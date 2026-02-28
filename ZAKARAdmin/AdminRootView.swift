import SwiftUI

// ============================================================
// MARK: - AdminRootView
// 로그인 상태에 따라 LoginView 또는 메인 레이아웃 표시
// ============================================================

struct AdminRootView: View {
    @EnvironmentObject var adminAuth: AdminAuthService

    var body: some View {
        Group {
            switch adminAuth.adminState {
            case .unauthenticated:
                AdminLoginView()

            case .notAdmin:
                NotAdminView()

            case .authenticated:
                AdminMainLayout()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: adminAuth.adminState)
    }
}

// ============================================================
// MARK: - AdminSplashView
// ============================================================

struct AdminSplashView: View {
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            VStack(spacing: 16) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                ProgressView()
                    .progressViewStyle(.circular)
                Text("ZAKAR Admin")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
    }
}

// ============================================================
// MARK: - AdminLoginView
// ============================================================

struct AdminLoginView: View {
    @EnvironmentObject var adminAuth: AdminAuthService
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusField: LoginField?

    enum LoginField { case email, password }

    var body: some View {
        ZStack {
            // 배경 그라디언트
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.15), Color(red: 0.05, green: 0.05, blue: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                // 로고 영역
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 80, height: 80)
                        Image(systemName: "shield.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)
                    }
                    Text("ZAKAR Admin")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Text("은혜의 교회 관리자 전용")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                // 로그인 카드
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("이메일")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("admin@church.org", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusField, equals: .email)
                            .onSubmit { focusField = .password }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("비밀번호")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("비밀번호", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusField, equals: .password)
                            .onSubmit { login() }
                    }

                    if let err = adminAuth.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: login) {
                        HStack {
                            if adminAuth.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                            }
                            Text("관리자 로그인")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.isEmpty || password.isEmpty || adminAuth.isLoading)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .frame(width: 360)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .onAppear { focusField = .email }
    }

    private func login() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task { await adminAuth.signIn(email: email, password: password) }
    }
}

// ============================================================
// MARK: - NotAdminView
// ============================================================

struct NotAdminView: View {
    @EnvironmentObject var adminAuth: AdminAuthService

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("관리자 권한 없음")
                    .font(.title2.bold())
                if let msg = adminAuth.errorMessage {
                    Text(msg)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("다른 계정으로 로그인") {
                    adminAuth.signOut()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
        }
        .frame(minWidth: 960, minHeight: 620)
    }
}

// ============================================================
// MARK: - AdminMainLayout  (사이드바 + 컨텐츠)
// ============================================================

struct AdminMainLayout: View {
    @EnvironmentObject var adminAuth: AdminAuthService
    @State private var selectedSection: SidebarSection = .users

    enum SidebarSection: String, CaseIterable, Identifiable {
        case users   = "사용자 관리"
        case stats   = "통계"
        case settings = "설정"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .users:    return "person.3.fill"
            case .stats:    return "chart.bar.fill"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // 사이드바
            VStack(alignment: .leading, spacing: 0) {
                // 관리자 정보
                if let admin = adminAuth.currentAdmin {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(admin.name)
                            .font(.headline)
                        Text(admin.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }

                // 메뉴
                List(SidebarSection.allCases, selection: $selectedSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Spacer()
                Divider()

                // 로그아웃 버튼
                Button(role: .destructive) {
                    adminAuth.signOut()
                } label: {
                    Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch selectedSection {
            case .users:
                AdminUserListView()
            case .stats:
                AdminStatsView()
            case .settings:
                AdminSettingsView()
                    .environmentObject(adminAuth)
            }
        }
    }
}
