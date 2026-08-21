import SwiftUI
import Combine
import Photos
import AppKit

// ============================================================
// MacAppState — 앱 전역 UI 상태 (사이드바 선택 등)
// 메뉴바 Commands·⌘단축키가 사이드바 선택을 구동할 수 있도록 공유한다.
// ============================================================

/// 확대 미리보기 대상 — 리뷰는 전체 사진, 그룹 비교는 그 그룹의 사진.
struct QuickLookRequest {
    var assets: [PHAsset]
    var index: Int
}

@MainActor
final class MacAppState: ObservableObject {
    @Published var selection: MacDestination? = .allPhotos

    /// 앱이 직접 소유하는 UndoManager.
    /// `@Environment(\.undoManager)`는 해당 뷰가 first responder 체인에 있을 때만 유효한데,
    /// NavigationSplitView의 detail 뷰는 사이드바가 포커스를 쥔 채 진입하면 nil이 되어
    /// 리뷰·그룹비교의 ⌘Z가 무반응이 된다. 소유권을 앱으로 옮겨 포커스와 분리한다.
    let undo = UndoManager()
    /// ⌘N 새 앨범 시트 (메뉴바 Commands → 루트 뷰)
    @Published var showNewAlbum = false
    /// 화면 하단 임시 안내 (앨범 없음 등). 표시 후 자동 소멸.
    @Published var toast: String?

    /// Space 확대 미리보기. detail 뷰가 아니라 **루트**에서 그려야
    /// 사이드바까지 덮는 창 전체 확대가 된다 (detail의 .overlay는 detail 영역에 갇힌다).
    @Published var quickLook: QuickLookRequest?
    /// 앨범 추가·제거, 즐겨찾기 변경 때마다 증가.
    /// 앨범 상세·즐겨찾기 화면이 이걸 보고 목록을 다시 읽는다.
    @Published var libraryRevision = 0

    /// 즐겨찾기된 사진 id 집합 — **모든 화면이 이 하나를 본다**.
    /// 화면마다 따로 조회하면 같은 사진이 어디선 하트가 있고 어디선 없는 상태가 된다.
    /// PHAsset.isFavorite은 페치 시점 스냅샷이라 신뢰할 수 없어 여기서 갱신해 쓴다.
    @Published private(set) var favoriteIDs: Set<String> = []

    func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    /// 라이브러리가 바뀌었음을 알린다 (앨범·즐겨찾기 화면 갱신 + 즐겨찾기 집합 재조회)
    func bumpLibrary() {
        libraryRevision += 1
        refreshFavoriteIDs()
    }

    func refreshFavoriteIDs() {
        Task {
            let ids: Set<String> = await Task.detached(priority: .utility) {
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "favorite == YES")
                let result = PHAsset.fetchAssets(with: options)
                var set: Set<String> = []
                result.enumerateObjects { asset, _, _ in set.insert(asset.localIdentifier) }
                return set
            }.value
            favoriteIDs = ids
        }
    }

    /// 즐겨찾기 설정·해제. 쓰기가 성공한 뒤에만 상태를 갱신한다.
    func setFavorite(_ id: String, to value: Bool) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest(for: asset).isFavorite = value
        }, completionHandler: { success, error in
            Task { @MainActor in
                guard success else {
                    self.showToast("즐겨찾기를 바꾸지 못했습니다")
                    print("ZAKAR Log: 즐겨찾기 실패 - \(error?.localizedDescription ?? "알 수 없음")")
                    return
                }
                if value { self.favoriteIDs.insert(id) } else { self.favoriteIDs.remove(id) }
                self.libraryRevision += 1
                self.showToast(value ? "즐겨찾기에 추가" : "즐겨찾기 해제")
            }
        })
    }

    /// 현재 값의 반대로 토글
    func toggleFavorite(_ id: String) { setFavorite(id, to: !isFavorite(id)) }

    // MARK: - 키 처리 (앱 전체 단일 NSEvent 모니터)
    // 화면별로 핸들러를 등록하고 현재 선택된 화면의 것만 호출한다.
    // 뷰마다 모니터를 달면 죽은 화면의 핸들러가 키를 계속 삼킬 수 있다.

    private var keyHandlers: [MacDestination: (MacKey, NSEvent.ModifierFlags) -> Bool] = [:]
    private var keyMonitor: Any?

    func registerKeys(for destination: MacDestination,
                      handler: @escaping (MacKey, NSEvent.ModifierFlags) -> Bool) {
        keyHandlers[destination] = handler
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                if event.window?.firstResponder is NSTextView { return event }   // 텍스트 편집 중엔 양보
                guard let key = MacKey(keyCode: event.keyCode) else { return event }
                return self.dispatchKey(key, event.modifierFlags) ? nil : event
            }
        }
    }

    func unregisterKeys(for destination: MacDestination) {
        keyHandlers[destination] = nil
    }

    private func dispatchKey(_ key: MacKey, _ mods: NSEvent.ModifierFlags) -> Bool {
        guard showNewAlbum == false else { return false }   // 시트가 떠 있으면 시트가 우선
        guard let destination = selection, let handler = keyHandlers[destination] else { return false }
        return handler(key, mods)
    }

    private var toastToken = 0

    func showToast(_ message: String, seconds: Double = 2.4) {
        toast = message
        toastToken += 1
        let token = toastToken
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }
}
