import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

// Firebase는 앱 시작 직후 configure()를 호출해야 합니다.
// AppDelegate를 통해 가장 이른 시점에 초기화합니다.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("🟢 ZAKAR Log: App launching - Initializing Firebase")
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        print("🟢 ZAKAR Log: Firebase configured successfully")
        #endif
        return true
    }
}

@main
struct ZAKARApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var photoManager = PhotoManager()
    @StateObject private var auth = AuthService()
    @StateObject private var driveService = GoogleDriveService(userID: "test-user")

    init() {
        print("🟢 ZAKAR Log: ZAKARApp.init() - App initialized")
    }

    var body: some Scene {
        let _ = print("🟢 ZAKAR Log: ZAKARApp.body - Creating WindowGroup")
        return WindowGroup {
            RootView()
                .environmentObject(photoManager)
                .environmentObject(auth)
                .environmentObject(driveService)
                .onAppear {
                    print("🟢 ZAKAR Log: RootView.onAppear - View appeared")
                }
        }
    }
}

// MARK: - RootView: 인증 상태에 따라 화면 분기
struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var initializationComplete = false

    var body: some View {
        let _ = print("🟠 ZAKAR Log: RootView.body - Auth state: \(auth.authState), initComplete: \(initializationComplete)")
        
        // 초기화가 완료될 때까지 Fallback UI만 표시
        if !initializationComplete {
            return AnyView(
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                            Text("ZAKAR 시작 중...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    )
                    .task {
                        print("🟢 ZAKAR Log: RootView.task - starting initialization")
                        auth.checkCurrentSession()
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        withAnimation {
                            initializationComplete = true
                        }
                        print("🟢 ZAKAR Log: RootView initialization complete")
                    }
            )
        }
        
        // 초기화 완료 후 실제 앱 화면 표시
        return AnyView(
            Group {
                switch auth.authState {
                case .loading:
                    let _ = print("🟠 ZAKAR Log: Rendering .loading state (SplashView)")
                    SplashView()

                case .unauthenticated:
                    let _ = print("🟠 ZAKAR Log: Rendering .unauthenticated state (LoginView)")
                    LoginView()

                case .pendingApproval:
                    let _ = print("🟠 ZAKAR Log: Rendering .pendingApproval state")
                    PendingApprovalView()

                case .rejected:
                    let _ = print("🟠 ZAKAR Log: Rendering .rejected state")
                    RejectedView()

                case .approved:
                    let _ = print("🟠 ZAKAR Log: Rendering .approved state (MainTabView)")
                    MainTabView()
                }
            }
            .animation(.easeInOut(duration: 0.35), value: auth.authState)
        )
    }
}

// MARK: - 스플래시 (로딩 중)
struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        let _ = print("🟣 ZAKAR Log: SplashView.body - Rendering SplashView")
        return ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    Image(systemName: "photo.on.rectangle.angled")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.white)
                }
                Text("ZAKAR")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(4)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            print("🟣 ZAKAR Log: SplashView.onAppear - SplashView appeared")
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

