import SwiftUI

// ============================================================
// MARK: - AdminSettingsView
// 관리자 설정 화면 (macOS Settings 창 + 메인 영역 공용)
// ============================================================

struct AdminSettingsView: View {
    @EnvironmentObject var adminAuth: AdminAuthService
    @State private var selectedTab: SettingsTab = .account

    enum SettingsTab: String, CaseIterable, Identifiable {
        case account = "계정"
        case departments = "부서 관리"
        case firestore = "Firestore"
        case about = "정보"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .account:     return "person.crop.circle"
            case .departments: return "building.2.fill"
            case .firestore:   return "cylinder.split.1x2"
            case .about:       return "info.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AccountSettingsTab()
                .tabItem { Label(SettingsTab.account.rawValue, systemImage: SettingsTab.account.icon) }
                .tag(SettingsTab.account)

            DepartmentsSettingsTab()
                .tabItem { Label(SettingsTab.departments.rawValue, systemImage: SettingsTab.departments.icon) }
                .tag(SettingsTab.departments)

            FirestoreSettingsTab()
                .tabItem { Label(SettingsTab.firestore.rawValue, systemImage: SettingsTab.firestore.icon) }
                .tag(SettingsTab.firestore)

            AboutTab()
                .tabItem { Label(SettingsTab.about.rawValue, systemImage: SettingsTab.about.icon) }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 500, minHeight: 380)
        .padding(20)
    }
}

// ============================================================
// MARK: - AccountSettingsTab
// ============================================================

struct AccountSettingsTab: View {
    @EnvironmentObject var adminAuth: AdminAuthService
    @State private var showLogoutConfirm = false

    var body: some View {
        Form {
            Section("현재 관리자 계정") {
                if let admin = adminAuth.currentAdmin {
                    LabeledContent("이름", value: admin.name)
                    LabeledContent("이메일", value: admin.email)
                    LabeledContent("역할", value: admin.role.displayName)
                    LabeledContent("상태", value: admin.status.displayName)
                } else {
                    Text("로그인 정보를 불러올 수 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("로그아웃", role: .destructive) {
                    showLogoutConfirm = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("로그아웃 하시겠습니까?", isPresented: $showLogoutConfirm) {
            Button("로그아웃", role: .destructive) {
                adminAuth.signOut()
            }
            Button("취소", role: .cancel) {}
        }
    }
}

// ============================================================
// MARK: - DepartmentsSettingsTab
// 부서 목록 관리 (추가 / 삭제) — Firestore departments 컬렉션
// ============================================================

struct DepartmentsSettingsTab: View {
    @EnvironmentObject var adminAuth: AdminAuthService
    @State private var departments: [DepartmentItem] = []
    @State private var newDeptName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    struct DepartmentItem: Identifiable {
        let id: String    // Firestore document ID
        let name: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 헤더
            HStack {
                Text("부서 목록")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.8)
                }
                Button {
                    Task { await loadDepartments() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

            // 새 부서 추가
            HStack(spacing: 8) {
                TextField("새 부서 이름", text: $newDeptName)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { Task { await addDepartment() } }
                Button("추가") {
                    Task { await addDepartment() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newDeptName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }

            Divider()

            // 부서 목록
            if departments.isEmpty && !isLoading {
                Text("등록된 부서가 없습니다.\n위에서 부서를 추가하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            } else {
                List {
                    ForEach(departments) { dept in
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundStyle(.secondary)
                            Text(dept.name)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await deleteDepartment(dept) }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 120)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(4)
        .task { await loadDepartments() }
    }

    // MARK: - Firestore REST helpers

    private func loadDepartments() async {
        guard let token = adminAuth.idToken, let pid = adminAuth.projectId else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let urlStr = "https://firestore.googleapis.com/v1/projects/\(pid)/databases/(default)/documents/departments"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["documents"] as? [[String: Any]] else {
                departments = []
                return
            }
            departments = docs.compactMap { doc -> DepartmentItem? in
                guard let docName = doc["name"] as? String,
                      let fields = doc["fields"] as? [String: Any],
                      let name = (fields["name"] as? [String: Any])?["stringValue"] as? String else { return nil }
                let docId = docName.components(separatedBy: "/").last ?? ""
                return DepartmentItem(id: docId, name: name)
            }.sorted { $0.name < $1.name }
        } catch {
            errorMessage = "불러오기 실패: \(error.localizedDescription)"
        }
    }

    private func addDepartment() async {
        let trimmed = newDeptName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let token = adminAuth.idToken,
              let pid = adminAuth.projectId else { return }

        // 중복 확인
        if departments.contains(where: { $0.name == trimmed }) {
            errorMessage = "이미 존재하는 부서입니다."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // POST로 자동 ID 생성
        let urlStr = "https://firestore.googleapis.com/v1/projects/\(pid)/databases/(default)/documents/departments"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "fields": ["name": ["stringValue": trimmed]]
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let statusCode = http?.statusCode ?? 0
            if statusCode == 200 {
                newDeptName = ""
                fieldFocused = false
                await loadDepartments()
            } else {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let msg = (json?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(statusCode)"
                errorMessage = "추가 실패: \(msg)"
            }
        } catch {
            errorMessage = "추가 실패: \(error.localizedDescription)"
        }
    }

    private func deleteDepartment(_ dept: DepartmentItem) async {
        guard let token = adminAuth.idToken, let pid = adminAuth.projectId else { return }
        isLoading = true
        defer { isLoading = false }

        let urlStr = "https://firestore.googleapis.com/v1/projects/\(pid)/databases/(default)/documents/departments/\(dept.id)"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, _) = try await URLSession.shared.data(for: req)
            await loadDepartments()
        } catch {
            errorMessage = "삭제 실패: \(error.localizedDescription)"
        }
    }
}

// ============================================================
// MARK: - FirestoreSettingsTab
// ============================================================

struct FirestoreSettingsTab: View {
    @State private var firestoreRules = """
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // users 컬렉션
    match /users/{uid} {
      // 관리자: 모든 문서 읽기/쓰기
      allow read, write: if request.auth != null
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';

      // 신규 가입: 본인 uid로 문서 생성 허용 (status는 pending만 허용)
      allow create: if request.auth != null 
        && request.auth.uid == uid
        && request.resource.data.status == 'pending';

      // 본인 문서는 본인이 읽기 가능
      allow read: if request.auth != null && request.auth.uid == uid;
    }

    // departments 컬렉션
    // - 읽기: 로그인한 모든 사용자 (가입 시 부서 목록 표시용)
    // - 쓰기: 관리자만
    match /departments/{docId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }
  }
}
"""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Firestore 보안 규칙")
                .font(.headline)

            Text("아래 규칙을 Firebase Console → Firestore → Rules에 붙여넣으세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(firestoreRules)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 180)

            HStack {
                Spacer()
                Button("클립보드에 복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(firestoreRules, forType: .string)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(4)
    }
}

// ============================================================
// MARK: - AboutTab
// ============================================================

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text("ZAKAR Admin")
                    .font(.title2.bold())
                Text("은혜의 교회 사용자 관리 시스템")
                    .foregroundStyle(.secondary)
                Text("v1.0.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(width: 200)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "대상", value: "은혜의 교회 관리자")
                InfoRow(label: "플랫폼", value: "macOS 14.0+")
                InfoRow(label: "백엔드", value: "Firebase Auth + Firestore")
            }

            Spacer()
        }
        .padding()
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
