import Foundation
import Combine
import UIKit
import Photos
import AVFoundation

// ============================================================
// MARK: - AWSService
// ZAKAR 교회 아카이브 AWS 백엔드 연동 서비스
//
// 아키텍처:
//   Firebase JWT → POST /auth → STS 임시 자격증명
//   GET /files → DynamoDB 파일 목록 조회
//   POST /files/upload-url → S3 Presigned PUT URL 발급
//   S3 Presigned URL → 직접 PUT (S3 업로드)
//   GET /files/view-url → Presigned GET URL (inline)
//   GET /files/download-url → Presigned GET URL (attachment)
//
// API Base: https://1kb1ritkqb.execute-api.ap-northeast-2.amazonaws.com/prod
// ============================================================

// MARK: - 모델

struct AWSCredentials: Codable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String
    let expiration: String
    let department: String
    let role: String
    let canDownload: Bool
    let canUpload: Bool

    var isExpired: Bool {
        // ISO 8601 형식 파싱
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiration) {
            return date < Date()
        }
        // fractional seconds 없는 경우
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiration).map { $0 < Date() } ?? true
    }
}

struct AWSArchiveFile: Identifiable, Codable {
    let fileId: String
    let department: String
    let s3Key: String
    let originalName: String
    let eventName: String
    let fileType: String    // "photo" | "video" | "document"
    let fileSize: Int
    let uploadedAt: String
    let status: String

    var id: String { fileId }

    var displaySize: String {
        let kb = fileSize / 1024
        if kb >= 1000 { return String(format: "%.1f MB", Double(kb) / 1000) }
        return "\(max(kb, 1)) KB"
    }

    var fileIcon: String {
        switch fileType {
        case "photo":    return "photo.fill"
        case "video":    return "video.fill"
        case "document": return "doc.fill"
        default:         return "doc.fill"
        }
    }

    var uploadedDate: String {
        let raw = uploadedAt
        return String(raw.prefix(10))   // "2026-05-16"
    }
}

struct AWSUploadItem: Identifiable {
    let id = UUID()
    var filename: String
    var size: String
    var progress: Double        // 0.0 ~ 1.0
    var status: UploadStatus
    var fileId: String?

    enum UploadStatus {
        case waiting, uploading, done, failed
    }
}

// MARK: - AWSService

@MainActor
final class AWSService: ObservableObject, ZKDriveSyncing {

    // MARK: - 상수
    static let apiBase = "https://tf6w4ysbk1.execute-api.ap-northeast-2.amazonaws.com/prod"

    // MARK: - 부서 매핑

    /// 하드코딩 fallback: 부서 한글명 → S3 폴더 키
    /// Firestore departments/{doc}.key 필드가 없는 기존 계정을 위해 유지
    static let departmentKeyMap: [String: String] = [
        "송도청": "songdo",
        "미들청": "middle",
        "이음청": "eum",
        "또래청": "ddrae",
        "기자부": "gijab",
        "사역자": "minister",
        "관리자": "admin",
        // 영문 키 passthrough (이미 키인 경우)
        "songdo":   "songdo",
        "middle":   "middle",
        "eum":      "eum",
        "ddrae":    "ddrae",
        "gijab":    "gijab",
        "minister": "minister",
        "admin":    "admin",
        "shared":   "shared"
    ]

    /// 하드코딩 fallback: S3 키 → 한글 표시명
    static let departmentDisplayMap: [String: String] = [
        "songdo":   "송도청",
        "middle":   "미들청",
        "eum":      "이음청",
        "ddrae":    "또래청",
        "gijab":    "기자부",
        "minister": "사역자",
        "admin":    "관리자",
        "shared":   "공용"
    ]

    /// Firestore departments 컬렉션에서 동적으로 로드된 매핑
    /// AuthService.fetchDepartments() 호출 시 자동 업데이트됨
    /// ZAKARAdmin에서 부서 추가/수정/삭제 시 앱 재시작 없이 다음 fetchDepartments() 호출에서 반영
    static var dynamicKeyMap:     [String: String] = [:]   // 한글명 → S3 키
    static var dynamicDisplayMap: [String: String] = [:]   // S3 키 → 한글명

    /// 부서명(한글) → S3 키. Firestore 동적 맵 우선, 없으면 하드코딩 fallback.
    static func s3Key(for department: String) -> String {
        if let key = dynamicKeyMap[department], !key.isEmpty { return key }
        return departmentKeyMap[department] ?? department
    }

