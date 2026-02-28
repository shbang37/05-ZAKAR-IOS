import SwiftUI
import Combine

// ============================================================
// MARK: - AuthService
// Firebase Auth + Firestore 기반 사용자 인증/승인 서비스
//
// 의존성: FirebaseAuth, FirebaseFirestore
// → Xcode > File > Add Package Dependencies >
//   https://github.com/firebase/firebase-ios-sdk
//   (FirebaseAuth + FirebaseFirestore 체크)
//
// GoogleService-Info.plist를 ZAKAR 타겟에 추가 필요
// ============================================================

// Firebase 패키지 추가 전까지 빌드가 가능하도록
// 실제 Firebase 호출은 #if canImport 블록 안에 작성합니다.

@MainActor
final class AuthService: ObservableObject {

    // MARK: - Published State
    @Published var authState: AuthState = .loading
    @Published var currentUser: UserRecord?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    enum AuthState: Equatable {
        case loading            // 앱 시작 시 상태 확인 중
        case unauthenticated    // 로그인 필요
        case pendingApproval    // 로그인됨, 관리자 승인 대기
        case rejected           // 로그인됨, 승인 거절됨
        case approved           // 로그인됨, 승인됨 → 앱 사용 가능
    }

    init() {}

    // MARK: - 세션 확인 (앱 시작 시) — ZAKARApp의 .task {} 에서 호출
    func checkCurrentSession() {
        #if canImport(FirebaseAuth)
        checkCurrentSessionFirebase()
        #else
        // Firebase 미설치 시 → 로그인 화면으로
        authState = .unauthenticated
        #endif
    }

    // MARK: - 회원가입
    func signUp(email: String, password: String, name: String, department: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        #if canImport(FirebaseAuth)
        await signUpFirebase(email: email, password: password, name: name, department: department)
        #else
        errorMessage = "Firebase 패키지를 먼저 추가해주세요."
        #endif
    }

    // MARK: - 부서 목록 조회 (Firestore REST — 로그인 전 접근 가능하도록 공개 규칙 필요)
    func fetchDepartments() async -> [String] {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let pid = dict["PROJECT_ID"] as? String,
              let apiKey = dict["API_KEY"] as? String else { return [] }

        let urlStr = "https://firestore.googleapis.com/v1/projects/\(pid)/databases/(default)/documents/departments?key=\(apiKey)"
        guard let reqURL = URL(string: urlStr) else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: reqURL)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["documents"] as? [[String: Any]] else { return [] }
            return docs.compactMap { doc -> String? in
                guard let fields = doc["fields"] as? [String: Any] else { return nil }
                return (fields["name"] as? [String: Any])?["stringValue"] as? String
            }.sorted()
        } catch {
            return []
        }
    }

    // MARK: - 로그인
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        #if canImport(FirebaseAuth)
        await signInFirebase(email: email, password: password)
        #else
        errorMessage = "Firebase 패키지를 먼저 추가해주세요."
        #endif
    }

    // MARK: - 로그아웃
    func signOut() {
        #if canImport(FirebaseAuth)
        signOutFirebase()
        #else
        currentUser = nil
        authState = .unauthenticated
        #endif
    }

    // MARK: - 실시간 승인 상태 리스닝 (Firebase 없을 때 no-op)
    func listenForApprovalChange(uid: String) {
        #if canImport(FirebaseAuth)
        listenForApprovalChangeFirebase(uid: uid)
        #endif
    }
}

// MARK: - Firebase 구현 (패키지 추가 후 활성화)
#if canImport(FirebaseAuth)
import FirebaseAuth
import FirebaseFirestore

// nonisolated storage for the Firebase Auth listener handle
private var _authListenerHandle: AuthStateDidChangeListenerHandle?

extension AuthService {

    private var db: Firestore { Firestore.firestore() }

