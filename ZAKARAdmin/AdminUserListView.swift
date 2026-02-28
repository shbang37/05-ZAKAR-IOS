import SwiftUI
import Combine

// ============================================================
// MARK: - AdminUserListView
// 전체 사용자 목록 + 탭 필터 (대기/승인/거절)
// ============================================================

struct AdminUserListView: View {
    @EnvironmentObject var adminAuth: AdminAuthService
    @StateObject private var vm = AdminUserListVM()
    @State private var selectedUser: UserRecord?
    @State private var filterStatus: UserRecord.UserStatus? = nil  // nil = 전체

    var filteredUsers: [UserRecord] {
        if let status = filterStatus {
            return vm.users.filter { $0.status == status }
        }
        return vm.users
    }

    var body: some View {
        HSplitView {
            // ── 왼쪽: 사용자 목록 ──
            VStack(spacing: 0) {
                // 툴바 영역
                HStack {
                    Text("사용자 목록")
                        .font(.title3.bold())

                    Spacer()

                    // 새로고침
                    Button {
                        vm.idToken = adminAuth.idToken
                        vm.projectId = adminAuth.projectId
                        Task { await vm.fetchUsers() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isLoading)

                    // 필터 피커
                    Picker("필터", selection: $filterStatus) {
                        Text("전체").tag(Optional<UserRecord.UserStatus>.none)
                        Text("대기").tag(Optional<UserRecord.UserStatus>.some(.pending))
                        Text("승인").tag(Optional<UserRecord.UserStatus>.some(.approved))
                        Text("거절").tag(Optional<UserRecord.UserStatus>.some(.rejected))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if vm.isLoading {
                    Spacer()
                    ProgressView("불러오는 중...")
                    Spacer()
                } else if filteredUsers.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("사용자가 없습니다")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(filteredUsers, selection: $selectedUser) { user in
                        UserListRow(user: user)
                            .tag(user)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }

                // 하단 상태바
                Divider()
                HStack {
                    let pendingCount = vm.users.filter { $0.status == .pending }.count
                    if pendingCount > 0 {
                        Label("\(pendingCount)명 승인 대기 중", systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("총 \(vm.users.count)명")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 300, idealWidth: 360)

            // ── 오른쪽: 사용자 상세 ──
            if let user = selectedUser {
                AdminUserDetailView(
                    user: user,
                    idToken: adminAuth.idToken,
                    projectId: adminAuth.projectId
                ) { updatedUser in
                    vm.applyUpdate(updatedUser)
                    selectedUser = updatedUser
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("사용자를 선택하세요")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .task {
            vm.idToken = adminAuth.idToken
            vm.projectId = adminAuth.projectId
            await vm.fetchUsers()
        }
        .alert("오류", isPresented: .constant(vm.errorMessage != nil)) {
            Button("확인") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}

// ============================================================
// MARK: - UserListRow
// ============================================================

struct UserListRow: View {
    let user: UserRecord

    var body: some View {
        HStack(spacing: 10) {
            // 아바타
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(user.name.prefix(1))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(avatarColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.system(size: 13, weight: .medium))
                Text(user.department.isEmpty ? user.email : "\(user.department) · \(user.email)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                StatusBadge(status: user.status)
                Text(user.role.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var avatarColor: Color {
        switch user.status {
        case .pending:  return .orange
        case .approved: return .blue
        case .rejected: return .red
        }
    }
}

// ============================================================
// MARK: - StatusBadge
// ============================================================

struct StatusBadge: View {
    let status: UserRecord.UserStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .pending:  return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

// ============================================================
// MARK: - AdminUserListVM (Firestore REST API 방식)
// ============================================================

@MainActor
final class AdminUserListVM: ObservableObject {
    @Published var users: [UserRecord] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // AdminAuthService에서 주입받는 인증 정보
    var idToken: String?
    var projectId: String?

    func fetchUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let token = idToken, let pid = projectId else {
            errorMessage = "인증 정보가 없습니다. 다시 로그인해주세요."
            return
        }

        // Firestore REST API: users 컬렉션 전체 조회
        let urlStr = "https://firestore.googleapis.com/v1/projects/\(pid)/databases/(default)/documents/users"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let documents = json["documents"] as? [[String: Any]] else {
                // 문서가 없는 경우 (빈 컬렉션)
                users = []
                return
            }

            users = documents.compactMap { doc -> UserRecord? in
                guard let name = doc["name"] as? String,
                      let fields = doc["fields"] as? [String: Any] else { return nil }
                // document name의 마지막 경로 세그먼트가 uid
                let uid = name.components(separatedBy: "/").last ?? ""
                return UserRecord(firestoreFields: fields, id: uid)
            }
            // requestedAt 기준 내림차순 정렬
            users.sort { $0.requestedAt > $1.requestedAt }

        } catch {
            errorMessage = "사용자 목록을 불러올 수 없습니다: \(error.localizedDescription)"
        }
    }

    func applyUpdate(_ updated: UserRecord) {
        if let idx = users.firstIndex(where: { $0.id == updated.id }) {
            users[idx] = updated
        }
    }
}

// MARK: - UserRecord ← Firestore REST fields 파싱
extension UserRecord {
    /// Firestore REST API의 fields 딕셔너리에서 UserRecord 생성
    init?(firestoreFields fields: [String: Any], id: String) {
        guard
            let email     = (fields["email"]   as? [String: Any])?["stringValue"] as? String,
            let name      = (fields["name"]    as? [String: Any])?["stringValue"] as? String,
            let roleRaw   = (fields["role"]    as? [String: Any])?["stringValue"] as? String,
            let statusRaw = (fields["status"]  as? [String: Any])?["stringValue"] as? String,
            let role      = UserRole(rawValue: roleRaw),
            let status    = UserStatus(rawValue: statusRaw)
        else { return nil }

        self.id          = id
        self.email       = email
        self.name        = name
        self.department  = (fields["department"] as? [String: Any])?["stringValue"] as? String ?? ""
        self.role        = role
        self.status      = status

        // requestedAt: Firestore REST는 timestampValue를 ISO8601 문자열로 반환
        if let tsStr = (fields["requestedAt"] as? [String: Any])?["timestampValue"] as? String {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.requestedAt = fmt.date(from: tsStr) ?? Date()
        } else {
            self.requestedAt = Date()
        }

        if let tsStr = (fields["approvedAt"] as? [String: Any])?["timestampValue"] as? String {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.approvedAt = fmt.date(from: tsStr)
        } else {
            self.approvedAt = nil
        }
    }
}

// ============================================================
// MARK: - AdminStatsView (간단한 통계 화면)
// ============================================================

struct AdminStatsView: View {
    @EnvironmentObject var adminAuth: AdminAuthService
    @StateObject private var vm = AdminUserListVM()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                StatCard(title: "전체 사용자", value: "\(vm.users.count)", icon: "person.3.fill", color: .blue)
                StatCard(title: "승인 대기", value: "\(vm.users.filter { $0.status == .pending }.count)", icon: "clock.fill", color: .orange)
                StatCard(title: "승인됨", value: "\(vm.users.filter { $0.status == .approved }.count)", icon: "checkmark.circle.fill", color: .green)
                StatCard(title: "거절됨", value: "\(vm.users.filter { $0.status == .rejected }.count)", icon: "xmark.circle.fill", color: .red)
                StatCard(title: "기자부", value: "\(vm.users.filter { $0.role == .reporter }.count)", icon: "camera.fill", color: .purple)
                StatCard(title: "관리자", value: "\(vm.users.filter { $0.role == .admin }.count)", icon: "shield.fill", color: .indigo)
            }
            .padding(24)
        }
        .navigationTitle("통계")
        .task {
            vm.idToken = adminAuth.idToken
            vm.projectId = adminAuth.projectId
            await vm.fetchUsers()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 36, weight: .bold))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// ============================================================
// MARK: - UserRecord dummy data (Firebase 없을 때)
// ============================================================

extension UserRecord {
    static var dummySamples: [UserRecord] {
        [
            UserRecord(id: "uid1", email: "kim@church.org", name: "김철수", department: "송도청", role: .member, status: .pending, requestedAt: Date().addingTimeInterval(-3600), approvedAt: nil),
            UserRecord(id: "uid2", email: "lee@church.org", name: "이영희", department: "또래청", role: .reporter, status: .approved, requestedAt: Date().addingTimeInterval(-86400), approvedAt: Date().addingTimeInterval(-82800)),
            UserRecord(id: "uid3", email: "park@church.org", name: "박민수", department: "미들청", role: .member, status: .rejected, requestedAt: Date().addingTimeInterval(-172800), approvedAt: nil),
            UserRecord(id: "uid4", email: "choi@church.org", name: "최지연", department: "열린청", role: .reporter, status: .pending, requestedAt: Date().addingTimeInterval(-7200), approvedAt: nil),
            UserRecord(id: "uid5", email: "admin@church.org", name: "관리자", department: "관리", role: .admin, status: .approved, requestedAt: Date().addingTimeInterval(-259200), approvedAt: Date().addingTimeInterval(-255600)),
        ]
    }
}
