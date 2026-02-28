import SwiftUI
import Combine

// ============================================================
// MARK: - AdminAuthService
// macOS Admin 앱 전용 인증 서비스
//
// macOS에서 Firebase Auth SDK는 키체인 접근 오류를 일으키므로
// Firebase Identity Toolkit REST API로 직접 인증합니다.
// 로그인 후 Firestore REST API로 사용자 문서를 조회합니다.
// ============================================================

@MainActor
final class AdminAuthService: ObservableObject {

    @Published var adminState: AdminState = .unauthenticated
    @Published var currentAdmin: UserRecord?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // 로그인 후 받은 idToken — Firestore REST 호출에 사용 (AdminUserListVM 등에서 접근)
    var idToken: String?
    private var localUid: String?

    // GoogleService-Info.plist의 PROJECT_ID (외부 접근용)
    var projectId: String? { plistValue(key: "PROJECT_ID") }

    enum AdminState: Equatable {
        case unauthenticated
        case notAdmin
        case authenticated
    }

    init() {}

    // MARK: - 로그인 (Firebase Identity Toolkit REST API)
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // GoogleService-Info.plist에서 API Key 읽기
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String
                ?? plistValue(key: "API_KEY") else {
            errorMessage = "GoogleService-Info.plist에서 API_KEY를 찾을 수 없습니다."
            return
        }

        // Firebase Auth REST API로 로그인
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": true
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "서버 응답 오류"
                return
            }

            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            if http.statusCode != 200 {
                // 오류 메시지 파싱
                let errMsg = (json?["error"] as? [String: Any])?["message"] as? String ?? "로그인 실패"
                switch errMsg {
                case "EMAIL_NOT_FOUND":   errorMessage = "등록되지 않은 이메일입니다."
                case "INVALID_PASSWORD":  errorMessage = "비밀번호가 올바르지 않습니다."
                case "USER_DISABLED":     errorMessage = "비활성화된 계정입니다."
                default:                  errorMessage = errMsg
                }
                return
            }

            guard let token = json?["idToken"] as? String,
                  let uid   = json?["localId"] as? String else {
                errorMessage = "인증 토큰을 받지 못했습니다."
                return
            }

            idToken   = token
            localUid  = uid
            await fetchAdminRecord(uid: uid, idToken: token)

        } catch {
            errorMessage = "네트워크 오류: \(error.localizedDescription)"
        }
    }

    // MARK: - 로그아웃
    func signOut() {
        idToken      = nil
        localUid     = nil
        currentAdmin = nil
        adminState   = .unauthenticated
    }

    // MARK: - Firestore REST API로 사용자 문서 조회
    private func fetchAdminRecord(uid: String, idToken: String) async {
        guard let projectId = plistValue(key: "PROJECT_ID") else {
            errorMessage = "GoogleService-Info.plist에서 PROJECT_ID를 찾을 수 없습니다."
            return
        }

        let urlStr = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/users/\(uid)"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let fields = json?["fields"] as? [String: Any]

            guard
                let name      = (fields?["name"]   as? [String: Any])?["stringValue"]   as? String,
                let email     = (fields?["email"]  as? [String: Any])?["stringValue"]   as? String,
                let roleRaw   = (fields?["role"]   as? [String: Any])?["stringValue"]   as? String,
                let statusRaw = (fields?["status"] as? [String: Any])?["stringValue"]   as? String,
                let role      = UserRecord.UserRole(rawValue: roleRaw),
                let status    = UserRecord.UserStatus(rawValue: statusRaw)
            else {
                errorMessage = "사용자 정보를 불러올 수 없습니다."
                adminState = .unauthenticated
                return
            }

            let department = (fields?["department"] as? [String: Any])?["stringValue"] as? String ?? ""
            let record = UserRecord(
                id: uid, email: email, name: name,
                department: department,
                role: role, status: status,
                requestedAt: Date(), approvedAt: nil
            )

            if role == .admin {
                currentAdmin = record
                adminState   = .authenticated
            } else {
                adminState   = .notAdmin
                errorMessage = "관리자 계정이 아닙니다. (\(role.displayName) 권한)"
            }
        } catch {
            errorMessage = "사용자 정보 조회 실패: \(error.localizedDescription)"
            adminState = .unauthenticated
        }
    }

    // MARK: - GoogleService-Info.plist 값 읽기
    private func plistValue(key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        return dict[key] as? String
    }
}
