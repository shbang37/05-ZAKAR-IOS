import SwiftUI
import Combine

// ============================================================
// MacAppState — 앱 전역 UI 상태 (사이드바 선택 등)
// 메뉴바 Commands·⌘단축키가 사이드바 선택을 구동할 수 있도록 공유한다.
// ============================================================

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
