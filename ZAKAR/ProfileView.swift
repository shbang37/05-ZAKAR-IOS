import SwiftUI

// MARK: - 내 정보 화면 (일반 사용자)
struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var drive: GoogleDriveService
    @State private var showSignOutAlert = false
    @State private var showDriveError = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeleting = false

    var body: some View {
        NavigationView {
            ZStack {
                PremiumBackground(style: .deep)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 프로필 카드
                        profileCard

                        // 구글 드라이브 연결 카드
                        driveConnectionCard

                        // 역할 안내
                        roleInfoCard

                        Spacer(minLength: 20)

                        // 로그아웃 버튼
                        signOutButton
                        
                        // 계정 삭제 버튼
                        deleteAccountButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("내 정보")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .alert("로그아웃", isPresented: $showSignOutAlert) {
            Button("취소", role: .cancel) {}
            Button("로그아웃", role: .destructive) { auth.signOut() }
        } message: {
            Text("로그아웃 하시겠습니까?")
        }
        .alert("계정 삭제", isPresented: $showDeleteAccountAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text("계정을 삭제하면 모든 데이터가 영구적으로 삭제됩니다.\n이 작업은 취소할 수 없습니다.\n\n정말 삭제하시겠습니까?")
        }
    }

    // MARK: - 프로필 카드
    private var profileCard: some View {
        VStack(spacing: 16) {
            // 아바타
            ZStack {
                Circle()
                    .fill(AppTheme.dualGradient)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.gracefulGold.opacity(0.4), lineWidth: 2)
                    )
                    .shadow(color: AppTheme.gracefulGold.opacity(0.3), radius: 15)
                Text(auth.currentUser?.name.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 6) {
                Text(auth.currentUser?.name ?? "사용자")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(auth.currentUser?.department ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            // 역할 및 상태 배지
            if let user = auth.currentUser {
                HStack(spacing: 8) {
                    roleBadge(user.role)
                    statusBadge(user.status)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(GlassCard(cornerRadius: 20))
    }

    private func roleBadge(_ role: UserRecord.UserRole) -> some View {
        let color: Color = role == .admin ? AppTheme.lightPurple : (role == .reporter ? AppTheme.gracefulGold : AppTheme.gracefulGold)
        return Text(role.displayName)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }

    private func statusBadge(_ status: UserRecord.UserStatus) -> some View {
        let color: Color = status == .approved ? .green : (status == .pending ? .orange : .red)
        return Text(status.displayName)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - 구글 드라이브 연결 카드
    private var driveConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.purpleGradient)
                Text("구글 드라이브 연동")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if drive.isLinked {
                    Circle()
                        .fill(AppTheme.gracefulGold)
                        .frame(width: 8, height: 8)
                        .shadow(color: AppTheme.gracefulGold.opacity(0.5), radius: 4)
                }
            }

            if drive.isLinked {
                // 연결됨 상태
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.gracefulGold)
                        Text("연결됨")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    if let email = drive.linkedEmail {
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Button {
                        drive.unlink()
                    } label: {
                        Text("연결 해제")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
            } else {
                // 미연결 상태
                VStack(alignment: .leading, spacing: 8) {
                    Text("구글 드라이브에 연결하여\n사진을 자동으로 백업하세요.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineSpacing(3)
                    
                    Button {
                        Task {
                            await drive.link()
                            if drive.linkError != nil {
                                showDriveError = true
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if drive.isLinking {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "link")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("지금 연결하기")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.purpleGradient)
                        .clipShape(Capsule())
                    }
                    .disabled(drive.isLinking)
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(GlassCard(cornerRadius: 16))
        .alert("연결 오류", isPresented: $showDriveError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(drive.linkError ?? "알 수 없는 오류")
        }
    }

    // MARK: - 역할 안내 카드
    private var roleInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("역할 안내", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.dualGradient)

            VStack(spacing: 8) {
                roleRow(icon: "person.fill", role: "동역자",
                        desc: "사진 정리 및 아카이브 열람")
                roleRow(icon: "newspaper.fill", role: "기자부",
                        desc: "사진 업로드 및 앨범 관리")
                roleRow(icon: "shield.fill", role: "관리자",
                        desc: "전체 관리 및 사용자 승인")
            }
        }
        .padding(16)
        .background(GlassCard(cornerRadius: 16))
    }

    private func roleRow(icon: String, role: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(role)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // MARK: - 로그아웃 버튼
    private var signOutButton: some View {
        Button {
            showSignOutAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("로그아웃")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.red.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.25), lineWidth: 0.5))
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - 계정 삭제 버튼
    private var deleteAccountButton: some View {
        Button {
            showDeleteAccountAlert = true
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(isDeleting ? "삭제 중..." : "계정 삭제")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        }
        .disabled(isDeleting)
    }

    // MARK: - 계정 삭제 로직
    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            // 1. LocalDB 초기화
            LocalDB.clearAll()

            // 2. Google Drive 연결 해제
            drive.unlink()

            // 3. Firebase 계정 삭제 (Firestore + Authentication)
            try await auth.deleteAccount()

            // 성공 시 자동으로 로그인 화면으로 이동 (authState가 .unauthenticated로 변경됨)
        } catch {
            // 오류 처리
            auth.errorMessage = "계정 삭제 실패: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthService())
        .environmentObject(GoogleDriveService(userID: "preview"))
}
