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

class PhotoManager: ObservableObject {
    enum SimilarityPreset: Int { case light = 14, balanced = 18, strict = 22 }
    var similarityPreset: SimilarityPreset = .balanced

    @Published var allPhotos: [PHAsset] = []
    @Published var groupedPhotos: [[PHAsset]] = []
    @Published var albums: [AlbumInfo] = []
    @Published var isLoadingList = false
    @Published var isAnalyzing = false
    private var didAnalyzeForCurrentList = false
    private var shouldAnalyzeAfterLoad = false
    
    // 분석 성능 향상을 위한 캐시
    private var hashCache: [String: UInt64] = [:]

    // MARK: - 메인 로직: 사진 불러오기 (전체)
    func fetchPhotos() {
        fetchPhotos(year: nil, month: nil)
    }

    // MARK: - 메인 로직: 사진 불러오기 (연/월 필터 지원)
    func fetchPhotos(year: Int?, month: Int?) {
        DispatchQueue.main.async {
            self.isLoadingList = true
            self.isAnalyzing = false
            self.didAnalyzeForCurrentList = false
            self.groupedPhotos = []
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            self.loadAssets(year: year, month: month)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                guard let self = self else { return }
                if newStatus == .authorized || newStatus == .limited {
                    self.fetchPhotos(year: year, month: month)
                } else {
                    DispatchQueue.main.async { self.isLoadingList = false }
                }
            }
        default:
            DispatchQueue.main.async { self.isLoadingList = false }
        }
    }

    private func loadAssets(year: Int?, month: Int?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            var tempAll: [PHAsset] = []
            assets.enumerateObjects { (asset, _, _) in
                tempAll.append(asset)
            }

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

            DispatchQueue.main.async {
                self.allPhotos = filtered
                self.isLoadingList = false
                self.groupedPhotos = []
                self.isAnalyzing = false
                self.didAnalyzeForCurrentList = false

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
        DispatchQueue.main.async { self.isAnalyzing = true }

        // 분석 시작 전 이전 결과 초기화
        DispatchQueue.main.async { self.groupedPhotos = [] }

        DispatchQueue.global(qos: .userInitiated).async { [assets = self.allPhotos] in
            self.analyzeGroupsProgressive(assets: assets)
            DispatchQueue.main.async { self.isAnalyzing = false }
        }
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
            DispatchQueue.main.async {
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
        var currentTimeGroup: [PHAsset] = []

        for asset in assets {
            if let last = currentTimeGroup.last,
               let lastDate = last.creationDate,
               let curDate = asset.creationDate,
               abs(curDate.timeIntervalSince(lastDate)) <= 3 {
                currentTimeGroup.append(asset)
            } else {
                flushTimeGroupIfReady(&currentTimeGroup)
                currentTimeGroup = [asset]
            }
        }
        flushTimeGroupIfReady(&currentTimeGroup)

        DispatchQueue.main.async {
            print("ZAKAR Log: 분석 완료 (\(self.groupedPhotos.count)개 그룹)")
        }
    }

    /// 시간 그룹을 시각적 유사도 필터링 후 main thread에 append합니다.
    private func flushTimeGroupIfReady(_ group: inout [PHAsset]) {
        guard group.count >= 2 else { return }
        let visualGroup = filterByVisualSimilarity(group: group)
        if visualGroup.count >= 2 {
            let result = visualGroup
            DispatchQueue.main.async {
                self.groupedPhotos.append(result)
            }
        }
    }

    // 기존 호환성을 위해 유지 (외부에서 호출 안 함)
    private func analyzeGroups(assets: [PHAsset]) {
        analyzeGroupsProgressive(assets: assets)
    }

    private func filterByVisualSimilarity(group: [PHAsset]) -> [PHAsset] {
        guard let firstAsset = group.first else { return [] }
        var resultGroup = [firstAsset]
        let baseHash = getOrGenerateHash(for: firstAsset)
        
        for i in 1..<group.count {
            let targetHash = getOrGenerateHash(for: group[i])
            if hammingDistance(baseHash, targetHash) <= similarityPreset.rawValue {
                resultGroup.append(group[i])
            }
        }
        return resultGroup
    }

    // MARK: - pHash Helper Methods
    private func getOrGenerateHash(for asset: PHAsset) -> UInt64 {
        if let cached = hashCache[asset.localIdentifier] { return cached }
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        
        var generatedHash: UInt64 = 0
        manager.requestImage(for: asset, targetSize: CGSize(width: 16, height: 16), contentMode: .aspectFill, options: options) { image, _ in
            if let img = image { generatedHash = self.calculatePHash(img) }
        }
        hashCache[asset.localIdentifier] = generatedHash
        return generatedHash
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
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            DispatchQueue.main.async { completion(fetchResult.firstObject) }
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
            DispatchQueue.main.async { completion(success) }
        }
    }
    
    // MARK: - 앨범 목록 가져오기
    func fetchAlbums() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            print("[PhotoManager] 사진 라이브러리 권한 필요")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
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
            
            DispatchQueue.main.async {
                self.albums = albumList
                print("ZAKAR Log: 앨범 \(albumList.count)개 로드 완료")
            }
        }
    }
}

