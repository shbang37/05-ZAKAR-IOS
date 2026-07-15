import SwiftUI
import Photos
import AppKit

// ============================================================
// MacAssetThumbnail — macOS 썸네일 셀 (NSImage)
// iOS AssetThumbnail(UIImage)의 macOS 대응. 공유 ThumbnailCache로
// 프리페치된 캐시를 그대로 적중시킨다. (셀 identity는 localIdentifier)
// ============================================================

struct MacAssetThumbnail: View {
    let asset: PHAsset
    let size: CGFloat
    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else {
                // 빠른 스크롤 시 스피너 남발 방지 — 단색 플레이스홀더
                Rectangle().fill(Color.white.opacity(0.06))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .contentShape(Rectangle())
        .onAppear { request() }
        .onChange(of: asset.localIdentifier) { _, _ in
            image = nil
            request()
        }
        .onDisappear {
            if let rid = requestID {
                ThumbnailCache.manager.cancelImageRequest(rid)
                requestID = nil
            }
        }
    }

    private func request() {
        if let rid = requestID {
            ThumbnailCache.manager.cancelImageRequest(rid)
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let targetSize = ThumbnailCache.targetSize(for: size, scale: scale)
        let requestedID = asset.localIdentifier
        requestID = ThumbnailCache.manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: ThumbnailCache.contentMode,
            options: ThumbnailCache.requestOptions()
        ) { img, _ in
            Task { @MainActor in
                guard self.asset.localIdentifier == requestedID else { return }
                self.image = img
            }
        }
    }
}
