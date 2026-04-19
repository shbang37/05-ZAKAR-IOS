import Foundation
import SwiftUI
import Photos
import Combine

// MARK: - Album 정보 모델
struct AlbumInfo: Identifiable, Hashable {
    let id: String
    let collection: PHAssetCollection
    let title: String
    let assetCount: Int
    let startDate: Date?
    let endDate: Date?
    
    init(collection: PHAssetCollection) {
        self.id = collection.localIdentifier
        self.collection = collection
        self.title = collection.localizedTitle ?? "제목 없음"
        
        let fetchResult = PHAsset.fetchAssets(in: collection, options: nil)
        self.assetCount = fetchResult.count
        
        // 앨범의 첫 번째/마지막 사진 날짜
        if fetchResult.count > 0 {
            self.startDate = fetchResult.firstObject?.creationDate
            self.endDate = fetchResult.lastObject?.creationDate
        } else {
            self.startDate = nil
            self.endDate = nil
        }
    }
}

// MARK: - ML 학습 모델
/// 사진의 특징을 저장하는 구조체
struct PhotoFeatures: Codable {
    let fileSize: Double           // 파일 크기 (bytes)
    let resolution: Int            // 해상도 (�elWidth * pixelHeight)
    let isLandscape: Bool          // 가로/세로
    let hourOfDay: Int             // 촬영 시간 (0-23)
    let isFavorite: Bool           // 즐겨찾기 여부
    let timestamp: Date            // 기록 시간
}

/// 사용자 선호도 학습 데이터
struct UserPreferences: Codable {
    var keptPhotos: [PhotoFeatures] = []       // 유지한 사진들
    var discardedPhotos: [PhotoFeatures] = []  // 삭제한 사진들
    
    // 평균 파일 크기
    var preferredFileSize: Double {
        guard !keptPhotos.isEmpty else { return 0 }
        return keptPhotos.map { $0.fileSize }.reduce(0, +) / Double(keptPhotos.count)
    }
    
    // 평균 해상도
    var preferredResolution: Double {
        guard !keptPhotos.isEmpty else { return 0 }
        return keptPhotos.map { Double($0.resolution) }.reduce(0, +) / Double(keptPhotos.count)
    }
    
    // 가로 사진 선호도
    var prefersLandscape: Bool {
        guard !keptPhotos.isEmpty else { return true }
        let landscapeCount = keptPhotos.filter { $0.isLandscape }.count
        return Double(landscapeCount) / Double(keptPhotos.count) > 0.5
    }
    
    // 선호 시간대
    var preferredHours: [Int] {
        guard !keptPhotos.isEmpty else { return [] }
        let hours = keptPhotos.map { $0.hourOfDay }
        let uniqueHours = Set(hours)
        return uniqueHours.sorted()
    }
    
    // 학습 데이터 충분 여부
    var hasEnoughData: Bool {
        return keptPhotos.count >= 10
    }
}

class PhotoManager: ObservableObject {
    enum SimilarityPreset: Int { case light = 14, balanced = 18, strict = 22 }
    var similarityPreset: SimilarityPreset = .balanced

    @Published var allPhotos: [PHAsset] = []
    @Published var groupedPhotos: [[PHAsset]] = []
    @Published var albums: [AlbumInfo] = []
    @Published var isLoadingList = false
    @Published var isAnalyzing = false
    @Published var trashAssets: [PHAsset] = []
    private var didAnalyzeForCurrentList = false
    private var shouldAnalyzeAfterLoad = false
    
    // 분석 성능 향상을 위한 캐시
    private var hashCache: [String: UInt64] = [:]
    
    // 동시 fetch 방지 플래그
    private var isFetching = false
    
    // 현재 적용된 필터 추적
    private var currentFilterYear: Int? = nil
    private var currentFilterMonth: Int? = nil

    // MARK: - 리소스 정리
    /// 필터 변경 시 분석 상태 및 캐시 초기화
    func resetAnalysisState() {
        print("ZAKAR Log: PhotoManager - resetAnalysisState called")
        Task { @MainActor in
            self.hashCache.removeAll()
            self.didAnalyzeForCurrentList = false
            self.groupedPhotos = []
        }
    }

