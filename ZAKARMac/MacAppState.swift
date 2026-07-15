import SwiftUI
import Combine

// ============================================================
// MacAppState — 앱 전역 UI 상태 (사이드바 선택 등)
// 메뉴바 Commands·⌘단축키가 사이드바 선택을 구동할 수 있도록 공유한다.
// ============================================================

@MainActor
final class MacAppState: ObservableObject {
    @Published var selection: MacDestination? = .allPhotos
}
