// 이 파일은 Google Drive와 연결해서 파일을 업로드/동기화하는 기능을 담고 있어요.
// 중학생도 이해할 수 있도록 쉬운 말로 설명 주석을 달았습니다.
// 코드는 바꾸지 않고, 이해를 돕는 설명만 추가했어요.

import Foundation
import AuthenticationServices
import CommonCrypto
import UIKit
import SwiftUI
import Combine
import Photos

// MARK: - Google Drive 업로드 항목
struct DriveUploadItem: Identifiable {
    let id = UUID()
    let filename: String
    var size: String          // 표시용 문자열 (e.g. "3.2 MB")
    var progress: Double      // 0.0 ~ 1.0
    var status: UploadStatus

    enum UploadStatus {
        case waiting, uploading, done, failed
    }
}

// 앱이 '드라이브와 동기화'할 때 필요한 공통 기능 목록이에요.
// 이 프로토콜을 따르면, 드라이브에 연결/해제하고, 업로드/다운로드/동기화 같은 기능을 갖추게 돼요.
// 실제 동작(어떻게 할지)은 이 프로토콜을 따르는 클래스가 구현해요.
// MARK: - DriveSyncing Protocol
protocol DriveSyncing: ObservableObject {
    var isLinked: Bool { get }
    var lastSyncAt: Date? { get }
    
    func upload(localURL: URL, to remotePath: String) async throws
    func download(from remotePath: String, to destinationURL: URL) async throws
    func synchronize(localFolder: URL, with remoteFolder: String) async throws
    
    func link() async
    func unlink()
}

// 실제로 Google Drive와 통신하는 서비스 클래스예요.
// OAuth2(로그인), 폴더 만들기, 파일 업로드 같은 일을 해요.
// SwiftUI에서 관찰 가능한 객체라서, 상태가 바뀌면 화면도 자동으로 업데이트돼요.
// MARK: - Service
final class GoogleDriveService: ZKDriveSyncing, ObservableObject {
    // SwiftUI가 관찰하는 상태 값이에요. 드라이브와 연결됐는지 표시해요.
    @Published var isLinked: Bool = false
    // 마지막으로 동기화한 시간이 언제인지 저장해요.
    @Published var lastSyncAt: Date?
    // 연결 진행 중 여부 (로딩 UI용)
    @Published var isLinking: Bool = false
    // 연결 에러 메시지 (Alert 표시용)
    @Published var linkError: String?
    // 연결된 구글 계정 이메일 (표시용)
    @Published var linkedEmail: String?
    
    // 업로드 진행 상황 추적
    @Published var uploadQueue: [DriveUploadItem] = []
    @Published var isUploading: Bool = false
    
    // 웹 인증 창(사파리 같은)을 유지하기 위해 강하게 잡아두는 변수예요. 세션이 살아있어야 인증이 끝나요.
    private var authSession: ASWebAuthenticationSession?
    // ASWebAuthenticationSession의 presentationContextProvider는 약한 참조이므로 강하게 보관해야 해요.
    private let anchorProvider = PresentationAnchorProvider()
    
    // 사용자 UID (키체인 키 분리용)
    private var userID: String

    // MARK: - OAuth2 (PKCE)
    // PKCE 방식의 OAuth2 로그인을 사용해요.
    // 아래 값들은 구글 콘솔에서 발급받은 값으로 바꿔야 해요. (예시는 그대로 쓰면 안 돼요)
    // scope는 구글 드라이브에 파일을 업로드/관리할 권한이에요.
    // iOS OAuth 클라이언트 ID (Google Cloud Console에서 생성)
    private let clientID = "703077622763-3frm65hm38rhsopb8tnro37scdth3kej.apps.googleusercontent.com"
    // Redirect Scheme = Bundle ID (iOS OAuth는 Bundle ID 기반)
    private let redirectScheme = "com.zakar.app"
    private let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let scope = "https://www.googleapis.com/auth/drive.file"