    // MARK: - 메인 로직: 사진 불러오기 (전체)
    func fetchPhotos() {
        fetchPhotos(year: nil, month: nil)
    }

    // MARK: - 메인 로직: 사진 불러오기 (연/월 필터 지원)
    func fetchPhotos(year: Int?, month: Int?) {
        // 동일한 필터로 이미 로드되어 있고 사진이 있으면 스킵
        if !allPhotos.isEmpty && year == currentFilterYear && month == currentFilterMonth && !isFetching {
            print("ZAKAR Log: PhotoManager - Same filter already loaded with \(allPhotos.count) photos, skipping")
            return
        }
        
        // 동일한 필터로 이미 로드 중이면 스킵
        if isFetching && year == currentFilterYear && month == currentFilterMonth {
            print("ZAKAR Log: PhotoManager - Same filter already loading, skipping")
            return
        }
        
        // 필터가 변경되었으면 기존 fetch 무시하고 새로 시작
        if year != currentFilterYear || month != currentFilterMonth {
            print("ZAKAR Log: PhotoManager - Filter changed from (\(currentFilterYear?.description ?? "nil"), \(currentFilterMonth?.description ?? "nil")) to (\(year?.description ?? "nil"), \(month?.description ?? "nil")), forcing new fetch")
            isFetching = false  // 기존 fetch 무시
        }
        
        guard !isFetching else {
            print("ZAKAR Log: PhotoManager - fetchPhotos already in progress, skipping")
            return
        }
        
        isFetching = true
        currentFilterYear = year
        currentFilterMonth = month
        print("ZAKAR Log: PhotoManager - fetchPhotos started (year: \(year?.description ?? "nil"), month: \(month?.description ?? "nil"))")
        Task { @MainActor in
            self.isLoadingList = true
            self.isAnalyzing = false
            self.didAnalyzeForCurrentList = false
            self.groupedPhotos = []
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        print("🟢 ZAKAR Log: PhotoManager - Photo library authorization status: \(status.rawValue)")
        switch status {
        case .authorized, .limited:
            print("🟢 ZAKAR Log: PhotoManager - Loading assets")
            self.loadAssets(year: year, month: month)
        case .notDetermined:
            // ⚠️ 중요: 권한 미결정 상태에서는 자동으로 요청하지 않음
            // 온보딩에서 사용자가 명시적으로 권한을 허용한 후에만 fetchPhotos() 호출되어야 함
            print("🟡 ZAKAR Log: PhotoManager - Photo authorization not determined. User must grant permission first.")
            Task { @MainActor in
                self.isLoadingList = false
                self.isFetching = false
            }
            // 자동 권한 요청 제거
            // PHPhotoLibrary.requestAuthorization()는 OnboardingView에서만 호출
        default:
            print("🔴 ZAKAR Log: PhotoManager - Photo authorization status: \(status.rawValue)")
            Task { @MainActor in
                self.isLoadingList = false
                self.isFetching = false
            }
        }
    }

    private func loadAssets(year: Int?, month: Int?) {
        Task(priority: .userInitiated) {
            let options = PHFetchOptions()
            // 시간순 정렬 (최신 것부터) - 사용자가 최근 사진을 먼저 보도록
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            var tempAll: [PHAsset] = []
            assets.enumerateObjects { (asset, _, _) in
                tempAll.append(asset)
            }
            
            print("ZAKAR Log: PhotoManager - Fetched \(tempAll.count) photos")

            let filtered: [PHAsset]
            if let y = year, let m = month {
                let cal = Calendar.current
                filtered = tempAll.filter { asset in
                    guard let d = asset.creationDate else { return false }
                    let comps = cal.dateComponents([.year, .month], from: d)
                    return comps.year == y && comps.month == m
                }
            } else if let y = year {
                let cal = Calendar.current
                filtered = tempAll.filter { asset in
                    guard let d = asset.creationDate else { return false }
                    let comps = cal.dateComponents([.year], from: d)
                    return comps.year == y
                }
            } else {
                filtered = tempAll
            }

            await MainActor.run {
                self.allPhotos = filtered
                self.isLoadingList = false
                self.groupedPhotos = []
                self.isAnalyzing = false
                self.didAnalyzeForCurrentList = false
                self.isFetching = false  // 로딩 완료 후 플래그 해제
                
                print("ZAKAR Log: PhotoManager - allPhotos set to \(self.allPhotos.count) photos, isFetching reset")

                if self.shouldAnalyzeAfterLoad {
                    self.shouldAnalyzeAfterLoad = false
                    // Trigger analysis now that photos are loaded
                    self.analyzeSimilaritiesIfNeeded()
                }
            }
        }
    }
    
    func analyzeSimilaritiesIfNeeded() {
        if allPhotos.isEmpty {
            // 사진 로딩 완료 후 자동으로 분석 시작
            shouldAnalyzeAfterLoad = true
            return
        }
        guard !didAnalyzeForCurrentList, !allPhotos.isEmpty else { return }
        didAnalyzeForCurrentList = true
        Task { @MainActor in self.isAnalyzing = true }

        // 분석 시작 전 이전 결과 초기화
        Task { @MainActor in self.groupedPhotos = [] }

        Task(priority: .userInitiated) { [assets = self.allPhotos] in
            self.analyzeGroupsProgressive(assets: assets)
            await MainActor.run { self.isAnalyzing = false }
        }
    }

    // MARK: - 임시 휴지통 (공유 상태)
    /// LocalDB에서 휴지통 목록을 로드합니다. 앱 시작 및 뷰 진입 시 호출하세요.
    func loadTrash() {
        let ids = LocalDB.shared.loadTrashIdentifiers()
        guard !ids.isEmpty else { trashAssets = []; return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var temp: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in temp.append(asset) }
        trashAssets = temp
    }

    /// 현재 trashAssets를 LocalDB에 저장합니다.
    func saveTrash() {
        let ids = trashAssets.map { $0.localIdentifier }
        LocalDB.shared.saveTrashIdentifiers(ids)
    }

    // MARK: - 핵심 기능: 실제 사진 라이브러리에서 삭제
    /// - Parameters:
    ///   - assets: 삭제할 PHAsset 배열
    ///   - completion: 삭제 성공 여부를 반환하는 클로저
    func deleteAssets(_ assets: [PHAsset], completion: @escaping (Bool) -> Void) {
        // 삭제 전 용량 추정 (HEIC 평균 ~3.5MB, JPEG 평균 ~2.5MB 기준)
        let estimatedMB = assets.reduce(0.0) { sum, asset in
            let mb: Double = asset.mediaType == .image ? 3.5 : 15.0
            return sum + mb
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, error in
            Task { @MainActor in
                if success {
                    print("ZAKAR Log: 사진 \(assets.count)장 삭제 성공")
                    // 삭제 통계를 LocalDB에 기록
                    self.recordCleanupStats(deletedCount: assets.count, savedMB: estimatedMB)
                    // 사진 목록 재로드 및 재분석
                    self.shouldAnalyzeAfterLoad = true
                    self.fetchPhotos()
                } else {
                    print("ZAKAR Log: 사진 삭제 실패 또는 유저 거부: \(error?.localizedDescription ?? "알 수 없는 에러")")
                }
                completion(success)
            }
        }
    }

    /// 삭제 후 LocalDB에 정리 날짜와 절감 용량을 누적 저장합니다.
    private func recordCleanupStats(deletedCount: Int, savedMB: Double) {
        var meta = LocalDB.shared.loadMetadata()
        meta.lastCleanupDate = Date()
        // 누적 절감 용량 (기존 + 이번 삭제분)
        let previous = meta.estimatedSavedMB ?? 0.0
        meta.estimatedSavedMB = previous + savedMB
        LocalDB.shared.saveMetadata(meta)
        print("ZAKAR Log: 정리 기록 저장 - 날짜: \(Date()), 절감: \(String(format: "%.1f", savedMB))MB (누적: \(String(format: "%.1f", meta.estimatedSavedMB ?? 0))MB)")
    }

    // MARK: - 분석 로직: 유사 사진 그룹화 (점진적 표시)
    // 그룹이 완성될 때마다 UI에 즉시 반영하여 첫 결과를 빠르게 표시합니다.
    private func analyzeGroupsProgressive(assets: [PHAsset]) {
        guard !assets.isEmpty else {
            print("ZAKAR Log: analyzeGroupsProgressive - no assets to analyze")
            return
        }
        
        print("📸 ZAKAR Log: Starting analysis of \(assets.count) photos")
        var currentTimeGroup: [PHAsset] = []

        for asset in assets {
            guard let curDate = asset.creationDate else { continue }
            
            // 시간 임계값: 7초
            if let last = currentTimeGroup.last,
               let lastDate = last.creationDate {
                let timeDiff = abs(curDate.timeIntervalSince(lastDate))
                
                if timeDiff <= 7 {
                    currentTimeGroup.append(asset)
                } else {
                    flushTimeGroupIfReady(&currentTimeGroup)
                    currentTimeGroup = [asset]
                }
            } else {
                flushTimeGroupIfReady(&currentTimeGroup)
                currentTimeGroup = [asset]
            }
        }
        flushTimeGroupIfReady(&currentTimeGroup)

        Task { @MainActor in
            print("✅ ZAKAR Log: Analysis complete - \(self.groupedPhotos.count) similar groups found")
        }
    }

    /// 시간 그룹을 시각적 유사도 필터링 후 main thread에 append합니다.
    private func flushTimeGroupIfReady(_ group: inout [PHAsset]) {
        guard group.count >= 2 else { return }
        let visualGroup = filterByVisualSimilarity(group: group)
        if visualGroup.count >= 2 {
            let result = visualGroup
            Task { @MainActor in
                self.groupedPhotos.append(result)
            }
        }
    }

    // 기존 호환성을 위해 유지 (외부에서 호출 안 함)
    private func analyzeGroups(assets: [PHAsset]) {
        analyzeGroupsProgressive(assets: assets)
    }

    private func filterByVisualSimilarity(group: [PHAsset]) -> [PHAsset] {
        guard group.count >= 2 else { return [] }
        
        // 모든 사진의 해시를 미리 계산
        let hashes = group.map { getOrGenerateHash(for: $0) }
        
        // 해시 계산 실패 체크
        let validHashes = hashes.filter { $0 != 0 }
        if validHashes.count < 2 {
            return []
        }
        
        // 첫 번째 사진을 기준으로 시작
        var resultGroup = [group[0]]
        var usedIndices = Set<Int>([0])
        
        // 그룹에 포함된 사진들끼리 서로 유사한지 검증
        for i in 1..<group.count {
            var isSimilarToGroup = false
            
            // 이미 그룹에 포함된 사진들과 비교
            for usedIndex in usedIndices {
                let distance = hammingDistance(hashes[i], hashes[usedIndex])
                
                if distance <= similarityPreset.rawValue {
                    isSimilarToGroup = true
                    break
                }
            }
            
            if isSimilarToGroup {
                resultGroup.append(group[i])
                usedIndices.insert(i)
            }
        }
        
        // 최소 2장 이상만 반환
        return resultGroup.count >= 2 ? resultGroup : []
    }

    // MARK: - pHash Helper Methods
    private func getOrGenerateHash(for asset: PHAsset) -> UInt64 {
        if let cached = hashCache[asset.localIdentifier] { return cached }
        
        // 타임스탬프 기반 빠른 해시 생성 (메모리 부담 감소)
        let fallbackHash: UInt64
        if let date = asset.creationDate {
            fallbackHash = UInt64(date.timeIntervalSince1970 * 1000000)
        } else {
            fallbackHash = UInt64.random(in: 1...UInt64.max)
        }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false  // 비동기로 변경하여 메인 스레드 블로킹 방지
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false
        options.resizeMode = .fast
        
        var generatedHash: UInt64 = fallbackHash
        
        // 작은 이미지만 요청하여 메모리 부담 최소화
        manager.requestImage(for: asset, targetSize: CGSize(width: 16, height: 16), contentMode: .aspectFill, options: options) { image, info in
            if let img = image, let hash = self.calculatePHashSafe(img) {
                generatedHash = hash
            }
        }
        
        hashCache[asset.localIdentifier] = generatedHash
        return generatedHash
    }
    
    private func calculatePHashSafe(_ image: UIImage) -> UInt64? {
        autoreleasepool {
            guard image.cgImage != nil else { return nil }
            return calculatePHash(image)
        }
    }

    private func calculatePHash(_ image: UIImage) -> UInt64 {
        guard let cgImage = image.cgImage else { return 0 }
        // 1) Resize to 32x32 grayscale
        let width = 32, height = 32
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return 0 }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        // 2) Build a 32x32 double matrix
        var f = Array(repeating: Array(repeating: 0.0, count: 32), count: 32)
        for y in 0..<32 {
            for x in 0..<32 {
                f[y][x] = Double(pixels[y * 32 + x])
            }
        }

        // 3) 2D DCT, take top-left 8x8 coefficients
        let N = 32
        let K = 8
        var dct = Array(repeating: Array(repeating: 0.0, count: K), count: K)
        let c: (Int) -> Double = { u in return u == 0 ? 1.0 / sqrt(2.0) : 1.0 }
        let scale = 2.0 / Double(N)
        for v in 0..<K {
            for u in 0..<K {
                var sum = 0.0
                for y in 0..<N {
                    for x in 0..<N {
                        let cos1 = cos(((Double(2*x) + 1.0) * Double(u) * .pi) / Double(2*N))
                        let cos2 = cos(((Double(2*y) + 1.0) * Double(v) * .pi) / Double(2*N))
                        sum += f[y][x] * cos1 * cos2
                    }
                }
                dct[v][u] = scale * c(u) * c(v) * sum
            }
        }

        // 4) Compute average of AC coefficients (exclude DC at [0][0])
        var total = 0.0
        var count = 0.0
        for v in 0..<K {
            for u in 0..<K {
                if v == 0 && u == 0 { continue }
                total += dct[v][u]
                count += 1
            }
        }
        let avg = total / max(count, 1.0)

        // 5) Build 64-bit hash by thresholding 8x8 block (row-major)
        var hash: UInt64 = 0
        var bitIndex: UInt64 = 0
        for v in 0..<K {
            for u in 0..<K {
                if v == 0 && u == 0 { continue }
                if dct[v][u] > avg { hash |= (1 << bitIndex) }
                bitIndex += 1
            }
        }
        return hash
    }

