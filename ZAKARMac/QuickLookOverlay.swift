import SwiftUI
import Photos
import AppKit

// ============================================================
// QuickLookOverlay — Space 확대 미리보기
// 현재 항목을 크게(≈1.45×) 확대해 보여주고 ←→로 그룹 내 순회, Space/Esc로 닫는다.
// ============================================================

struct QuickLookOverlay: View {
    let assets: [PHAsset]
    @Binding var index: Int
    let onClose: () -> Void

    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?
    @FocusState private var focused: Bool

    private var asset: PHAsset? {
        assets.indices.contains(index) ? assets[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 16) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(1.45)
                        .clipped()
                } else {
                    ProgressView().tint(AppTheme.gracefulGold)
                }

                if let asset {
                    Text(metadataLine(asset))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text("←→ 이동 · Space/Esc 닫기")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(40)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { onClose(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.leftArrow) { cycle(-1); return .handled }
        .onKeyPress(.rightArrow) { cycle(1); return .handled }
        .onAppear { focused = true; load() }
        .onChange(of: index) { _, _ in load() }
    }

    private func cycle(_ delta: Int) {
        let next = index + delta
        guard assets.indices.contains(next) else { return }
        index = next
    }

    private func load() {
        guard let asset else { return }
        if let rid = requestID { ThumbnailCache.manager.cancelImageRequest(rid) }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let requested = asset.localIdentifier
        requestID = ThumbnailCache.manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 1600, height: 1600),
            contentMode: .aspectFit,
            options: options
        ) { img, _ in
            Task { @MainActor in
                guard self.asset?.localIdentifier == requested else { return }
                self.image = img
            }
        }
    }

    private func metadataLine(_ asset: PHAsset) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy.MM.dd"
        let date = asset.creationDate.map { df.string(from: $0) } ?? "—"
        return "\(date) · \(asset.pixelWidth)×\(asset.pixelHeight)"
    }
}