    // 액세스 토큰, 리프레시 토큰, 만료 시간을 키체인에 안전하게 저장/읽기 해요.
    // 사용자별로 분리하기 위해 userID를 키에 포함합니다.
    private var accessToken: String? {
        get { KeychainHelper.shared.get("drive_access_token_\(userID)") }
        set { KeychainHelper.shared.set(newValue, forKey: "drive_access_token_\(userID)") }
    }
    private var refreshToken: String? {
        get { KeychainHelper.shared.get("drive_refresh_token_\(userID)") }
        set { KeychainHelper.shared.set(newValue, forKey: "drive_refresh_token_\(userID)") }
    }
    private var tokenExpiry: Date? {
        get {
            if let s = KeychainHelper.shared.get("drive_token_expiry_\(userID)"), let t = TimeInterval(s) { return Date(timeIntervalSince1970: t) }
            return nil
        }
        set {
            let val = newValue?.timeIntervalSince1970.description
            KeychainHelper.shared.set(val, forKey: "drive_token_expiry_\(userID)")
        }
    }

    // 사용자 UID를 받아서 해당 사용자의 토큰을 로드합니다.
    init(userID: String) {
        self.userID = userID
        self.isLinked = (accessToken != nil)
        self.linkedEmail = KeychainHelper.shared.get("drive_email_\(userID)")
    }

    // 사용자 변경 시 호출 (로그인/로그아웃)
    @MainActor
    func updateUser(userID: String) {
        guard userID != self.userID else { return }
        self.userID = userID
        // 새 사용자의 토큰 로드
        self.isLinked = (accessToken != nil)
        self.linkedEmail = KeychainHelper.shared.get("drive_email_\(userID)")
        self.lastSyncAt = nil
    }

    // 로컬(내 기기)의 파일을 읽어서 Google Drive로 업로드해요.
    // 파일 이름은 아래 'Upload with Renaming' 규칙을 따르게 돼요.
    func upload(localURL: URL, to remotePath: String) async throws {
        let data = try Data(contentsOf: localURL)
        let originalName = localURL.lastPathComponent
        try await upload(data: data, originalName: originalName, albumName: nil, createdAt: nil, to: remotePath)
    }