    private func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        return (hash1 ^ hash2).nonzeroBitCount
    }

    // MARK: - Albums: Create / Find / Add
    func findAlbum(named name: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        var result: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == name {
                result = collection
                stop.pointee = true
            }
        }
        return result
    }

    func fetchOrCreateAlbum(named name: String, completion: @escaping (PHAssetCollection?) -> Void) {
        if let existing = findAlbum(named: name) {
            completion(existing)
            return
        }
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }) { success, _ in
            guard success, let id = placeholder?.localIdentifier else {
                Task { @MainActor in completion(nil) }
                return
            }
            let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            Task { @MainActor in completion(fetchResult.firstObject) }
        }
    }

    func addAssets(_ assets: [PHAsset], toAlbum collection: PHAssetCollection, completion: @escaping (Bool) -> Void) {
        guard !assets.isEmpty else { completion(true); return }
        PHPhotoLibrary.shared().performChanges({
            if let changeRequest = PHAssetCollectionChangeRequest(for: collection) {
                changeRequest.addAssets(assets as NSArray)
            }
        }) { success, error in
            if let error = error { print("ZAKAR Log: addAssets error - \(error.localizedDescription)") }
            Task { @MainActor in completion(success) }
        }
    }
    
    // MARK: - 앨범 목록 가져오기
    func fetchAlbums() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            print("[PhotoManager] 사진 라이브러리 권한 필요")
            return
        }
        
        Task(priority: .userInitiated) {
            var albumList: [AlbumInfo] = []
            
            // 사용자 앨범
            let userAlbums = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .albumRegular,
                options: nil
            )
            userAlbums.enumerateObjects { collection, _, _ in
                let info = AlbumInfo(collection: collection)
                if info.assetCount > 0 {
                    albumList.append(info)
                }
            }
            
            // 스마트 앨범 (최근 항목, 즐겨찾기 등)
            let smartAlbums = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .albumRegular,
                options: nil
            )
            smartAlbums.enumerateObjects { collection, _, _ in
                let info = AlbumInfo(collection: collection)
                if info.assetCount > 0 {
                    albumList.append(info)
                }
            }
            
            // 날짜순 정렬 (최신 앨범 먼저)
            albumList.sort { ($0.endDate ?? Date.distantPast) > ($1.endDate ?? Date.distantPast) }
            
            await MainActor.run {
                self.albums = albumList
                print("ZAKAR Log: 앨범 \(albumList.count)개 로드 완료")
            }
        }
    }
    
    // MARK: - 월별 사진 데이터 생성
    func getMonthlyPhotoData() -> [MonthData] {
        var monthDictionary: [String: Int] = [:]
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        
        // 모든 사진을 년월별로 그룹화
        for asset in allPhotos {
            guard let date = asset.creationDate else { continue }
            
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = "\(year)-\(month)"
            
            monthDictionary[key, default: 0] += 1
        }
        
        // MonthData 배열 생성
        var result: [MonthData] = []
        
        for (key, count) in monthDictionary {
            let components = key.split(separator: "-")
            guard components.count == 2,
                  let year = Int(components[0]),
                  let month = Int(components[1]) else {
                continue
            }
            
            let isCurrentMonth = (year == currentYear && month == currentMonth)
            
            result.append(MonthData(
                year: year,
                month: month,
                photoCount: count,
                isCurrentMonth: isCurrentMonth
            ))
        }
        
        // 최신 순으로 정렬 (2026년 4월 → 2026년 3월 → ...)
        result.sort { lhs, rhs in
            if lhs.year != rhs.year {
                return lhs.year > rhs.year
            }
            return lhs.month > rhs.month
        }
        
        return result
    }
    
    // MARK: - ML 학습 기반 대표 사진 선택
    
    /// 사용자 선호도 (UserDefaults에 저장)
    private var userPreferences: UserPreferences {
        get {
            guard let data = UserDefaults.standard.data(forKey: "ZAKAR_UserPreferences"),
                  let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
                return UserPreferences()
            }
            return prefs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "ZAKAR_UserPreferences")
            }
        }
    }
    
    /// 사진의 특징 추출
    private func extractFeatures(from asset: PHAsset) -> PhotoFeatures {
        let resources = PHAssetResource.assetResources(for: asset)
        let fileSize = resources.first?.value(forKey: "fileSize") as? Double ?? 0
        let resolution = asset.pixelWidth * asset.pixelHeight
        let isLandscape = asset.pixelWidth > asset.pixelHeight
        let hour = Calendar.current.component(.hour, from: asset.creationDate ?? Date())
        
        return PhotoFeatures(
            fileSize: fileSize,
            resolution: resolution,
            isLandscape: isLandscape,
            hourOfDay: hour,
            isFavorite: asset.isFavorite,
            timestamp: Date()
        )
    }
    
    /// 사용자 선택 기록 (학습 데이터 수집)
    func recordUserChoice(kept: PHAsset, discarded: [PHAsset]) {
        var prefs = userPreferences
        
        // 유지한 사진 특징 저장
        prefs.keptPhotos.append(extractFeatures(from: kept))
        
        // 버린 사진들 특징 저장
        for photo in discarded {
            prefs.discardedPhotos.append(extractFeatures(from: photo))
        }
        
        // 최근 100개만 유지 (메모리 절약)
        if prefs.keptPhotos.count > 100 {
            prefs.keptPhotos = Array(prefs.keptPhotos.suffix(100))
        }
        if prefs.discardedPhotos.count > 100 {
            prefs.discardedPhotos = Array(prefs.discardedPhotos.suffix(100))
        }
        
        userPreferences = prefs
        print("ZAKAR Log: ML - Recorded user choice. Total data: \(prefs.keptPhotos.count)")
    }
    
    /// 대표 사진 선택 (ML 활용)
    func selectBestPhoto(from group: [PHAsset]) -> PHAsset? {
        guard !group.isEmpty else { return nil }
        
        // 1순위: 즐겨찾기
        if let favorite = group.first(where: { $0.isFavorite }) {
            print("ZAKAR Log: Selected favorite photo")
            return favorite
        }
        
        let prefs = userPreferences
        
        // 2순위: ML 학습 데이터 활용 (데이터 충분시)
        if prefs.hasEnoughData {
            print("ZAKAR Log: Using ML to select best photo (data: \(prefs.keptPhotos.count))")
            return selectBestPhotoWithML(from: group, preferences: prefs)
        }
        
        // 3순위: 기본 로직 (고화질 상위 30% 중 최근)
        print("ZAKAR Log: Using default logic (insufficient ML data)")
        return selectBestPhotoDefault(from: group)
    }
    
    /// ML 기반 선택
    private func selectBestPhotoWithML(from group: [PHAsset], preferences: UserPreferences) -> PHAsset? {
        let scored = group.map { photo -> (photo: PHAsset, score: Double) in
            let features = extractFeatures(from: photo)
            var score = 0.0
            
            // 파일 크기 유사도 (40% 가중치)
            if preferences.preferredFileSize > 0 {
                let sizeDiff = abs(features.fileSize - preferences.preferredFileSize) / preferences.preferredFileSize
                let sizeScore = max(0, 1.0 - sizeDiff)
                score += sizeScore * 0.4
            }
            
            // 해상도 유사도 (30% 가중치)
            if preferences.preferredResolution > 0 {
                let resDiff = abs(Double(features.resolution) - preferences.preferredResolution) / preferences.preferredResolution
                let resScore = max(0, 1.0 - resDiff)
                score += resScore * 0.3
            }
            
            // 방향 선호도 (20% 가중치)
            if features.isLandscape == preferences.prefersLandscape {
                score += 0.2
            }
            
            // 시간대 선호도 (10% 가중치)
            if preferences.preferredHours.contains(features.hourOfDay) {
                score += 0.1
            }
            
            return (photo, score)
        }
        
        return scored.max(by: { $0.score < $1.score })?.photo
    }
    
    /// 기본 선택 로직
    private func selectBestPhotoDefault(from group: [PHAsset]) -> PHAsset? {
        let sortedBySize = group.sorted {
            let resources1 = PHAssetResource.assetResources(for: $0)
            let resources2 = PHAssetResource.assetResources(for: $1)
            let size1 = resources1.first?.value(forKey: "fileSize") as? Double ?? 0
            let size2 = resources2.first?.value(forKey: "fileSize") as? Double ?? 0
            return size1 > size2
        }
        
        let topThird = Array(sortedBySize.prefix(max(1, group.count / 3)))
        return topThird.max {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
    }
    
    /// 전체 그룹 자동 정리
    func autoCleanAllGroups() -> (keptCount: Int, removedCount: Int) {
        var kept: [PHAsset] = []
        var removed: [PHAsset] = []
        
        for group in groupedPhotos {
            if let best = selectBestPhoto(from: group) {
                kept.append(best)
                let discarded = group.filter { $0 != best }
                removed.append(contentsOf: discarded)
                
                // ML 학습 데이터 기록
                recordUserChoice(kept: best, discarded: discarded)
            }
        }
        
        // 휴지통으로 이동
        var currentTrash = LocalDB.shared.loadTrashIdentifiers()
        let removedIds = removed.map { $0.localIdentifier }
        currentTrash.append(contentsOf: removedIds)
        LocalDB.shared.saveTrashIdentifiers(currentTrash)
        
        print("ZAKAR Log: Auto-cleaned \(groupedPhotos.count) groups - kept: \(kept.count), removed: \(removed.count)")
        
        return (kept.count, removed.count)
    }
}