    /// S3 키 → 한글 표시명. Firestore 동적 맵 우선, 없으면 하드코딩 fallback.
    static func displayName(for deptKey: String) -> String {
        if let name = dynamicDisplayMap[deptKey], !name.isEmpty { return name }
        return departmentDisplayMap[deptKey] ?? deptKey
    }

    // MARK: - Published 상태
    @Published var isAuthenticated: Bool = false
    @Published var credentials: AWSCredentials?
    @Published var uploadQueue: [AWSUploadItem] = []
    @Published var isUploading: Bool = false
    @Published var files: [AWSArchiveFile] = []
    @Published var isLoadingFiles: Bool = false
    @Published var errorMessage: String?
    @Published var lastSyncAt: Date?

    // MARK: - Firebase → AWS 인증
    /// Firebase ID 토큰을 Lambda에 전달하여 STS 임시 자격증명을 교환합니다.
    func authenticate(firebaseToken: String, department: String, role: String) async {
        errorMessage = nil
        let deptKey = AWSService.s3Key(for: department)

        guard let url = URL(string: "\(AWSService.apiBase)/auth") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "firebaseToken": firebaseToken,
            "department":    deptKey,
            "role":          role
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode != 200 {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                errorMessage = "AWS 인증 실패 (\(httpRes.statusCode)): \(msg ?? "")"
                return
            }
            credentials = try JSONDecoder().decode(AWSCredentials.self, from: data)
            isAuthenticated = true
        } catch {
            errorMessage = "AWS 인증 오류: \(error.localizedDescription)"
        }
    }

    // MARK: - 파일 목록 조회
    func fetchFiles(department: String, year: String = "") async {
        isLoadingFiles = true
        defer { isLoadingFiles = false }

        let deptKey  = AWSService.s3Key(for: department)
        let yearStr  = year.isEmpty ? String(Calendar.current.component(.year, from: Date())) : year
        let urlStr   = "\(AWSService.apiBase)/files?department=\(deptKey)&year=\(yearStr)"

        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["files"] as? [[String: Any]] else { return }

            files = items.compactMap { dict -> AWSArchiveFile? in
                guard let fileId = dict["fileId"] as? String,
                      let dept   = dict["department"] as? String,
                      let s3Key  = dict["s3Key"] as? String else { return nil }
                return AWSArchiveFile(
                    fileId:       fileId,
                    department:   dept,
                    s3Key:        s3Key,
                    originalName: dict["originalName"] as? String ?? "unknown",
                    eventName:    dict["eventName"] as? String ?? "",
                    fileType:     dict["fileType"] as? String ?? "photo",
                    fileSize:     dict["fileSize"] as? Int ?? 0,
                    uploadedAt:   dict["uploadedAt"] as? String ?? "",
                    status:       dict["status"] as? String ?? "uploaded"
                )
            }
            lastSyncAt = Date()
        } catch {
            errorMessage = "파일 목록 오류: \(error.localizedDescription)"
        }
    }

    // MARK: - 업로드 Presigned URL 요청
    func requestUploadURL(
        department:  String,
        year:        String,
        eventName:   String,
        filename:    String,
        contentType: String,
        fileSize:    Int,
        userId:      String,
        fileType:    String = "photo"
    ) async throws -> (uploadUrl: String, fileId: String) {
        let deptKey = AWSService.s3Key(for: department)
        guard let url = URL(string: "\(AWSService.apiBase)/files/upload-url") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "department":   deptKey,
            "year":         year,
            "eventName":    eventName,
            "filename":     filename,
            "contentType":  contentType,
            "fileSize":     fileSize,
            "userId":       userId,
            "fileType":     fileType
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadUrl = json["uploadUrl"] as? String,
              let fileId    = json["fileId"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return (uploadUrl, fileId)
    }

    // MARK: - S3 Presigned URL로 직접 업로드 (PUT)
    // S3 글로벌 엔드포인트는 307 Temporary Redirect를 반환할 수 있음.
    // iOS URLSession 기본 동작은 PUT 리다이렉트 시 바디를 재전송하지 않으므로
    // 직접 307을 감지해 리다이렉트된 URL로 다시 PUT을 날립니다.
    func uploadToS3(presignedURL: String, data: Data, contentType: String) async throws {
        var targetURL = presignedURL

        // 최대 2번 리다이렉트 허용 (307 → 실제 리전 엔드포인트)
        for attempt in 0..<3 {
            guard let url = URL(string: targetURL) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            request.timeoutInterval = 120

            // 자동 리다이렉트 비활성화 → 307을 직접 처리
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config,
                                     delegate: S3NoRedirectDelegate(),
                                     delegateQueue: nil)

            let (responseData, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            if status == 307 || status == 301 {
                // Location 헤더에서 리다이렉트 URL 추출
                if let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
                   !location.isEmpty {
                    print("  🔀 [S3] \(status) redirect → \(location.prefix(80))...")
                    targetURL = location
                    continue
                }
            }

            guard (200...299).contains(status) else {
                let body = String(data: responseData, encoding: .utf8) ?? "(empty)"
                print("❌ [S3 PUT] attempt:\(attempt) status:\(status) body:\(body.prefix(500))")
                throw URLError(.badServerResponse)
            }
            return  // 성공
        }
        throw URLError(.badServerResponse)
    }

    // MARK: - 조회용 URL (inline 뷰어, 15분 유효)
    func getViewURL(fileId: String, userId: String = "unknown") async throws -> String {
        let urlStr = "\(AWSService.apiBase)/files/view-url?fileId=\(fileId)&userId=\(userId)&platform=iOS"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let viewUrl = json["viewUrl"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return viewUrl
    }

    // MARK: - 다운로드 URL (attachment, 리더/관리자 전용)
    func getDownloadURL(fileId: String, userId: String) async throws -> String {
        guard credentials?.canDownload == true else {
            throw NSError(
                domain: "AWSService", code: 403,
                userInfo: [NSLocalizedDescriptionKey: "다운로드 권한이 없습니다.\n리더 또는 관리자만 다운로드 가능합니다."]
            )
        }
        let urlStr = "\(AWSService.apiBase)/files/download-url?fileId=\(fileId)&userId=\(userId)&platform=iOS&canDownload=true"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let downloadUrl = json["downloadUrl"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return downloadUrl
    }

    // MARK: - PHAsset 배열 → AWS 업로드 (큐 방식)
    func enqueueAndUpload(
        assets:     [PHAsset],
        department: String,
        eventName:  String,
        userId:     String
    ) async {
        // isAuthenticated만 확인 (canUpload 서버 체크는 Lambda가 아닌 presigned URL 발급 자체로 검증)
        guard isAuthenticated, !isUploading else {
            print("⚠️ [AWSService] 업로드 건너뜀 — isAuthenticated:\(isAuthenticated), isUploading:\(isUploading)")
            return
        }

        let year = String(Calendar.current.component(.year, from: Date()))
        let df   = DateFormatter(); df.dateFormat = "yyyyMMdd_HHmmss"

        // 큐 항목 생성
        let newItems: [AWSUploadItem] = assets.enumerated().map { i, asset in
            let stamp   = df.string(from: asset.creationDate ?? Date())
            let ext     = asset.mediaType == .video ? "mp4" : "jpg"
            let rawKB   = max(asset.pixelWidth * asset.pixelHeight * 3 / 1024, 100)
            let sizeStr = rawKB >= 1000
                ? String(format: "%.1f MB", Double(rawKB) / 1000)
                : "\(rawKB) KB"
            return AWSUploadItem(
                filename: "ZAKAR_\(stamp)_\(String(format: "%03d", i + 1)).\(ext)",
                size: sizeStr,
                progress: 0,
                status: .waiting
            )
        }
        uploadQueue.append(contentsOf: newItems)

        isUploading = true
        defer { isUploading = false; lastSyncAt = Date() }

        let startIdx = uploadQueue.count - newItems.count

        for (offset, asset) in assets.enumerated() {
            let qi = startIdx + offset
            guard qi < uploadQueue.count else { continue }

            let isVideo     = asset.mediaType == .video
            let contentType = isVideo ? "video/mp4" : "image/jpeg"
            let fileType    = isVideo ? "video" : "photo"
            let filename    = uploadQueue[qi].filename

            uploadQueue[qi].status = .uploading
            print("📤 [AWSService] 업로드 시작 [\(filename)] dept=\(department) event=\(eventName)")

            do {
                // 1단계: PHAsset → Data
                print("  1️⃣ extractAssetData 시작")
                let data = try await extractAssetData(asset: asset, isVideo: isVideo)
                print("  1️⃣ extractAssetData 완료 — \(data.count) bytes")
                uploadQueue[qi].progress = 0.2

                // 2단계: Presigned URL 요청
                print("  2️⃣ requestUploadURL 시작")
                let (presignedURL, fileId) = try await requestUploadURL(
                    department:  department,
                    year:        year,
                    eventName:   eventName,
                    filename:    filename,
                    contentType: contentType,
                    fileSize:    data.count,
                    userId:      userId,
                    fileType:    fileType
                )
                print("  2️⃣ requestUploadURL 완료 — fileId:\(fileId)")
                uploadQueue[qi].progress = 0.4

                // 3단계: S3 직접 업로드
                print("  3️⃣ uploadToS3 시작")
                try await uploadToS3(presignedURL: presignedURL, data: data, contentType: contentType)
                print("  3️⃣ uploadToS3 완료 ✅")
                uploadQueue[qi].progress = 1.0
                uploadQueue[qi].status   = .done

            } catch {
                uploadQueue[qi].status = .failed
                print("❌ [AWSService] 업로드 실패 [\(filename)] 단계:\(uploadQueue[qi].progress) 오류:\(error)")
            }
        }

        // 파일 목록 갱신
        await fetchFiles(department: department, year: year)
    }

    func clearCompleted() {
        uploadQueue.removeAll { $0.status == .done }
    }

    // MARK: - PHAsset Data 추출 (async)
    private func extractAssetData(asset: PHAsset, isVideo: Bool) async throws -> Data {
        if isVideo {
            // 영상: URL을 통해 Data로 변환
            return try await withCheckedThrowingContinuation { cont in
                let opts = PHVideoRequestOptions()
                opts.deliveryMode = .fastFormat
                opts.isNetworkAccessAllowed = true
                PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                    if let urlAsset = avAsset as? AVURLAsset,
                       let data = try? Data(contentsOf: urlAsset.url) {
                        cont.resume(returning: data)
                    } else {
                        cont.resume(returning: Data())  // 빈 데이터로 안전 처리
                    }
                }
            }
        } else {
            // 사진: UIImage로 받아 JPEG(85%) 변환 → 범용 호환성 확보
            return try await withCheckedThrowingContinuation { cont in
                let opts = PHImageRequestOptions()
                opts.deliveryMode = .highQualityFormat
                opts.isSynchronous = false
                opts.isNetworkAccessAllowed = true
                var didResume = false   // requestImage는 저화질→고화질 순으로 두 번 호출될 수 있음
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: PHImageManagerMaximumSize,
                    contentMode: .aspectFit,
                    options: opts
                ) { image, info in
                    // isDegraded=true 이면 저화질 프리뷰 → 무시하고 고화질 대기
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !isDegraded, !didResume else { return }
                    didResume = true
                    if let image = image,
                       let jpegData = image.jpegData(compressionQuality: 0.85) {
                        cont.resume(returning: jpegData)
                    } else {
                        cont.resume(throwing: URLError(.cannotLoadFromNetwork))
                    }
                }
            }
        }
    }

    // MARK: - ZKDriveSyncing 구현
    /// LocalURL → S3 업로드
    func upload(localURL: URL, to remotePath: String) async throws {
        let data        = try Data(contentsOf: localURL)
        let parts       = remotePath.split(separator: "/").map(String.init)
        let department  = parts.first ?? "shared"
        let filename    = localURL.lastPathComponent
        let contentType = mimeType(for: filename)
        let year        = String(Calendar.current.component(.year, from: Date()))

        let (presignedURL, _) = try await requestUploadURL(
            department:  department,
            year:        year,
            eventName:   "sync",
            filename:    filename,
            contentType: contentType,
            fileSize:    data.count,
            userId:      "sync-service"
        )
        try await uploadToS3(presignedURL: presignedURL, data: data, contentType: contentType)
    }

    /// S3 fileId → 로컬 파일로 다운로드
    func download(from remotePath: String, to destinationURL: URL) async throws {
        let fileId  = String(remotePath.split(separator: "/").last ?? Substring(remotePath))
        let viewURL = try await getViewURL(fileId: fileId)
        guard let url = URL(string: viewURL) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        try data.write(to: destinationURL, options: .atomic)
    }

    /// 부서 폴더 동기화 (파일 목록 새로고침)
    func synchronize(localFolder: URL, with remoteFolder: String) async throws {
        await fetchFiles(department: remoteFolder)
    }

    // MARK: - 유틸
    private func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "heic":        return "image/jpeg"   // HEIC 원본도 JPEG으로 변환 후 업로드
        case "mp4":         return "video/mp4"
        case "mov":         return "video/quicktime"
        case "pdf":         return "application/pdf"
        default:            return "application/octet-stream"
        }
    }
}

// MARK: - S3 PUT 리다이렉트 핸들러
// URLSession 기본 동작은 PUT 리다이렉트 시 바디를 재전송하지 않음.
// S3 글로벌 엔드포인트의 307 응답을 차단해 uploadToS3 내에서 직접 재시도합니다.
private final class S3NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // nil 전달 → 리다이렉트 중단, 현재 응답(307)을 그대로 반환
        completionHandler(nil)
    }
}

