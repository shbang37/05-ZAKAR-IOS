import Foundation

// MARK: - 사용자 인증/승인 모델
/// Firestore의 users/{uid} 문서와 1:1 대응합니다.
struct UserRecord: Codable, Identifiable, Hashable {
    var id: String          // Firebase Auth UID
    var email: String
    var name: String
    var department: String  // 소속 부서 (Firestore의 departments 컬렉션 기준)
    var role: UserRole
    var status: UserStatus
    var requestedAt: Date
    var approvedAt: Date?

    enum UserRole: String, Codable, CaseIterable {
        case member   = "member"    // 일반 동역자
        case reporter = "reporter"  // 기자부
        case admin    = "admin"     // 관리자

        var displayName: String {
            switch self {
            case .member:   return "동역자"
            case .reporter: return "기자부"
            case .admin:    return "관리자"
            }
        }
    }

    enum UserStatus: String, Codable {
        case pending  = "pending"   // 승인 대기
        case approved = "approved"  // 승인됨
        case rejected = "rejected"  // 거절됨

        var displayName: String {
            switch self {
            case .pending:  return "승인 대기"
            case .approved: return "승인됨"
            case .rejected: return "거절됨"
            }
        }
    }
}

// MARK: - Models
struct AssetRecord: Codable, Identifiable, Hashable {
    var id: String // PHAsset.localIdentifier or custom for documents
    var type: String // photo | video | document
    var favorite: Bool
    var createdAt: Date
    var hash64: UInt64?
    var remoteStatus: String? // synced | pending | conflict
}

struct GroupRecord: Codable, Identifiable, Hashable {
    var id: String // group id
    var assetIds: [String]
    var createdAt: Date
    var preset: String // similarity preset label
}

struct SessionRecord: Codable, Identifiable, Hashable {
    var id: String // UUID
    var startedAt: Date
    var processedCount: Int
    var deletedCount: Int
    var savedCount: Int
}

struct ArchiveRecord: Codable, Hashable {
    var provider: String // GoogleDrive, NAS, etc.
    var remotePath: String
    var lastSyncAt: Date?
    var integrityHash: String?
}

struct AppMetadata: Codable {
    var lastCleanupDate: Date?
    var estimatedSavedMB: Double?
    var archive: ArchiveRecord?
    var onboardingCompleted: Bool?
}

// MARK: - Repository
final class LocalDB {
    static let shared = LocalDB()
    private init() {}

    private let fm = FileManager.default

    private var baseURL: URL {
        let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = url.appendingPathComponent("ZAKAR", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var metadataURL: URL { baseURL.appendingPathComponent("metadata.json") }
    private var trashURL: URL { baseURL.appendingPathComponent("trash.json") }

    func loadMetadata() -> AppMetadata {
        guard let data = try? Data(contentsOf: metadataURL) else { return AppMetadata(lastCleanupDate: nil, estimatedSavedMB: nil, archive: nil) }
        return (try? JSONDecoder().decode(AppMetadata.self, from: data)) ?? AppMetadata(lastCleanupDate: nil, estimatedSavedMB: nil, archive: nil)
    }

    func saveMetadata(_ meta: AppMetadata) {
        do {
            let data = try JSONEncoder().encode(meta)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("LocalDB saveMetadata error: \(error)")
        }
    }

    func isOnboardingCompleted() -> Bool {
        return loadMetadata().onboardingCompleted ?? false
    }

    func setOnboardingCompleted(_ completed: Bool) {
        var meta = loadMetadata()
        meta.onboardingCompleted = completed
        saveMetadata(meta)
    }

    func loadTrashIdentifiers() -> [String] {
        guard let data = try? Data(contentsOf: trashURL) else { return [] }
        if let ids = try? JSONDecoder().decode([String].self, from: data) { return ids }
        // 해석할 수 없는 파일을 그대로 두면 다음 저장 때 빈 목록으로 덮어써져 휴지통 목록을 잃는다.
        // 원본을 옆에 보관해 두고 빈 목록으로 시작한다.
        let backup = baseURL.appendingPathComponent("trash.unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? fm.moveItem(at: trashURL, to: backup)
        print("LocalDB ⚠️ trash.json을 읽을 수 없어 \(backup.lastPathComponent)로 보관함")
        return []
    }

    /// 저장 성공 여부를 돌려준다 (디스크 부족 등으로 실패하면 호출 쪽이 알 수 있게)
    @discardableResult
    func saveTrashIdentifiers(_ ids: [String]) -> Bool {
        do {
            let data = try JSONEncoder().encode(ids)
            try data.write(to: trashURL, options: .atomic)
            return true
        } catch {
            print("LocalDB saveTrashIdentifiers error: \(error)")
            return false
        }
    }

    /// 모든 로컬 데이터 삭제 (계정 삭제 시 사용)
    static func clearAll() {
        let db = LocalDB.shared
        do {
            // metadata.json 삭제
            if db.fm.fileExists(atPath: db.metadataURL.path) {
                try db.fm.removeItem(at: db.metadataURL)
            }
            // trash.json 삭제
            if db.fm.fileExists(atPath: db.trashURL.path) {
                try db.fm.removeItem(at: db.trashURL)
            }
            print("✅ LocalDB cleared successfully")
        } catch {
            print("❌ LocalDB clearAll error: \(error)")
        }
    }
}