    // 다운로드 기능은 아직 구현하지 않았어요.
    func download(from remotePath: String, to destinationURL: URL) async throws {
        // Not implemented in this pass
        throw NSError(domain: "Drive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download not implemented"]) 
    }

    // 지정한 로컬 폴더 안의 파일들을 하나씩 업로드해요.
    // 간단한 예시라서 '이미 있으면 건너뛰기' 같은 고급 기능은 아직 없어요.
    func synchronize(localFolder: URL, with remoteFolder: String) async throws {
        // Example: iterate local files and upload if missing
        let items = try FileManager.default.contentsOfDirectory(at: localFolder, includingPropertiesForKeys: nil)
        for url in items where url.isFileURL {
            try await upload(localURL: url, to: remoteFolder)
        }
        await MainActor.run { self.lastSyncAt = Date() }
    }
    
    // PHAsset 배열을 Google Drive에 업로드합니다.
    // 폴더 구조: ZAKAR/{부서}/{연도}/{날짜}_{이벤트명}/
    // 파일명 형식: {부서}_{날짜시간}_{원본명}.{확장자}
    func uploadAssets(
        _ assets: [PHAsset],
        department: String,
        eventName: String,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws {
        guard !assets.isEmpty else { return }
        
        print("[GoogleDrive] uploadAssets called with department: '\(department)', eventName: '\(eventName)', asset count: \(assets.count)")
        
        await MainActor.run {
            self.isUploading = true
            self.uploadQueue.removeAll()
        }
        
        defer {
            Task { @MainActor in
                self.isUploading = false
            }
        }
        
        // 첫 번째 사진의 날짜를 기준으로 연도 및 날짜 폴더명 생성
        let referenceDate = assets.first?.creationDate ?? Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: referenceDate)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: referenceDate)
        
        // 폴더 경로: ZAKAR/{부서}/{연도}/{부서}_{날짜}_{이벤트명}/
        let folderPath = "ZAKAR/\(department)/\(year)/\(department)_\(dateStr)_\(eventName)/"
        
        // 업로드 큐 생성 (원본 파일명 그대로 사용)
        var queue: [DriveUploadItem] = []
        for asset in assets {
            if let originalFileName = try? await getAssetFileName(asset: asset) {
                let sizeStr = "예상 중..."
                queue.append(DriveUploadItem(
                    filename: originalFileName,  // 원본 파일명 그대로
                    size: sizeStr,
                    progress: 0,
                    status: .waiting
                ))
            }
        }
        
        await MainActor.run {
            self.uploadQueue = queue
        }
        
        // 📌 최적화: 폴더를 미리 한 번만 생성
        print("[GoogleDrive] Creating folder structure: \(folderPath)")
        let startTime = Date()
        
        try await ensureAccessTokenValid()
        guard let token = accessToken else {
            throw NSError(domain: "Drive", code: -2, userInfo: [NSLocalizedDescriptionKey: "No access token"])
        }
        
        let folderId = try await ensureFolderPath(folderPath, token: token)
        let folderCreationTime = Date().timeIntervalSince(startTime)
        print("[GoogleDrive] Folder created in \(String(format: "%.2f", folderCreationTime))s, folderId: \(folderId)")
        
        // 📌 병렬 업로드 (동시 5개씩 처리)
        let concurrentLimit = 5
        var completedCount = 0
        
        await withTaskGroup(of: (Int, Bool).self) { group in
            var currentIndex = 0
            
            // 초기 배치 시작
            for index in 0..<min(concurrentLimit, assets.count) {
                group.addTask {
                    await self.uploadSingleAsset(
                        index: index,
                        asset: assets[index],
                        department: department,
                        folderId: folderId,
                        token: token
                    )
                }
                currentIndex += 1
            }
            
            // 완료되는 대로 새 작업 추가
            for await _ in group {
                completedCount += 1
                
                await MainActor.run {
                    progressHandler?(completedCount, assets.count)
                }
                
                // 다음 작업 추가
                if currentIndex < assets.count {
                    group.addTask {
                        await self.uploadSingleAsset(
                            index: currentIndex,
                            asset: assets[currentIndex],
                            department: department,
                            folderId: folderId,
                            token: token
                        )
                    }
                    currentIndex += 1
                }
            }
        }
        
        await MainActor.run { self.lastSyncAt = Date() }
    }
    
    // 완료된 업로드 항목 제거
    func clearCompletedUploads() {
        uploadQueue.removeAll { $0.status == .done }
    }
    
    // 단일 asset 업로드 (병렬 처리용)
    private func uploadSingleAsset(
        index: Int,
        asset: PHAsset,
        department: String,
        folderId: String,
        token: String
    ) async -> (Int, Bool) {
        let assetStartTime = Date()
        
        do {
            // 상태를 uploading으로 변경
            await MainActor.run {
                if index < self.uploadQueue.count {
                    self.uploadQueue[index].status = .uploading
                }
            }
            
            print("[GoogleDrive] [\(index + 1)] Extracting image data...")
            
            // PHAsset에서 이미지 데이터 추출
            guard let imageData = try await extractImageData(from: asset),
                  let originalFileName = try await getAssetFileName(asset: asset) else {
                throw NSError(domain: "Drive", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to extract asset data"])
            }
            
            let extractTime = Date().timeIntervalSince(assetStartTime)
            print("[GoogleDrive] [\(index + 1)] Extracted in \(String(format: "%.2f", extractTime))s, size: \(imageData.count / 1_000_000)MB")
            
            // 파일 크기 업데이트
            let sizeMB = Double(imageData.count) / 1_000_000.0
            let sizeStr = String(format: "%.1f MB", sizeMB)
            await MainActor.run {
                if index < self.uploadQueue.count {
                    self.uploadQueue[index].size = sizeStr
                }
            }
            
            print("[GoogleDrive] [\(index + 1)] Uploading '\(originalFileName)' to Drive...")
            
            // Google Drive에 업로드 (원본 파일명 그대로)
            try await uploadDataToFolder(
                imageData,
                fileName: originalFileName,
                folderId: folderId,
                token: token
            )
            
            let totalTime = Date().timeIntervalSince(assetStartTime)
            print("[GoogleDrive] [\(index + 1)] Completed in \(String(format: "%.2f", totalTime))s")
            
            // 상태를 done으로 변경
            await MainActor.run {
                if index < self.uploadQueue.count {
                    self.uploadQueue[index].progress = 1.0
                    self.uploadQueue[index].status = .done
                }
            }
            
            return (index, true)
            
        } catch {
            print("[GoogleDrive] [\(index + 1)] Failed: \(error)")
            // 상태를 failed로 변경
            await MainActor.run {
                if index < self.uploadQueue.count {
                    self.uploadQueue[index].status = .failed
                }
            }
            return (index, false)
        }
    }
    
    // PHAsset에서 이미지 데이터를 추출합니다
    private func extractImageData(from asset: PHAsset) async throws -> Data? {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
    
    // PHAsset의 원본 파일명을 가져옵니다
    private func getAssetFileName(asset: PHAsset) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first {
                continuation.resume(returning: resource.originalFilename)
            } else {
                // 파일명을 찾지 못한 경우 기본값 생성
                let ext = asset.mediaType == .image ? "jpg" : "mov"
                continuation.resume(returning: "IMG_\(Int(Date().timeIntervalSince1970)).\(ext)")
            }
        }
    }
    
    // 파일명을 변환합니다: {부서}_{날짜시간}_{원본명}.{확장자}
    private func convertFileName(originalName: String, department: String, createdAt: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: createdAt)
        
        let base = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        let finalExt = ext.isEmpty ? "jpg" : ext
        
        let convertedName = "\(department)_\(timestamp)_\(base).\(finalExt)"
        print("[GoogleDrive] Converting filename: '\(originalName)' -> '\(convertedName)' (dept: '\(department)')")
        
        return convertedName
    }
    
    // 데이터를 지정된 파일명으로 업로드합니다 (폴더 ID 직접 사용 - 최적화 버전)
    private func uploadDataToFolder(_ data: Data, fileName: String, folderId: String, token: String) async throws {
        // 파일 확장자 추출
        let ext = (fileName as NSString).pathExtension
        
        // Multipart upload 구성
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        
        // metadata part
        let meta: [String: Any] = [
            "name": fileName,
            "parents": [folderId]
        ]
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: [])
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metaData)
        body.appendString("\r\n")
        
        // media part
        let mime = mimeType(forExtension: ext)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        
        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            let msg = String(data: respData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(msg)"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: respData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(msg)"])
        }
    }
    
    // 데이터를 지정된 파일명으로 업로드합니다 (기존 메서드 - 호환성 유지)
    private func uploadData(_ data: Data, fileName: String, to remotePath: String) async throws {
        try await ensureAccessTokenValid()
        guard let token = accessToken else {
            throw NSError(domain: "Drive", code: -2, userInfo: [NSLocalizedDescriptionKey: "No access token"])
        }
        
        // 폴더 경로 확인 및 생성
        let folderId = try await ensureFolderPath(remotePath, token: token)
        
        // 최적화된 메서드 호출
        try await uploadDataToFolder(data, fileName: fileName, folderId: folderId, token: token)
    }
    
    // MARK: - URL 기반 파일 업로드 (영상, 문서 등)
    /// URL 배열을 Google Drive에 업로드합니다.
    /// 폴더 구조: ZAKAR/{부서}/{연도}/{날짜}_{이벤트명}/
    /// 파일명: 원본 파일명 그대로 유지
    func uploadFiles(
        _ fileURLs: [URL],
        department: String,
        eventName: String,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async throws {
        guard !fileURLs.isEmpty else { return }
        
        print("[GoogleDrive] uploadFiles called with department: '\(department)', eventName: '\(eventName)', file count: \(fileURLs.count)")
        
        await MainActor.run {
            self.isUploading = true
            self.uploadQueue.removeAll()
        }
        
        defer {
            Task { @MainActor in
                self.isUploading = false
            }
        }
        
        // 현재 날짜를 기준으로 연도 및 날짜 폴더명 생성
        let referenceDate = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: referenceDate)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: referenceDate)
        
        // 폴더 경로: ZAKAR/{부서}/{연도}/{날짜}_{이벤트명}/
        let folderPath = "ZAKAR/\(department)/\(year)/\(dateStr)_\(eventName)/"
        
        // 업로드 큐 생성
        var queue: [DriveUploadItem] = []
        for url in fileURLs {
            let fileName = url.lastPathComponent
            let sizeStr = fileSizeString(url: url) ?? "알 수 없음"
            queue.append(DriveUploadItem(
                filename: fileName,
                size: sizeStr,
                progress: 0,
                status: .waiting
            ))
        }
        
        await MainActor.run {
            self.uploadQueue = queue
        }
        
        // 📌 폴더를 미리 한 번만 생성
        print("[GoogleDrive] Creating folder structure: \(folderPath)")
        let startTime = Date()
        
        try await ensureAccessTokenValid()
        guard let token = accessToken else {
            throw NSError(domain: "Drive", code: -2, userInfo: [NSLocalizedDescriptionKey: "No access token"])
        }
        
        let folderId = try await ensureFolderPath(folderPath, token: token)
        let folderCreationTime = Date().timeIntervalSince(startTime)
        print("[GoogleDrive] Folder created in \(String(format: "%.2f", folderCreationTime))s, folderId: \(folderId)")
        
        // 📌 병렬 업로드 (동시 3개씩 처리 - 파일이 클 수 있으므로)
        let concurrentLimit = 3
        var completedCount = 0
        
        await withTaskGroup(of: (Int, Bool).self) { group in
            var currentIndex = 0
            
            // 초기 배치 시작
            for index in 0..<min(concurrentLimit, fileURLs.count) {
                group.addTask {
                    await self.uploadSingleFile(
                        index: index,
                        fileURL: fileURLs[index],
                        folderId: folderId,
                        token: token
                    )
                }
                currentIndex += 1
            }
            
            // 완료되는 대로 새 작업 추가
            for await _ in group {
                completedCount += 1
                
                await MainActor.run {
                    progressHandler?(completedCount, fileURLs.count)
                }
                
                // 다음 작업 추가
                if currentIndex < fileURLs.count {
                    group.addTask {
                        await self.uploadSingleFile(
                            index: currentIndex,
                            fileURL: fileURLs[currentIndex],
                            folderId: folderId,
                            token: token
                        )
                    }
                    currentIndex += 1
                }
            }
        }
        
        await MainActor.run { self.lastSyncAt = Date() }
    }
    
    // 단일 파일 업로드 (병렬 처리용)
    private func uploadSingleFile(
        index: Int,
        fileURL: URL,
        folderId: String,
        token: String
    ) async -> (Int, Bool) {
        let fileStartTime = Date()
        
        do {
            // 상태를 uploading으로 변경
            await MainActor.run {
                if index < self.uploadQueue.count {
                    self.uploadQueue[index].status = .uploading
                }
            }
            
            print("[GoogleDrive] [\(index + 1)] Reading file data...")
            
            // 파일 데이터 읽기
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            
            let extractTime = Date().timeIntervalSince(fileStartTime)
            print("[GoogleDrive] [\(index + 1)] Read in \(String(format: "%.2f", extractTime))s, size: \(fileData.count / 1_000_000)MB")
            
            print("[GoogleDrive] [\(index + 1)] Uploading '\(fileName)' to Drive...")
            
            // Google Drive에 업로드 (원본 파일명 그대로)
            try await uploadDataToFolder(
                fileData,
                fileName: fileName,
                folderId: folderId,
                token: token
            )
            
            let totalTime = Date().timeIntervalSince(fileStartTime)
            print("[GoogleDrive] [\(index + 1)] Completed in \(String(format: "%.2f", totalTime))s")
            
            // 상태를 done으로 변경
            await MainActor.run {
                if index < self.uploadQueue.count {
                    self.uploadQueue[index].progress = 1.0
                    self.uploadQueue[index].status = .done
                }
            }
            
            return (index, true)
            
        } catch {
            print("[GoogleDrive] [\(index + 1)] Failed: \(error)")
            // 상태를 failed로 변경
            await MainActor.run {
                if index < self.uploadQueue.count {
                    self.uploadQueue[index].status = .failed
                }
            }
            return (index, false)
        }
    }
    
    // 파일 크기를 사람이 읽을 수 있는 형식으로 변환
    private func fileSizeString(url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    


    // 구글 로그인 화면을 띄워서 연결해요.
    // ASWebAuthenticationSession을 통해 시스템 브라우저에서 OAuth를 진행합니다.
    // 성공하면 isLinked가 true가 되고, 실패하면 linkError에 에러 메시지가 저장돼요.
    func link() async {
        await MainActor.run { self.isLinking = true; self.linkError = nil }
        defer { Task { await MainActor.run { self.isLinking = false } } }

        // Client ID 미설정 시 안내
        if clientID.hasPrefix("<YOUR") {
            await MainActor.run {
                self.linkError = "Google Cloud Console에서 iOS OAuth Client ID를 발급 후\nGoogleDriveService.swift의 clientID를 교체해주세요."
            }
            return
        }

        do {
            try await startOAuth()
            await fetchUserInfo() // 구글 계정 이메일 가져오기
            await MainActor.run { self.isLinked = true }
        } catch {
            print("[GoogleDrive] OAuth failed: \(error)")
            let msg = (error as NSError).localizedDescription
            await MainActor.run {
                self.isLinked = false
                self.linkError = msg
            }
        }
    }

    // 저장된 토큰을 모두 지우고 연결을 끊어요.
    // 이후에는 다시 로그인해서 연결해야 해요.
    func unlink() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        KeychainHelper.shared.set(nil, forKey: "drive_email_\(userID)")
        isLinked = false
        linkedEmail = nil
        lastSyncAt = nil
    }

    // 업로드할 때 보기 좋게 파일 이름을 바꿔서 올려요.
    // 규칙: [앨범명]_[날짜시간]_원래이름.확장자 (예: Album_20250101_121314_IMG001.jpg)
    // 그리고, 업로드할 폴더 경로가 없으면 만들어서 그 안에 올려요.
    func upload(data: Data, originalName: String, albumName: String?, createdAt: Date?, to remoteFolder: String) async throws {
        try await ensureAccessTokenValid()
        guard let token = accessToken else { throw NSError(domain: "Drive", code: -2, userInfo: [NSLocalizedDescriptionKey: "No access token"]) }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = createdAt.map { dateFormatter.string(from: $0) } ?? dateFormatter.string(from: Date())
        let base = (originalName as NSString).deletingPathExtension
        let ext = ((originalName as NSString).pathExtension.isEmpty ? "jpg" : (originalName as NSString).pathExtension)
        let album = (albumName ?? "Album").replacingOccurrences(of: " ", with: "_")
        let newName = "\(album)_\(stamp)_\(base).\(ext)"

        // 업로드할 경로가 실제로 있는지 확인하고, 없으면 폴더를 만들어서 그 ID를 받아와요.
        let folderId = try await ensureFolderPath(remoteFolder, token: token)

        // 구글 드라이브는 메타데이터(파일 이름, 부모 폴더 등)와 실제 파일 데이터를 함께 보내는 '멀티파트' 업로드를 지원해요.
        // 경계(boundary)를 정하고, 메타정보 부분과 파일 부분을 차례로 붙여서 전송해요.
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // metadata part
        let meta: [String: Any] = [
            "name": newName,
            "parents": [folderId]
        ]
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: [])
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metaData)
        body.appendString("\r\n")

        // media part
        // 파일 확장자에 맞는 MIME 타입을 정해요. (이미지면 image/jpeg 같은 형식)
        let mime = mimeType(forExtension: ext)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            let msg = String(data: respData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(msg)"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: respData, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(msg)"])
        }
    }

    // 파일 확장자에 따라 서버에 알려줄 파일 형식(MIME type)을 돌려줘요.
    // 모르면 기본값(application/octet-stream)을 사용해요.
    private func mimeType(forExtension ext: String) -> String {
        let lower = ext.lowercased()
        switch lower {
        // 이미지
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        // 영상
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        // 문서
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    // 액세스 토큰이 아직 유효하면 그냥 쓰고,
    // 만료가 가까우면 리프레시 토큰으로 새 토큰을 받아와요.
    // 둘 다 없으면 로그인 과정을 시작해요.
    private func ensureAccessTokenValid() async throws {
        if let expiry = tokenExpiry, Date() < expiry.addingTimeInterval(-60), accessToken != nil {
            return
        }
        if let refresh = refreshToken {
            try await refreshAccessToken(refreshToken: refresh)
            return
        }
        // No token: start OAuth
        try await startOAuth()
    }

    // PKCE 방식의 OAuth2 로그인 절차를 시작해요.
    // 1) 무작위 검증 문자열(verifier)을 만들고,
    // 2) 그걸 해시해서 challenge를 만든 다음,
    // 3) 웹 인증 세션을 열어 사용자가 로그인하면,
    // 4) 콜백으로 받은 '코드'를 액세스 토큰으로 바꿔요.
    private func startOAuth() async throws {
        // PKCE
        let verifier = PKCE.randomVerifier()
        let challenge = verifier.challenge()

        var comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "\(redirectScheme):/oauthcallback"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        let authURL = comps.url!

        // 웹 인증 세션에서 콜백 URL을 받으면, 그 안의 'code' 값을 꺼내요.
        let callbackScheme = "\(redirectScheme)"
        let code: String = try await withCheckedThrowingContinuation { cont in
            self.authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, error in
                defer { self.authSession = nil }
                if let error = error { cont.resume(throwing: error); return }
                guard let url = url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let codeItem = comps.queryItems?.first(where: { $0.name == "code" }), let code = codeItem.value else {
                    cont.resume(throwing: NSError(domain: "Drive", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing auth code"]))
                    return
                }
                cont.resume(returning: code)
            }
            self.authSession?.presentationContextProvider = self.anchorProvider
            self.authSession?.prefersEphemeralWebBrowserSession = true
            _ = self.authSession?.start()
        }
        // 받은 'code'와 verifier를 사용해 액세스 토큰/리프레시 토큰으로 교환해요.
        try await exchangeCodeForToken(code: code, verifier: verifier)
    }

    // 로그인 후 받은 '코드'를 서버에 보내서 액세스 토큰과 리프레시 토큰을 받아와요.
    // 응답에 만료 시간(expires_in)이 있으면 현재 시간에 더해서 저장해요.
    private func exchangeCodeForToken(code: String, verifier: String) async throws {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        let params: [String: String] = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": "\(redirectScheme):/oauthcallback",
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.percentEncoded()

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(msg)"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(msg)"])
        }
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        self.accessToken = json?["access_token"] as? String
        self.refreshToken = json?["refresh_token"] as? String ?? self.refreshToken
        if let expiresIn = json?["expires_in"] as? Double {
            self.tokenExpiry = Date().addingTimeInterval(expiresIn)
        }
    }

    // OAuth 성공 후 구글 계정 이메일 정보를 가져와요.
    private func fetchUserInfo() async {
        guard let token = accessToken else { return }
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                KeychainHelper.shared.set(email, forKey: "drive_email_\(userID)")
                await MainActor.run { self.linkedEmail = email }
            }
        } catch {
            print("[GoogleDrive] Failed to fetch user info: \(error)")
        }
    }

    // 리프레시 토큰을 사용해 새로운 액세스 토큰을 받아와요.
    // 유효 시간이 다시 설정돼요.
    private func refreshAccessToken(refreshToken: String) async throws {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        let params: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.percentEncoded()

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Refresh failed: \(msg)"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Refresh failed: \(msg)"])
        }
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        self.accessToken = json?["access_token"] as? String
        if let expiresIn = json?["expires_in"] as? Double {
            self.tokenExpiry = Date().addingTimeInterval(expiresIn)
        }
    }

    // "ZAKAR/Uploads" 같은 경로 문자열을 '/'로 나눠서 한 단계씩 확인해요.
    // 없는 폴더는 새로 만들고, 최종 폴더의 ID를 돌려줘요.
    private func ensureFolderPath(_ path: String, token: String) async throws -> String {
        // Split path like "ZAKAR/Uploads" and create if missing
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        var parent = "root"
        for name in parts {
            if let id = try await findFolder(named: name, inParent: parent, token: token) {
                parent = id
            } else {
                parent = try await createFolder(named: name, inParent: parent, token: token)
            }
        }
        return parent
    }

    // 특정 부모 폴더 안에서 이름이 같은 '폴더'를 검색해요. 있으면 그 폴더 ID를 돌려줘요.
    private func findFolder(named name: String, inParent parent: String, token: String) async throws -> String? {
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let q = "mimeType='application/vnd.google-apps.folder' and name='\(name.replacingOccurrences(of: "'", with: "\\'"))' and '\(parent)' in parents and trashed=false"
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        if let files = json?["files"] as? [[String: Any]], let first = files.first, let id = first["id"] as? String {
            return id
        }
        return nil
    }

    // 새 폴더를 만들어서 그 ID를 돌려줘요.
    private func createFolder(named name: String, inParent parent: String, token: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let meta: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder",
            "parents": [parent]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: meta, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: -1, userInfo: [NSLocalizedDescriptionKey: "Create folder failed: \(msg)"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Drive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Create folder failed: \(msg)"])
        }
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let id = json?["id"] as? String else {
            throw NSError(domain: "Drive", code: -4, userInfo: [NSLocalizedDescriptionKey: "Missing folder id"]) 
        }
        return id
    }
}

