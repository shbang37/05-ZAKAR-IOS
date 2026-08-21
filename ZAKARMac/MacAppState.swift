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
    /// 앨범에 사진이 추가·제거될 때마다 증가 — 앨범 상세 화면이 이걸 보고 다시 읽는다
    @Published var albumRevision = 0

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
