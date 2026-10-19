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
                // 앱 색(진보라 배경·흰 글자)은 어두운 화면 기준이다. iOS처럼 고정하지 않으면
                // macOS 라이트 모드에서 사이드바가 밝아져 흰 글자가 거의 보이지 않는다.
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // "새 윈도우" 대체는 MacCommands의 .newItem 그룹("새 앨범…")이 담당
            MacCommands(appState: appState)
        }
    }
}
