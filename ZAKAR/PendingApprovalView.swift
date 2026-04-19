import SwiftUI

// MARK: - 승인 대기 화면
struct PendingApprovalView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var pulseScale: CGFloat = 1.0
    @State private var appear = false

    var body: some View {
        ZStack {
            PremiumBackground(style: .warm)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // 아이콘 (맥박 애니메이션)
                ZStack {
                    Circle()
                        .stroke(AppTheme.gracefulGold.opacity(0.15), lineWidth: 1)
                        .frame(width: 130, height: 130)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - pulseScale)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 96, height: 96)
                        .overlay(Circle().stroke(AppTheme.gracefulGold.opacity(0.4), lineWidth: 1.5))
                        .shadow(color: AppTheme.gracefulGold.opacity(0.15), radius: 16)

                    Image(systemName: "clock.badge")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(AppTheme.gracefulGold)
                }
                .scaleEffect(appear ? 1 : 0.7)
                .opacity(appear ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appear)

                Spacer().frame(height: 32)

                // 텍스트
                VStack(spacing: 10) {
                    Text("승인 대기 중")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("공동체 관리자의 승인 후 이용하실 수 있습니다.\n담당자에게 문의해 주세요.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                }
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: appear)

                Spacer().frame(height: 36)

                // 사용자 정보 카드
                if let user = auth.currentUser {
                    userInfoCard(user: user)
                        .padding(.horizontal, 28)
                        .opacity(appear ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.35), value: appear)
                }

                Spacer().frame(height: 24)

                // 안내 스텝
                waitingSteps
                    .padding(.horizontal, 28)
                    .opacity(appear ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.45), value: appear)

                Spacer()

                // 로그아웃 버튼
                Button {
                    auth.signOut()
                } label: {
                    Text("다른 계정으로 로그인")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .padding(.bottom, 44)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.55), value: appear)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            appear = true
            startPulse()
            // 승인 상태 실시간 리스닝
            if let uid = auth.currentUser?.id {
                auth.listenForApprovalChange(uid: uid)
            }
        }
    }

    private func userInfoCard(user: UserRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                Text(String(user.name.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(user.email)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Text(user.role.displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.gracefulGold.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.gracefulGold.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    private var waitingSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(number: "1", text: "관리자에게 알림이 전송되었습니다", done: true)
            stepRow(number: "2", text: "관리자 검토 및 승인 중", done: false, isActive: true)
            stepRow(number: "3", text: "승인 완료 시 자동으로 앱이 열립니다", done: false)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    private func stepRow(number: String, text: String, done: Bool, isActive: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green.opacity(0.8) : (isActive ? AppTheme.gracefulGold.opacity(0.7) : Color.white.opacity(0.1)))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text(number)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isActive ? .white : .white.opacity(0.4))
                }
            }
            Text(text)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .white : .white.opacity(done ? 0.7 : 0.4))
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulseScale = 1.5
        }
    }
}

// MARK: - 승인 거절 화면
struct RejectedView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var appear = false

    var body: some View {
        ZStack {
            PremiumBackground(style: .warm)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 96, height: 96)
                        .overlay(Circle().stroke(Color.red.opacity(0.4), lineWidth: 1.5))
                    Image(systemName: "xmark.shield.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                }
                .scaleEffect(appear ? 1 : 0.7)
                .opacity(appear ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appear)

                Spacer().frame(height: 28)

                VStack(spacing: 10) {
                    Text("접근이 거절되었습니다")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("관리자에 의해 접근이 거절되었습니다.\n담당 사역자에게 문의해주세요.")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                }
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: appear)

                Spacer()

                Button { auth.signOut() } label: {
                    Text("로그아웃")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 44)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.4), value: appear)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { appear = true }
    }
}

#Preview {
    PendingApprovalView()
        .environmentObject(AuthService())
}