// 문자열을 Data에 간편하게 붙이기 위한 도우미 확장이에요.
private extension Data {
    mutating func appendString(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

// 딕셔너리를 폼 전송 형식(application/x-www-form-urlencoded)으로 바꿔주는 함수예요.
private extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}

// PKCE에서 쓰는 무작위 검증 문자열(verifier)을 만들어줘요.
private struct PKCE {
    static func randomVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }
}

// 검증 문자열을 SHA-256으로 해시하고, URL에서 안전한 Base64 문자열로 바꿔요.
private extension String {
    func challenge() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        return data.sha256().base64URLEncodedString()
    }
}

// 해시 계산(SHA-256)과 URL-safe Base64 인코딩을 도와주는 확장이에요.
private extension Data {
    func sha256() -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &digest) }
        return Data(digest)
    }
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// 웹 인증 창(ASWebAuthenticationSession)을 어느 윈도우 위에 띄울지 알려주는 객체예요.
private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        if let scene {
            return scene.windows.first(where: { $0.isKeyWindow })
                ?? scene.windows.first
                ?? UIWindow(windowScene: scene)
        }
        // 씬이 없는 경우는 실제로 발생하지 않음 (iOS 13+에서 씬 기반 앱이므로)
        preconditionFailure("No UIWindowScene available")
    }
}

