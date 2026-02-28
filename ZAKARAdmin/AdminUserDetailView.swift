import SwiftUI
import Combine

// ============================================================
// MARK: - AdminUserDetailView
// 개별 사용자 상세 정보 + 승인/거절/역할 변경
// ============================================================

struct AdminUserDetailView: View {
    let user: UserRecord
    let idToken: String?
    let projectId: String?
    let onUpdate: (UserRecord) -> Void

    @StateObject private var vm: AdminUserDetailVM

    init(user: UserRecord, idToken: String?, projectId: String?, onUpdate: @escaping (UserRecord) -> Void) {
        self.user = user
        self.idToken = idToken
        self.projectId = projectId
        self.onUpdate = onUpdate
        _vm = StateObject(wrappedValue: AdminUserDetailVM(user: user, idToken: idToken, projectId: projectId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── 프로필 헤더 ──
                profileHeader

                Divider()

                // ── 상태 제어 ──
                statusSection

                Divider()

                // ── 역할 변경 ──
                roleSection

                // ── 위험 구역 ──
                Divider()
                dangerSection
            }
            .padding(28)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: vm.currentUser) {
            onUpdate(vm.currentUser)
        }
        .alert("오류", isPresented: .constant(vm.errorMessage != nil)) {
            Button("확인") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .overlay {
            if vm.isProcessing {
                ZStack {
                    Color.black.opacity(0.1)
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // ── 프로필 헤더 ──
    private var profileHeader: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(statusColor(vm.currentUser.status).opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(vm.currentUser.name.prefix(1))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(statusColor(vm.currentUser.status))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(vm.currentUser.name)
                        .font(.title2.bold())
                    StatusBadge(status: vm.currentUser.status)
                }
                Text(vm.currentUser.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !vm.currentUser.department.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2")
                            .font(.caption)
                        Text(vm.currentUser.department)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("가입 요청: \(formattedDate(vm.currentUser.requestedAt))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                if let approved = vm.currentUser.approvedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                        Text("승인: \(formattedDate(approved))")
                            .font(.caption)
                    }
                    .foregroundStyle(.green.opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // ── 상태 제어 ──
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("승인 상태 관리")
                .font(.headline)

            HStack(spacing: 12) {
                // 승인
                ActionButton(
                    label: "승인",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    isActive: vm.currentUser.status == .approved,
                    isDisabled: vm.currentUser.status == .approved || vm.isProcessing
                ) {
                    Task { await vm.updateStatus(.approved) }
                }

                // 거절
                ActionButton(
                    label: "거절",
                    icon: "xmark.circle.fill",
                    color: .red,
                    isActive: vm.currentUser.status == .rejected,
                    isDisabled: vm.currentUser.status == .rejected || vm.isProcessing
                ) {
                    Task { await vm.updateStatus(.rejected) }
                }

                // 대기로 되돌리기
                ActionButton(
                    label: "대기로 변경",
                    icon: "clock.fill",
                    color: .orange,
                    isActive: vm.currentUser.status == .pending,
                    isDisabled: vm.currentUser.status == .pending || vm.isProcessing
                ) {
                    Task { await vm.updateStatus(.pending) }
                }
            }

            // 상태 설명
            statusDescription
        }
    }

    @ViewBuilder
    private var statusDescription: some View {
        switch vm.currentUser.status {
        case .pending:
            InfoBanner(
                message: "이 사용자는 승인을 기다리고 있습니다. 승인하면 앱에 접근할 수 있습니다.",
                color: .orange,
                icon: "clock.fill"
            )
        case .approved:
            InfoBanner(
                message: "이 사용자는 승인되어 앱을 사용할 수 있습니다.",
                color: .green,
                icon: "checkmark.circle.fill"
            )
        case .rejected:
            InfoBanner(
                message: "이 사용자는 접근이 거절된 상태입니다. 앱 로그인 후 거절 화면이 표시됩니다.",
                color: .red,
                icon: "xmark.circle.fill"
            )
        }
    }

    // ── 역할 변경 ──
    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("역할 관리")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(UserRecord.UserRole.allCases, id: \.self) { role in
                    RoleButton(
                        role: role,
                        isSelected: vm.currentUser.role == role,
                        isDisabled: vm.isProcessing
                    ) {
                        Task { await vm.updateRole(role) }
                    }
                }
            }

            roleDescription
        }
    }

    @ViewBuilder
    private var roleDescription: some View {
        switch vm.currentUser.role {
        case .member:
            InfoBanner(message: "일반 동역자: 사진 조회 및 정리 기능을 사용할 수 있습니다.", color: .blue, icon: "person.fill")
        case .reporter:
            InfoBanner(message: "기자부: 사진 업로드 및 아카이브 관리 기능을 사용할 수 있습니다.", color: .purple, icon: "camera.fill")
        case .admin:
            InfoBanner(message: "관리자: 모든 기능과 사용자 관리 권한을 갖습니다.", color: .indigo, icon: "shield.fill")
        }
    }

    // ── 위험 구역 ──
    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("위험 구역")
                .font(.headline)
                .foregroundStyle(.red)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("계정 삭제")
                        .font(.subheadline.bold())
                    Text("Firestore에서 사용자 문서를 영구적으로 삭제합니다.\nFirebase Auth 계정은 별도로 삭제해야 합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) {
                    vm.showDeleteConfirm = true
                } label: {
                    Label("삭제", systemImage: "trash.fill")
                }
                .buttonStyle(.bordered)
                .disabled(vm.isProcessing)
            }
            .padding(16)
            .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
        .confirmationDialog(
            "'\(vm.currentUser.name)' 계정을 삭제하시겠습니까?",
            isPresented: $vm.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                Task { await vm.deleteUser() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 작업은 되돌릴 수 없습니다.")
        }
    }

    // ── 헬퍼 ──
    private func statusColor(_ status: UserRecord.UserStatus) -> Color {
        switch status {
        case .pending:  return .orange
        case .approved: return .blue
        case .rejected: return .red
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: date)
    }
}

// ============================================================
// MARK: - 재사용 컴포넌트
// ============================================================

struct ActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let isActive: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(isActive ? .bold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isActive ? color.opacity(0.15) : Color(NSColor.controlColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
                .foregroundStyle(isActive ? color : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

struct RoleButton: View {
    let role: UserRecord.UserRole
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    private var color: Color {
        switch role {
        case .member:   return .blue
        case .reporter: return .purple
        case .admin:    return .indigo
        }
    }

    private var icon: String {
        switch role {
        case .member:   return "person.fill"
        case .reporter: return "camera.fill"
        case .admin:    return "shield.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(role.displayName)
                    .font(.caption.bold())
            }
            .frame(width: 80, height: 60)
            .background(
                isSelected ? color.opacity(0.15) : Color(NSColor.controlColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
            .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

struct InfoBanner: View {
    let message: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

// ============================================================
// MARK: - AdminUserDetailVM (Firestore REST API 방식)
// ============================================================

@MainActor
final class AdminUserDetailVM: ObservableObject {
    @Published var currentUser: UserRecord
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var showDeleteConfirm = false

    var idToken: String?
    var projectId: String?

    init(user: UserRecord, idToken: String?, projectId: String?) {
        self.currentUser = user
        self.idToken = idToken
        self.projectId = projectId
    }

    func updateStatus(_ status: UserRecord.UserStatus) async {
        isProcessing = true
        defer { isProcessing = false }

        // Firestore REST PATCH로 status (및 approvedAt) 업데이트
        var firestoreFields: [String: Any] = [
            "status": ["stringValue": status.rawValue]
        ]
        if status == .approved {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            firestoreFields["approvedAt"] = ["timestampValue": iso.string(from: Date())]
        } else {
            firestoreFields["approvedAt"] = ["nullValue": NSNull()]
        }

        let success = await patchFirestore(fields: firestoreFields,
                                           updateMask: status == .approved ? ["status", "approvedAt"] : ["status", "approvedAt"])
        if success {
            var updated = currentUser
            updated.status = status
            updated.approvedAt = status == .approved ? Date() : nil
            currentUser = updated
        }
    }

    func updateRole(_ role: UserRecord.UserRole) async {
        isProcessing = true
        defer { isProcessing = false }

        let firestoreFields: [String: Any] = [
            "role": ["stringValue": role.rawValue]
        ]
        let success = await patchFirestore(fields: firestoreFields, updateMask: ["role"])
        if success {
            var updated = currentUser
            updated.role = role
            currentUser = updated
        }
    }

    func deleteUser() async {
        isProcessing = true
        defer { isProcessing = false }
        await deleteFirestore()
    }

    // MARK: - REST API helpers

    /// Firestore PATCH (부분 업데이트)
    private func patchFirestore(fields: [String: Any], updateMask: [String]) async -> Bool {
        guard let token = idToken, let pid = projectId else {
            errorMessage = "인증 정보가 없습니다."
            return false
        }

        // updateMask.fieldPaths 쿼리 파라미터 조합
        let maskParams = updateMask.map { "updateMask.fieldPaths=\($0)" }.joined(separator: "&")
        let urlStr = "https://firestore.googleapis.com/v1/projects/\(pid)/databases/(default)/documents/users/\(currentUser.id)?\(maskParams)"
        guard let url = URL(string: urlStr) else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let msg = (json?["error"] as? [String: Any])?["message"] as? String ?? "저장 실패"
                errorMessage = "저장 실패: \(msg)"
                return false
            }
            return true
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
            return false
        }
    }

    /// Firestore DELETE
    private func deleteFirestore() async {
        guard let token = idToken, let pid = projectId else {
            errorMessage = "인증 정보가 없습니다."
            return
        }

        let urlStr = "https://firestore.googleapis.com/v1/projects/\(pid)/databases/(default)/documents/users/\(currentUser.id)"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let msg = (json?["error"] as? [String: Any])?["message"] as? String ?? "삭제 실패"
                errorMessage = "삭제 실패: \(msg)"
            }
        } catch {
            errorMessage = "삭제 실패: \(error.localizedDescription)"
        }
    }
}
