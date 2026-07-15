import Foundation
import Photos
import CoreGraphics
import Combine

// ============================================================
// 썸네일 공유 캐싱 인프라 (iOS·macOS 공용, 순수 PhotoKit)
// 뷰 계층(UIImage/NSImage)과 분리된 캐싱 매니저·프리페처.
// 각 플랫폼의 썸네일 View가 ThumbnailCache.manager로 요청/캐시를 공유한다.
// ============================================================

// 앱 전역 공유 썸네일 캐싱 매니저 — 셀마다 PHImageManager.default()에 개별 요청하면
// 스크롤 시 요청·디코드가 몰려 프레임이 드랍된다. 하나를 공유해 중복 요청을 병합하고
// 디코드 결과를 재사용하며, 스크롤 방향 프리페치(startCachingImages)도 이 인스턴스로 구동한다.
// startCachingImages와 requestImage가 같은 캐시를 맞히려면 targetSize·contentMode·options가
// 일치해야 하므로 여기서 중앙 정의한다.
enum ThumbnailCache {
    static let manager = PHCachingImageManager()
    // 프리페치와 요청이 같은 캐시 엔트리를 공유하도록 contentMode도 여기에 고정
    static let contentMode: PHImageContentMode = .aspectFill

    // 렌더와 프리페치가 같은 크기를 써야 캐시가 적중하므로 화면별 썸네일 크기도 여기서 소유한다
    static let gridSize: CGFloat = 125   // iOS 모든 사진 그리드
    static let rowSize: CGFloat = 96     // iOS 유사 그룹 행 가로 스크롤
    static let macGridSize: CGFloat = 160 // macOS 모든 사진 그리드 (데스크탑 밀도)

    static func targetSize(for size: CGFloat, scale: CGFloat) -> CGSize {
        CGSize(width: size * scale, height: size * scale)
    }

    static func requestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // 콜백 1회 (opportunistic의 저→고화질 2회 재렌더 제거)
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }
}

// 스크롤 방향 프리페치 구동기 — 셀이 나타날 때 앞뒤 윈도우의 썸네일을 미리 디코드해둔다.
// SwiftUI에는 UICollectionView 같은 prefetch API가 없어 셀 onAppear 인덱스로 윈도우를 민다.
// 전량 캐싱은 대용량 라이브러리에서 메모리를 폭증시키므로 반드시 윈도우로 제한할 것.
// stopCachingImagesForAllAssets()는 공유 매니저를 쓰는 다른 화면의 캐시까지 날려
// 그 화면이 "이미 캐싱됨"으로 오판하게 만든다 — 이 인스턴스가 시작한 에셋만 정확히 해제한다.
final class ThumbnailPrefetcher: ObservableObject {
    private static let lookBehind = 8
    private static let lookAhead = 24
    private static let groupLookBehind = 1
    private static let groupLookAhead = 4

    private var cached: [String: PHAsset] = [:]
    private var cachedTargetSize: CGSize = .zero

    /// 그리드용 — 인덱스 주변 앞뒤 윈도우
    static func window(_ assets: [PHAsset], around index: Int) -> ArraySlice<PHAsset> {
        guard !assets.isEmpty else { return [] }
        let lower = max(0, index - lookBehind)
        let upper = min(assets.count, index + lookAhead)
        guard lower < upper else { return [] }
        return assets[lower..<upper]
    }

    /// 유사 그룹 리스트용 — 앞뒤 그룹들의 에셋을 평탄화한 윈도우
    static func groupWindow(_ groups: [[PHAsset]], around index: Int) -> [PHAsset] {
        guard !groups.isEmpty else { return [] }
        let lower = max(0, index - groupLookBehind)
        let upper = min(groups.count, index + groupLookAhead)
        guard lower < upper else { return [] }
        return groups[lower..<upper].flatMap { $0 }
    }

    func update<S: Sequence>(window: S, size: CGFloat, scale: CGFloat) where S.Element == PHAsset {
        let targetSize = ThumbnailCache.targetSize(for: size, scale: scale)
        if targetSize != cachedTargetSize {
            stopAll()                       // 이전 크기로 잡아둔 캐싱을 먼저 해제
            cachedTargetSize = targetSize
        }

        var next: [String: PHAsset] = [:]
        for asset in window { next[asset.localIdentifier] = asset }

        // 윈도우에 새로 들어온 것만 캐싱 시작, 빠져나간 것만 해제
        let toStart = next.compactMap { cached[$0.key] == nil ? $0.value : nil }
        let toStop = cached.compactMap { next[$0.key] == nil ? $0.value : nil }
        guard !toStart.isEmpty || !toStop.isEmpty else { return }

        let options = ThumbnailCache.requestOptions()
        if !toStop.isEmpty {
            ThumbnailCache.manager.stopCachingImages(for: toStop, targetSize: targetSize, contentMode: ThumbnailCache.contentMode, options: options)
        }
        if !toStart.isEmpty {
            ThumbnailCache.manager.startCachingImages(for: toStart, targetSize: targetSize, contentMode: ThumbnailCache.contentMode, options: options)
        }
        cached = next
    }

    /// 목록 교체·화면 이탈 시 이 인스턴스가 시작한 캐싱만 해제
    func stopAll() {
        guard !cached.isEmpty else { return }
        ThumbnailCache.manager.stopCachingImages(
            for: Array(cached.values),
            targetSize: cachedTargetSize,
            contentMode: ThumbnailCache.contentMode,
            options: ThumbnailCache.requestOptions()
        )
        cached = [:]
    }
}
