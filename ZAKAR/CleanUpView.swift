import SwiftUI
import Photos
import UIKit

struct CleanUpView: View {
    let photos: [PHAsset]
    let startIndex: Int
    @Binding var isPresented: Bool
    
    // [수정] UIImage 대신 PHAsset을 바인딩으로 받습니다.
    @Binding var trashAlbum: [PHAsset]
    let photoManager: PhotoManager
    var onFinishGroup: (() -> Void)? = nil
    
    @State private var currentIndex: Int
    @State private var currentUIImage: UIImage?
    @State private var offset: CGSize = .zero
    @State private var isImportant: Bool = false
    @State private var isPullingDown: Bool = false

    // Album quick-add state
    @State private var lastUsedAlbum: PHAssetCollection?
    @State private var showAlbumActionSheet = false
    
    @State private var imageOpacity: Double = 1.0
    @State private var imageScale: CGFloat = 1.0

    // 인접 사진 프리로드 캐시: key=index, value=UIImage
    @State private var imageCache: [Int: UIImage] = [:]
    // 현재 진행 중인 이미지 요청 ID (중복 요청 취소용)
    @State private var currentRequestID: PHImageRequestID?

    @Environment(\.displayScale) var displayScale

    // MARK: - Share Sheet State
    @State private var showAddToAlbumAlert = false
    @State private var tempAlbumName: String = ""
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    
    @State private var userAlbums: [PHAssetCollection] = []