// 민감한 값을 안전하게 저장/읽기 하기 위해 iOS 키체인을 사용해요.
// set(_:forKey:)로 저장하고, get(_:)으로 꺼내요.
final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    func set(_ value: String?, forKey key: String) {
        let service = "ZAKAR.DriveAuth"
        let account = key
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value = value else { return }
        let attrs: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecValueData as String: value.data(using: .utf8) ?? Data()]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        let service = "ZAKAR.DriveAuth"
        let account = key
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// 사용자가 드라이브 연결/해제를 하고, 수동 동기화를 실행할 수 있는 설정 화면이에요.
// 버튼을 누르면 비동기 작업(Task)으로 실제 기능을 호출해요.
struct DriveSettingsView: View {
    @StateObject private var drive = GoogleDriveService(userID: "preview")
    @State private var isSyncing = false

    // 화면 레이아웃과 버튼들이 정의된 부분이에요.
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Google Drive 연동")) {
                    HStack {
                        Text("상태")
                        Spacer()
                        Text(drive.isLinked ? "연결됨" : "연결 안 됨").foregroundColor(drive.isLinked ? .green : .secondary)
                    }
                    if drive.isLinked {
                        HStack {
                            Text("최근 동기화")
                            Spacer()
                            Text(lastSyncText)
                        }
                    }
                    Button(drive.isLinked ? "연결 해제" : "연결하기") {
                        Task { await toggleLink() }
                    }
                }

                Section(header: Text("수동 동기화")) {
                    Button(isSyncing ? "동기화 중..." : "지금 동기화") {
                        Task { await syncNow() }
                    }.disabled(!drive.isLinked || isSyncing)
                }
            }
            .navigationTitle("드라이브 설정")
        }
    }

    // 마지막 동기화 시간을 보기 좋게 MM/dd HH:mm 형태로 보여줘요.
    private var lastSyncText: String {
        guard let d = drive.lastSyncAt else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }

    // 연결 상태에 따라 로그인(연결)하거나, 토큰을 지우고 연결을 끊어요.
    private func toggleLink() async {
        if drive.isLinked { drive.unlink() }
        else { await drive.link() }
    }

    // 수동 동기화 버튼을 눌렀을 때 실행돼요.
    // 앱의 Application Support 폴더를 찾아서, 그 안의 파일들을 드라이브로 업로드해요.
    // 동기화 중에는 버튼이 비활성화돼요.
    private func syncNow() async {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        isSyncing = true
        defer { isSyncing = false }
        try? await drive.synchronize(localFolder: support, with: "ZAKAR/")
    }
}

#Preview {
    DriveSettingsView()
}

