import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

// Firebase는 앱 시작 직후 configure()를 호출해야 합니다.
// AppDelegate를 통해 가장 이른 시점에 초기화합니다.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
        return true
    }
}

@main
struct ZAKARApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var photoManager = PhotoManager()
    @StateObject private var auth = AuthService()
    @StateObject private var driveService = GoogleDriveService(userID: "")

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(photoManager)
                .environmentObject(auth)
                .environmentObject(driveService)
                .onAppear {
                    // AppDelegate에서 FirebaseApp.configure() 완료 후
                    // 메인 스레드에서 Auth 리스너 등록
                    auth.checkCurrentSession()
                }
                .task {
                    // Firebase 응답 없을 때 5초 후 로그인 화면으로 폴백
                    try? await Task.sleep(for: .seconds(5))
                    if auth.authState == .loading {
                        auth.authState = .unauthenticated
                    }
                }
                .onChange(of: auth.currentUser?.id) {
                    // 사용자 로그인/로그아웃 시 drive 서비스 재생성
                    if let uid = auth.currentUser?.id {
                        driveService.updateUser(userID: uid)
                    }
                }
        }
    }
}

// MARK: - RootView: 인증 상태에 따라 화면 분기
struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var photoManager: PhotoManager

    var body: some View {
        Group {
            switch auth.authState {

            case .loading:
                // 앱 시작 시 Firebase 세션 확인 중
                SplashView()

            case .unauthenticated:
                // 로그인/회원가입 화면
                LoginView()

            case .pendingApproval:
                // 승인 대기 화면 (실시간 리스닝 → 승인 시 자동 전환)
                PendingApprovalView()

            case .rejected:
                // 접근 거절 화면
                RejectedView()

            case .approved:
                // 정상 사용자 → 온보딩(최초) or 메인 탭
                MainTabView()
                    .task {
                        photoManager.fetchPhotos()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            photoManager.analyzeSimilaritiesIfNeeded()
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.authState)
    }
}

// MARK: - 스플래시 (로딩 중)
struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 80, height: 80)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
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
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}