    // [수정] init 메서드의 trashAlbum 타입 변경
    init(photos: [PHAsset], startIndex: Int, isPresented: Binding<Bool>, trashAlbum: Binding<[PHAsset]>, photoManager: PhotoManager, onFinishGroup: (() -> Void)? = nil) {
        self.photos = photos
        self.startIndex = startIndex
        self._isPresented = isPresented
        self._trashAlbum = trashAlbum
        self.photoManager = photoManager
        self.onFinishGroup = onFinishGroup
        self._currentIndex = State(initialValue: photos.indices.contains(startIndex) ? startIndex : 0)
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()
            
            // 사진이 없는 경우 자동 재시도
            if photos.isEmpty {
                VStack(spacing: 20) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("사진 불러오는 중...")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }
                .onAppear {
                    // 0.5초 후 자동으로 닫기 (상위 View에서 재시도하도록)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("ZAKAR Log: CleanUpView - photos empty, auto-closing for retry")
                        isPresented = false
                    }
                }
            } else {
            
            VStack {
                // 1. 상단 정보 헤더
                HStack(alignment: .center) {
                    Button("닫기") { isPresented = false }
                        .foregroundColor(.white)
                        .bold()
                        .frame(width: 60, alignment: .leading)
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        if photos.indices.contains(currentIndex), let date = photos[currentIndex].creationDate {
                            Text(formatDate(date))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Text("\(currentIndex + 1) / \(photos.count)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }
                    
                    Spacer()
                    
                    Image(systemName: isImportant ? "star.fill" : "star")
                        .foregroundStyle(isImportant ? AppTheme.goldenGradient : LinearGradient(colors: [AppTheme.gracefulGold.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                        .font(.headline)
                        .frame(width: 30)
                        .shadow(color: isImportant ? AppTheme.gracefulGold.opacity(0.5) : .clear, radius: 8)

                    Button {
                        Task { await exportCurrentPhotoForSharing() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .padding(.horizontal, 6)
                    
                    // 상단 헤더의 가장 오른쪽에 배치
                    TrashBucketButton(count: trashAlbum.count) {
                        // 1. 현재 창을 닫음
                        self.isPresented = false
                        
                        // 2. 부모 뷰(ContentView)에게 휴지통을 열라고 신호를 보냄
                        // (이 기능을 위해 ContentView에 Notification 혹은 별도 바인딩 연결이 필요할 수 있습니다.)
                        NotificationCenter.default.post(name: NSNotification.Name("OpenTrash"), object: nil)
                    }
                    .foregroundColor(.red)
                    .contentShape(Rectangle()) // 터치 영역 확보
                    .onTapGesture {
                        // 현재 CleanUpView를 닫으면서 휴지통을 열도록 처리
                        self.isPresented = false
                        // 부모 뷰의 showTrashView를 트리거하는 로직이 필요할 수 있습니다.
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer()
                
                // 2. 메인 사진 카드 영역
                ZStack {
                    guideIcons
                    
                    if let image = currentUIImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 340, height: 500)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                AppTheme.gracefulGold.opacity(0.3),
                                                AppTheme.dawnPurple.opacity(0.25)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: AppTheme.dawnPurple.opacity(0.2), radius: 20)
                            .shadow(color: AppTheme.gracefulGold.opacity(0.15), radius: 15)
                            .opacity(imageOpacity)
                            .scaleEffect(imageScale * (isPullingDown ? 0.95 : 1.0))
                            .offset(y: offset.height)
                            .offset(x: offset.height < 0 ? abs(offset.height) * 0.5 : 0)
                            .rotationEffect(.degrees(offset.height < 0 ? Double(abs(offset.height) / 15) : 0))
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        let h = gesture.translation.width
                                        let v = gesture.translation.height
                                        
                                        if abs(v) > abs(h) {
                                            offset = gesture.translation
                                            isPullingDown = v > 0
                                        } else {
                                            offset = CGSize(width: h, height: 0)
                                        }
                                    }
                                    .onEnded(handleGesture)
                            )
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                Spacer()
            }
            // Bottom album controls
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        presentAddToAlbumPrompt()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.dualGradient)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.dawnPurple.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.gracefulGold.opacity(0.25), lineWidth: 1))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(userAlbums, id: \.localIdentifier) { album in
                                Button {
                                    addCurrentPhoto(to: album)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(AppTheme.purpleGradient)
                                        Text(album.localizedTitle ?? "앨범")
                                            .lineLimit(1)
                                            .foregroundColor(.white)
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.dawnPurple.opacity(0.10)))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.dawnPurple.opacity(0.3), lineWidth: 1))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            } // else (photos not empty)
        }
        .alert("앨범에 추가", isPresented: $showAddToAlbumAlert) {
            TextField("앨범 이름", text: $tempAlbumName)
            Button("취소", role: .cancel) {}
            Button("추가") {
                let name = tempAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, photos.indices.contains(currentIndex) else { return }
                let asset = photos[currentIndex]
                photoManager.fetchOrCreateAlbum(named: name) { collection in
                    guard let collection = collection else { return }
                    DispatchQueue.main.async {
                        self.lastUsedAlbum = collection
                        if !self.userAlbums.contains(where: { $0.localIdentifier == collection.localIdentifier }) {
                            self.userAlbums.insert(collection, at: 0)
                        }
                    }
                    photoManager.addAssets([asset], toAlbum: collection) { success in
                        if success {
                            DispatchQueue.main.async { self.changePhoto(next: true) }
                        }
                    }
                }
            }
        } message: {
            Text("앨범명을 입력하세요")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .onAppear {
            print("ZAKAR Log: CleanUpView onAppear - currentIndex: \(currentIndex), photos.count: \(photos.count)")
            
            // 약간의 지연 후 이미지 로드 (SwiftUI 초기화 대기)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                print("ZAKAR Log: Starting initial image load after delay")
                self.loadImgWithPreview(at: self.currentIndex)
                self.preloadAdjacent(around: self.currentIndex)
                self.updateStarStatus()
                self.fetchUserAlbums()
                
                // 타임아웃 체크: 2초 후에도 이미지가 없으면 재시도
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.currentUIImage == nil {
                        print("ZAKAR Log: Image load timeout! Retrying...")
                        self.loadImgWithPreview(at: self.currentIndex)
                    }
                }
            }
        }
        .onChange(of: currentIndex) { _, newIndex in
            print("ZAKAR Log: currentIndex changed to \(newIndex)")
            // 인덱스가 변경될 때도 동일한 로직 적용
            if imageCache[newIndex] == nil && currentUIImage == nil {
                loadImgWithPreview(at: newIndex)
                preloadAdjacent(around: newIndex)
            }
            updateStarStatus()
        }
    } // body

    private var guideIcons: some View {
        Group {
            Image(systemName: "trash.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
                .opacity(offset.height < -60 ? 0.8 : 0)
                .shadow(color: .red.opacity(0.6), radius: 20)
                .offset(x: 140, y: -280)
            
            Image(systemName: "star.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.goldenGradient)
                .opacity(offset.height > 60 ? 0.8 : 0)
                .shadow(color: AppTheme.gracefulGold.opacity(0.6), radius: 20)
                .offset(y: 260)
        }
    }

    private func handleGesture(_ gesture: DragGesture.Value) {
        let h = gesture.translation.width
        let v = gesture.translation.height
        
        if v < -120 {
            // [수정] 1시 방향으로 던질 때 UIImage가 아닌 현재 PHAsset을 추가합니다.
            let currentAsset = photos[currentIndex]
            if !trashAlbum.contains(where: { $0.localIdentifier == currentAsset.localIdentifier }) {
                withAnimation { trashAlbum.append(currentAsset) }
            }
            changePhoto(next: true)
        } else if v > 100 {
            toggleFavorite()
            resetPosition()
        } else if h < -80 {
            changePhoto(next: true)
        } else if h > 80 {
            changePhoto(next: false)
        } else {
            resetPosition()
        }
    }

    // ... [중략: changePhoto, resetPosition, loadImg, updateStarStatus, formatDate 로직은 동일] ...
    
    private func changePhoto(next: Bool) {
        withAnimation(.easeIn(duration: 0.15)) {
            imageOpacity = 0.0
            imageScale = 0.8
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if next {
                if currentIndex < photos.count - 1 { 
                    currentIndex += 1 
                } else { 
                    // 마지막 사진 도달: 다음 그룹으로 이동
                    if let onFinish = onFinishGroup {
                        onFinish()
                    } else {
                        isPresented = false
                    }
                    return 
                }
            } else {
                if currentIndex > 0 { currentIndex -= 1 }
            }

            // 캐시에 있으면 즉시 표시, 없으면 프리뷰부터 로드
            if let cached = imageCache[currentIndex] {
                currentUIImage = cached
            } else {
                currentUIImage = nil
                loadImgWithPreview(at: currentIndex)
            }

            // 다음 인접 사진 프리로드
            preloadAdjacent(around: currentIndex)
            updateStarStatus()
            resetPosition()

            imageOpacity = 0.0
            imageScale = 0.9
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                imageOpacity = 1.0
                imageScale = 1.0
            }
        }
    }

    private func resetPosition() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            offset = .zero
            isPullingDown = false
        }
    }

    // MARK: - 이미지 로딩 (2단계: 저해상도 즉시 → 고해상도 교체)

    /// 현재 인덱스 사진을 로드합니다.
    /// 1단계: 썸네일(400px) 즉시 표시 → 2단계: 전체 해상도로 교체
    private func loadImgWithPreview(at index: Int) {
        guard photos.indices.contains(index) else { 
            print("ZAKAR Log: loadImgWithPreview - index \(index) out of range")
            return 
        }
        let asset = photos[index]
        print("ZAKAR Log: loadImgWithPreview - Loading index \(index), localIdentifier: \(asset.localIdentifier)")

        // 캐시 히트 시 즉시 반환
        if let cached = imageCache[index] {
            print("ZAKAR Log: loadImgWithPreview - Cache hit for index \(index)")
            if index == currentIndex { currentUIImage = cached }
            return
        }
        
        print("ZAKAR Log: loadImgWithPreview - Requesting image for index \(index)")

        // 1단계: 빠른 저해상도 썸네일 (즉시 표시용, ~400px)
        let previewOptions = PHImageRequestOptions()
        previewOptions.deliveryMode = .fastFormat
        previewOptions.isNetworkAccessAllowed = true
        previewOptions.isSynchronous = false
        previewOptions.resizeMode = .fast  // 빠른 리사이징

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 400, height: 400),
            contentMode: .aspectFit,
            options: previewOptions
        ) { img, info in
            if let img = img {
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                print("ZAKAR Log: Preview callback - index \(index), isDegraded: \(isDegraded), size: \(img.size)")
                DispatchQueue.main.async {
                    // 아직 고해상도가 없을 때만 저해상도로 채움
                    if index == self.currentIndex, self.currentUIImage == nil {
                        print("ZAKAR Log: Setting currentUIImage from preview - index \(index)")
                        self.currentUIImage = img
                    }
                    // 최종본(isDegraded=false)이면 캐시에 저장
                    if !isDegraded {
                        self.imageCache[index] = img
                    }
                }
            } else {
                print("ZAKAR Log: Preview callback - index \(index), img is nil, info: \(String(describing: info))")
            }
        }

        // 2단계: 표시 크기에 맞는 고해상도 (카드 340pt × 500pt 기준)
        let hqOptions = PHImageRequestOptions()
        hqOptions.deliveryMode = .highQualityFormat  // opportunistic → highQualityFormat
        hqOptions.isNetworkAccessAllowed = true
        hqOptions.isSynchronous = false
        hqOptions.resizeMode = .fast

        // 카드 크기에 맞는 적절한 해상도 (전체 화면 원본 불필요)
        let scale = displayScale
        let targetSize = CGSize(width: 340 * scale, height: 500 * scale)

        let reqID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: hqOptions
        ) { img, info in
            guard let img else { return }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            DispatchQueue.main.async {
                // 현재 보고 있는 인덱스일 때만 UI 업데이트
                if index == self.currentIndex {
                    self.currentUIImage = img
                }
                if !isDegraded {
                    self.imageCache[index] = img
                }
            }
        }

        if index == currentIndex { currentRequestID = reqID }
    }

    /// 현재 인덱스 앞뒤 각 2장을 미리 캐시에 로드합니다.
    private func preloadAdjacent(around index: Int) {
        // 앞 2장, 뒤 2장
        let targets = [index - 2, index - 1, index + 1, index + 2]
        for i in targets where photos.indices.contains(i) && imageCache[i] == nil {
            let asset = photos[i]
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 340 * displayScale, height: 500 * displayScale),
                contentMode: .aspectFit,
                options: opts
            ) { img, info in
                guard let img else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    DispatchQueue.main.async { self.imageCache[i] = img }
                }
            }
        }
    }
    
    private func updateStarStatus() {
        if photos.indices.contains(currentIndex) {
            isImportant = photos[currentIndex].isFavorite
        }
    }

    private func toggleFavorite() {
        let asset = photos[currentIndex]
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = !asset.isFavorite
        }) { success, _ in
            if success {
                DispatchQueue.main.async { self.isImportant.toggle() }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 MM월 dd일"
        return formatter.string(from: date)
    }
    
    // MARK: - Add to Album Flow

    private func presentAddToAlbumPrompt() {
        tempAlbumName = ""
        showAddToAlbumAlert = true
    }
    
    private func addCurrentPhotoToLastAlbum() {
        guard let album = lastUsedAlbum, photos.indices.contains(currentIndex) else { return }
        let asset = photos[currentIndex]
        photoManager.addAssets([asset], toAlbum: album) { success in
            if success {
                DispatchQueue.main.async {
                    self.changePhoto(next: true)
                }
            }
        }
    }
    
    private func fetchUserAlbums() {
        var result: [PHAssetCollection] = []
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        collections.enumerateObjects { collection, _, _ in
            result.append(collection)
        }
        self.userAlbums = result
    }
    
    private func addCurrentPhoto(to album: PHAssetCollection) {
        guard photos.indices.contains(currentIndex) else { return }
        let asset = photos[currentIndex]
        photoManager.addAssets([asset], toAlbum: album) { success in
            if success {
                DispatchQueue.main.async {
                    self.lastUsedAlbum = album
                    self.changePhoto(next: true)
                }
            }
        }
    }
    
    // MARK: - Share Sheet Helpers

    private func buildFileName(original: String, albumName: String?, createdAt: Date?) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
        let stamp = (createdAt != nil) ? df.string(from: createdAt!) : df.string(from: Date())
        let base = (original as NSString).deletingPathExtension
        let ext = ((original as NSString).pathExtension.isEmpty ? "jpg" : (original as NSString).pathExtension)
        let album = (lastUsedAlbum?.localizedTitle ?? "Album").replacingOccurrences(of: " ", with: "_")
        return "\(album)_\(stamp)_\(base).\(ext)"
    }

    private func exportCurrentPhotoForSharing() async {
        guard photos.indices.contains(currentIndex) else { return }
        let asset = photos[currentIndex]
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, uti, _, info in
                defer { cont.resume() }
                guard let data = data else { return }
                let original = (info?["PHImageFileURLKey"] as? URL)?.lastPathComponent ?? "photo.jpg"
                let fileName = buildFileName(original: original, albumName: lastUsedAlbum?.localizedTitle, createdAt: asset.creationDate)
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try data.write(to: tmpURL, options: .atomic)
                    self.shareItems = [tmpURL]
                    self.showShareSheet = true
                } catch {
                    print("Export write error: \(error)")
                }
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