    func checkCurrentSessionFirebase() {
        _authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                guard let self else { return }
                guard let firebaseUser else {
                    self.authState = .unauthenticated
                    self.currentUser = nil
                    return
                }
                await self.fetchAndApplyUserRecord(uid: firebaseUser.uid)
            }
        }
    }

    func signUpFirebase(email: String, password: String, name: String, department: String) async {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let uid = result.user.uid

            // Firestore에 사용자 문서 생성 (status: pending)
            let record = UserRecord(
                id: uid,
                email: email,
                name: name,
                department: department,
                role: .member,
                status: .pending,
                requestedAt: Date(),
                approvedAt: nil
            )
            try await db.collection("users").document(uid).setData(record.firestoreData)
            currentUser = record
            authState = .pendingApproval

        } catch {
            let nsError = error as NSError
            print("🔴 SignUp Error: domain=\(nsError.domain) code=\(nsError.code)")
            print("🔴 userInfo=\(nsError.userInfo)")
            // Firebase 내부 오류의 실제 원인 추출
            if let detail = nsError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any] {
                print("🔴 Firebase detail: \(detail)")
                errorMessage = detail["message"] as? String ?? authErrorMessage(error)
            } else if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("🔴 Underlying: \(underlying.domain) \(underlying.code) \(underlying.userInfo)")
                errorMessage = underlying.localizedDescription
            } else {
                errorMessage = "[\(nsError.code)] \(nsError.localizedDescription)"
            }
        }
    }

    func signInFirebase(email: String, password: String) async {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await fetchAndApplyUserRecord(uid: result.user.uid)
        } catch {
            errorMessage = authErrorMessage(error)
        }
    }

    func signOutFirebase() {
        try? Auth.auth().signOut()
        currentUser = nil
        authState = .unauthenticated
    }

    /// Firestore에서 사용자 문서를 읽어 authState에 반영
    func fetchAndApplyUserRecord(uid: String) async {
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data(), let record = UserRecord(firestoreData: data, id: uid) else {
                authState = .unauthenticated
                return
            }
            currentUser = record
            switch record.status {
            case .pending:  authState = .pendingApproval
            case .approved: authState = .approved
            case .rejected: authState = .rejected
            }
        } catch {
            authState = .unauthenticated
        }
    }

    // MARK: - Firestore 실시간 승인 상태 리스닝
    /// 승인 대기 화면에서 호출 → 관리자가 승인하면 즉시 메인 화면으로 전환
    func listenForApprovalChangeFirebase(uid: String) {
        db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self, let data = snapshot?.data(),
                      let record = UserRecord(firestoreData: data, id: uid) else { return }
                self.currentUser = record
                switch record.status {
                case .pending:  self.authState = .pendingApproval
                case .approved: self.authState = .approved
                case .rejected: self.authState = .rejected
                }
            }
        }
    }

    private func authErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        // 디버그용 상세 로그 출력
        print("🔴 AuthError domain=\(nsError.domain) code=\(nsError.code)")
        print("🔴 userInfo=\(nsError.userInfo)")
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("🔴 underlying=\(underlying.domain) code=\(underlying.code) \(underlying.userInfo)")
        }

        switch nsError.code {
        case 17007: return "이미 사용 중인 이메일입니다."
        case 17008: return "올바른 이메일 형식이 아닙니다."
        case 17026: return "비밀번호는 6자 이상이어야 합니다."
        case 17009: return "비밀번호가 올바르지 않습니다."
        case 17011: return "등록되지 않은 이메일입니다."
        default:
            // Firebase 내부 오류 시 userInfo의 상세 메시지 표시
            if let detail = nsError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
               let message = detail["message"] as? String {
                return message
            }
            return nsError.localizedDescription
        }
    }
}

// MARK: - UserRecord ↔ Firestore 변환
extension UserRecord {
    var firestoreData: [String: Any] {
        var d: [String: Any] = [
            "email": email,
            "name": name,
            "department": department,
            "role": role.rawValue,
            "status": status.rawValue,
            "requestedAt": Timestamp(date: requestedAt)
        ]
        if let approvedAt { d["approvedAt"] = Timestamp(date: approvedAt) }
        return d
    }

    init?(firestoreData data: [String: Any], id: String) {
        guard
            let email = data["email"] as? String,
            let name = data["name"] as? String,
            let roleRaw = data["role"] as? String,
            let statusRaw = data["status"] as? String,
            let role = UserRole(rawValue: roleRaw),
            let status = UserStatus(rawValue: statusRaw),
            let requestedTS = data["requestedAt"] as? Timestamp
        else { return nil }

        self.id = id
        self.email = email
        self.name = name
        self.department = data["department"] as? String ?? ""
        self.role = role
        self.status = status
        self.requestedAt = requestedTS.dateValue()
        if let approvedTS = data["approvedAt"] as? Timestamp {
            self.approvedAt = approvedTS.dateValue()
        }
    }
}
#endif
