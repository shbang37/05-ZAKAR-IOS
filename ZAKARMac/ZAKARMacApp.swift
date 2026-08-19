import SwiftUI

// ============================================================
// ZAKAR Mac — 사진 정리 데스크탑 앱
// Phase 0: 타깃 부트스트랩 + PhotoKit 권한 스파이크
// (공유 코어 연결은 Phase 1, 실제 UI는 Phase 2~)
// ============================================================

@main
struct ZAKARMacApp: App {
    @StateObject private var photoManager = PhotoManager()
    @StateObject private var appState = MacAppState()

    init() {
        // 콘솔 리다이렉트 시 print가 블록 버퍼링되지 않도록 (디버깅 로그 즉시 노출)
        setvbuf(stdout, nil, _IONBF, 0)
    }

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environmentObject(photoManager)
                .environmentObject(appState)
                .frame(minWidth: 1040, idealWidth: 1280,
                       minHeight: 680, idealHeight: 840)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // "새 윈도우" 대체는 MacCommands의 .newItem 그룹("새 앨범…")이 담당
            MacCommands(appState: appState)
        }
    }
}
