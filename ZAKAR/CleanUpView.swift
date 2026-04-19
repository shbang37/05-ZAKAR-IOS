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
    @State private var hapticThresholdTriggered = false

    // Album quick-add state
    @State private var lastUsedAlbum: PHAssetCollection?
    @State private var showAlbumActionSheet = false
    @State private var draggedAlbum: PHAssetCollection?
    
    @State private var imageOpacity: Double = 1.0
    @State private var imageScale: CGFloat = 1.0
    
    // 줌 제스처 상태
    @State private var currentZoom: CGFloat = 1.0
    @State private var totalZoom: CGFloat = 1.0

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
            PremiumBackground(style: .deep)
            
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
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
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
                        .foregroundColor(isImportant ? AppTheme.gracefulGold : AppTheme.gracefulGold.opacity(0.5))
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
                        print("ZAKAR Log: CleanUpView - TrashBucketButton clicked, closing and opening trash")
                        // 1. 현재 창을 닫음
                        self.isPresented = false
                        
                        // 2. 부모 뷰(ContentView)에게 휴지통을 열라고 신호를 보냄
                        NotificationCenter.default.post(name: NSNotification.Name("OpenTrash"), object: nil)
                    }
                    .foregroundColor(.red)
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
                            .scaledToFit()
                            .frame(width: 340, height: 500)
                            .cornerRadius(20)
                            .overlay(
                                ZStack {
                                    // 드래그 방향에 따른 테두리 색상 변화
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                colors: [cardBorderColors.0, cardBorderColors.1],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                    
                                    // 휴지통 임계값 도달 아이콘 (카드 상단 오버레이)
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 46, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(18)
                                        .background(Circle().fill(Color.red.opacity(0.88)))
                                        .shadow(color: .red.opacity(0.7), radius: 16)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                        .padding(.top, 20)
                                        .opacity(isTrashThreshold ? 1.0 : 0.0)
                                        .scaleEffect(isTrashThreshold ? 1.0 : 0.5)
                                        .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isTrashThreshold)
                                    
                                    // 즐겨찾기 임계값 도달 아이콘 (카드 하단 오버레이)
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 46, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(18)
                                        .background(Circle().fill(AppTheme.gracefulGold.opacity(0.88)))
                                        .shadow(color: AppTheme.gracefulGold.opacity(0.7), radius: 16)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                        .padding(.bottom, 20)
                                        .opacity(isFavoriteThreshold ? 1.0 : 0.0)
                                        .scaleEffect(isFavoriteThreshold ? 1.0 : 0.5)
                                        .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isFavoriteThreshold)
                                }
                            )
                            .shadow(color: AppTheme.lightPurple.opacity(0.2), radius: 20)
                            .shadow(color: AppTheme.gracefulGold.opacity(0.15), radius: 15)
                            .opacity(imageOpacity)
                            .scaleEffect(imageScale * (isPullingDown ? 0.95 : 1.0) * currentZoom * totalZoom)
                            .offset(offset)                          // 손가락에 1:1 즉각 반응 (animation 없음)
                            .rotationEffect(.degrees(dragRotation))  // X 이동량 기반 자연스러운 기울기
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        currentZoom = value
                                    }
                                    .onEnded { value in
                                        totalZoom *= value
                                        currentZoom = 1.0
                                        totalZoom = min(max(totalZoom, 0.5), 3.0)
                                    }
                                    .simultaneously(with:
                                        DragGesture()
                                            .onChanged { gesture in
                                                let h = gesture.translation.width
                                                let v = gesture.translation.height

                                                // 가로/세로 축 고정 (기존 방식)
                                                // 수평 드래그 시 y 잠금, 수직 드래그 시 자유 이동
                                                if abs(v) > abs(h) {
                                                    offset = gesture.translation
                                                    isPullingDown = v > 0
                                                } else {
                                                    offset = CGSize(width: h, height: 0)
                                                    isPullingDown = false
                                                }

                                                // 휴지통 방향(위쪽/대각선 위)만 임계값 햅틱 유지
                                                let dist = sqrt(h * h + v * v)
                                                let reachedTrash = v < -100 || (h > 40 && v < -40 && dist > 80)
                                                if reachedTrash && !hapticThresholdTriggered {
                                                    hapticThresholdTriggered = true
                                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                } else if !reachedTrash {
                                                    hapticThresholdTriggered = false
                                                }
                                            }
                                            .onEnded(handleGesture)
                                    )
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
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.lightPurple.opacity(0.12)))
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
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.lightPurple.opacity(0.10)))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.lightPurple.opacity(0.3), lineWidth: 1))
                                }
                                .onDrag {
                                    // 드래그 시작
                                    self.draggedAlbum = album
                                    return NSItemProvider(object: album.localIdentifier as NSString)
                                }
                                .onDrop(of: [.text], delegate: AlbumDropDelegate(
                                    album: album,
                                    albums: $userAlbums,
                                    draggedAlbum: $draggedAlbum
                                ))
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
                    Task { @MainActor in
                        self.lastUsedAlbum = collection
                        if !self.userAlbums.contains(where: { $0.localIdentifier == collection.localIdentifier }) {
                            self.userAlbums.insert(collection, at: 0)
                        }
                    }
                    photoManager.addAssets([asset], toAlbum: collection) { success in
                        if success {
                            Task { @MainActor in self.changePhoto(next: true) }
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
            Task {
                try? await Task.sleep(nanoseconds: 50_000_000)
                print("ZAKAR Log: Starting initial image load after delay")
                self.loadImgWithPreview(at: self.currentIndex)
                self.preloadAdjacent(around: self.currentIndex)
                self.updateStarStatus()
                self.fetchUserAlbums()
                
                // 타임아웃 체크: 2초 후에도 이미지가 없으면 재시도
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.currentUIImage == nil {
                    print("ZAKAR Log: Image load timeout! Retrying...")
                    self.loadImgWithPreview(at: self.currentIndex)
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

    // MARK: - 드래그 피드백 계산

    /// X 이동량 기반 자연스러운 회전 (최대 ±20°)
    private var dragRotation: Double {
        let rotation = Double(offset.width) / 12.0
        return min(max(rotation, -20), 20)
    }

    /// 휴지통 방향 임계값 도달 여부 (위 또는 오른쪽 위 대각선)
    private var isTrashThreshold: Bool {
        let h = offset.width
        let v = offset.height
        let dist = sqrt(h * h + v * v)
        return v < -100 || (h > 40 && v < -40 && dist > 80)
    }

    /// 즐겨찾기 방향 임계값 도달 여부 (아래로)
    private var isFavoriteThreshold: Bool {
        offset.height > 100
    }

    /// 드래그 방향에 따른 카드 테두리 색상 (topLeading, bottomTrailing)
    private var cardBorderColors: (Color, Color) {
        let h = offset.width
        let v = offset.height
        let dist = sqrt(h * h + v * v)
        let progress = min(dist / 80.0, 1.0)
        // 위쪽 또는 오른쪽 위: 빨간색
        if v < -20 || (h > 15 && v < -15) {
            return (Color.red.opacity(0.15 + progress * 0.65),
                    Color.red.opacity(0.08 + progress * 0.32))
        }
        // 아래쪽: 초록색
        if v > 20 {
            return (Color.green.opacity(0.15 + progress * 0.65),
                    Color.green.opacity(0.08 + progress * 0.32))
        }
        // 중립
        return (AppTheme.gracefulGold.opacity(0.3), AppTheme.lightPurple.opacity(0.25))
    }

    // MARK: - 방향 힌트 아이콘 (카드 뒤 배경)
    private var guideIcons: some View {
        Group {
            // 위/오른쪽 위 방향 힌트
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.red)
                .opacity({
                    let h = offset.width
                    let v = offset.height
                    if isTrashThreshold { return 0.65 }
                    if v < -25 || (h > 15 && v < -15) { return 0.25 }
                    return 0
                }())
                .scaleEffect(isTrashThreshold ? 1.15 : 1.0)
                .shadow(color: .red.opacity(0.4), radius: 15)
                .offset(x: 140, y: -275)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isTrashThreshold)

            // 아래 방향 힌트
            Image(systemName: "star.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.goldenGradient)
                .opacity({
                    if isFavoriteThreshold { return 0.65 }
                    if offset.height > 25 { return 0.25 }
                    return 0
                }())
                .scaleEffect(isFavoriteThreshold ? 1.15 : 1.0)
                .shadow(color: AppTheme.gracefulGold.opacity(0.4), radius: 15)
                .offset(y: 260)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFavoriteThreshold)
        }
    }

    private func handleGesture(_ gesture: DragGesture.Value) {
        hapticThresholdTriggered = false

        let h = gesture.translation.width
        let v = gesture.translation.height

        // 휴지통(위쪽)만 predictedEnd 속도 반영
        let pH = gesture.predictedEndTranslation.width
        let pV = gesture.predictedEndTranslation.height
        let effectiveH = abs(pH) > abs(h) ? pH : h
        let effectiveV = abs(pV) > abs(v) ? pV : v
        let effectiveDist = sqrt(effectiveH * effectiveH + effectiveV * effectiveV)

        let isTrash = effectiveV < -100 || (effectiveH > 40 && effectiveV < -40 && effectiveDist > 80)

        if isTrash {
            flyToTrash()
        } else if v > 100 {
            // 아래로: 즐겨찾기 (기존 방식)
            toggleFavorite()
            resetPosition()
        } else if h < -80 && abs(v) < 60 {
            // 순수 좌측: 다음 사진 (기존 방식)
            changePhoto(next: true)
        } else if h > 80 && abs(v) < 60 {
            // 순수 우측: 이전 사진 (기존 방식)
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
        
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
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
            currentZoom = 1.0
            totalZoom = 1.0
        }
    }

    // MARK: - 제스처 확정 애니메이션

    /// 휴지통 확정: 오른쪽 위로 가속하며 사라짐 (easeIn = 가속감)
    private func flyToTrash() {
        guard photos.indices.contains(currentIndex) else { return }
        // 휴지통 확정 햅틱 (warning)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        withAnimation(.easeIn(duration: 0.28)) {
            offset = CGSize(width: 500, height: -700)
            imageOpacity = 0
        }

        Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            await MainActor.run {
                let asset = photos[currentIndex]
                if !trashAlbum.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                    print("ZAKAR Log: CleanUpView - Adding to trash, total count will be: \(trashAlbum.count + 1)")
                    trashAlbum.append(asset)
                } else {
                    print("ZAKAR Log: CleanUpView - Photo already in trash")
                }
                changePhoto(next: true)
            }
        }
    }

    /// 즐겨찾기 확정: 아래로 가속하며 사라졌다가 제자리에서 페이드인
    private func flyToFavorite() {
        guard photos.indices.contains(currentIndex) else { return }
        // 유지 확정 햅틱 (soft)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        withAnimation(.easeIn(duration: 0.22)) {
            offset = CGSize(width: 0, height: 700)
            imageOpacity = 0
        }

        Task {
            try? await Task.sleep(nanoseconds: 210_000_000)
            await MainActor.run {
                toggleFavorite()
                // 같은 사진 유지: 위치 리셋 후 fade in
                offset = .zero
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    imageOpacity = 1.0
                }
            }
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

        // 1단계: 고품질 프리뷰 (즉시 표시용)
        let previewOptions = PHImageRequestOptions()
        previewOptions.deliveryMode = .opportunistic  // 빠르지만 품질 좋은 이미지
        previewOptions.isNetworkAccessAllowed = true
        previewOptions.isSynchronous = false
        previewOptions.resizeMode = .exact  // 정확한 리사이징으로 품질 향상

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 340 * displayScale, height: 500 * displayScale),  // 표시 크기에 맞춤
            contentMode: .aspectFit,
            options: previewOptions
        ) { img, info in
            if let img = img {
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                print("ZAKAR Log: Preview callback - index \(index), isDegraded: \(isDegraded), size: \(img.size)")
                Task { @MainActor in
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
        hqOptions.resizeMode = .exact  // 정확한 리사이징으로 품질 향상

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
            Task { @MainActor in
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
            opts.deliveryMode = .opportunistic  // 품질 향상
            opts.resizeMode = .exact  // 정확한 리사이징
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
                    Task { @MainActor in self.imageCache[i] = img }
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
                Task { @MainActor in self.isImportant.toggle() }
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
                Task { @MainActor in
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
                Task { @MainActor in
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

// MARK: - 앨범 드래그 앤 드롭 Delegate
struct AlbumDropDelegate: DropDelegate {
    let album: PHAssetCollection
    @Binding var albums: [PHAssetCollection]
    @Binding var draggedAlbum: PHAssetCollection?
    
    func performDrop(info: DropInfo) -> Bool {
        draggedAlbum = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedAlbum = draggedAlbum,
              draggedAlbum.localIdentifier != album.localIdentifier,
              let from = albums.firstIndex(where: { $0.localIdentifier == draggedAlbum.localIdentifier }),
              let to = albums.firstIndex(where: { $0.localIdentifier == album.localIdentifier })
        else { return }
        
        withAnimation {
            albums.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
}
