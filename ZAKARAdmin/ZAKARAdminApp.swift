import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

// ============================================================
// ZAKAR Admin — macOS 관리자 전용 앱
// ============================================================

@main
struct ZAKARAdminApp: App {
    @StateObject private var adminAuth = AdminAuthService()

    init() {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AdminRootView()
                .environmentObject(adminAuth)
                .frame(minWidth: 960, idealWidth: 1100, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
        }

        // 설정 창 (⌘,)
        Settings {
            AdminSettingsView()
                .environmentObject(adminAuth)
        }
    }
}
