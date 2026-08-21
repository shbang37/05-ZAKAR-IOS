import SwiftUI
import Photos
import AppKit

// ============================================================
// QuickLookOverlay — Space 확대 미리보기
// **창 전체**를 덮고 가용 영역을 꽉 채워 보여준다(잘림 없음). ←→로 순회, Space/Esc로 닫기.
// 루트(MacRootView)에서 그려지며, 키 입력은 각 모드의 macKeys 핸들러가 처리한다.
// ============================================================

struct QuickLookOverlay: View {
    let assets: [PHAsset]
    @Binding var index: Int
    let onClose: () -> Void

    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?

    private var asset: PHAsset? {
        assets.indices.contains(index) ? assets[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 12) {
                // 가용 영역을 꽉 채우는 aspect-fit — scaleEffect로 키우면 넘치는 만큼 잘린다
                ZStack {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        ProgressView().tint(AppTheme.gracefulGold)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let asset {
                    Text(metadataLine(asset))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Text("←→ 이동 · Space/Esc 닫기")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .onAppear { load() }
        .onChange(of: index) { _, _ in load() }
    }

    /// 화면 해상도에 맞춘 요청 크기 — 창 전체로 키우므로 1600px로는 뭉갠다
    private var fullScreenTarget: CGSize {
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return CGSize(width: screen.width * scale, height: screen.height * scale)
    }

    private func load() {
        guard let asset else { return }
        if let rid = requestID { ThumbnailCache.manager.cancelImageRequest(rid) }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic   // 저화질 즉시 → 고화질 교체 (전체화면은 원본이 커서 느리다)
        options.isNetworkAccessAllowed = true
        let requested = asset.localIdentifier
        requestID = ThumbnailCache.manager.requestImage(
            for: asset,
            targetSize: fullScreenTarget,
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
