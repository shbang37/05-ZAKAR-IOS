import SwiftUI
import Photos
import UIKit

private enum DragIntent { case undecided, horizontal, vertical, trash }

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
    @State private var dragIntent: DragIntent = .undecided

    // 다음 카드 뒤에서 나타나기 애니메이션용
    @State private var nextCardUIImage: UIImage? = nil
    @State private var nextCardVisible: Bool = false
    @State private var nextCardScale: CGFloat = 0.88
    @State private var nextCardOpacity: Double = 0.6

    // Album quick-add state
    @State private var lastUsedAlbum: PHAssetCollection?
    @State private var showAlbumActionSheet = false
    @State private var draggedAlbum: PHAssetCollection?
    
    @State private var imageOpacity: Double = 1.0
    @State private var imageScale: CGFloat = 1.0
    // 휴지통 방향 진행도: 0.0(원위치) → 1.0(임계 거리 도달)
    // 드래그 중 테두리 색·회전·축소·버튼 반응의 강도를 결정
    @State private var trashProgress: CGFloat = 0.0
    // 릴리즈 시 카드가 날아갈 목적지 계산용 (global 좌표)
    @State private var trashButtonCenter: CGPoint = .zero
    @State private var cardRestCenter: CGPoint = .zero
    
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
                    // 카드가 날아갈 목적지 좌표 캡처
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    let f = geo.frame(in: .global)
                                    trashButtonCenter = CGPoint(x: f.midX, y: f.midY)
                                }
                        }
                    )
                    // 휴지통 방향 드래그 중 "받을 준비" 반응: 진행도에 따라 커짐
                    .scaleEffect(isTrashThreshold ? 1.22 : (dragIntent == .trash ? 1.0 + trashProgress * 0.12 : 1.0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isTrashThreshold)
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer()
                
                // 2. 메인 사진 카드 영역
                ZStack {
                    guideIcons

                    // 다음 카드 (현재 카드 뒤에서 나타나는 애니메이션용)
                    if nextCardVisible, let nextImg = nextCardUIImage {
                        Image(uiImage: nextImg)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 340, height: 500)
                            .cornerRadius(20)
                            .scaleEffect(nextCardScale)
                            .opacity(nextCardOpacity)
                            .shadow(color: AppTheme.lightPurple.opacity(0.15), radius: 15)
                    }

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
                            .scaleEffect(cardScaleEffect)            // 진행도에 따라 살짝 축소
                            .offset(offset)                          // 손가락 1:1 추적
                            .rotationEffect(.degrees(dragRotation))  // 던지는 듯한 시계방향 기울기
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
                                                let dist = sqrt(h * h + v * v)

                                                // 30pt 데드존: 방향 확정 전까지 카드 미동
                                                if dragIntent == .undecided {
                                                    guard dist > 30 else { return }
                                                    if v < -20 {
                                                        dragIntent = .trash      // 위쪽 → 휴지통
                                                    } else if abs(h) > abs(v) {
                                                        dragIntent = .horizontal
                                                    } else if v > 0 {
                                                        dragIntent = .vertical
                                                    } else {
                                                        dragIntent = .trash
                                                    }
                                                }

                                                // 의도 확정 후 축 고정 + 65% 댐핑 적용
                                                switch dragIntent {
                                                case .horizontal:
                                                    offset = CGSize(width: h * 0.65, height: 0)
                                                    isPullingDown = false
                                                case .vertical:
                                                    let down = max(0, v)
                                                    offset = CGSize(width: 0, height: down * 0.65)
                                                    isPullingDown = down > 0
                                                case .trash:
                                                    // 손가락 1:1 추적 — 카드가 손을 그대로 따라옴
                                                    offset = CGSize(width: h, height: v)
                                                    // 위쪽+오른쪽 성분으로 진행도 계산 (회전·축소·색상·버튼 반응용)
                                                    let upward    = max(0, -v)
                                                    let rightward = max(0, h) * 0.4
                                                    trashProgress = min((upward + rightward) / 200.0, 1.0)
                                                    isPullingDown = false
                                                case .undecided:
                                                    break
                                                }

                                                // 진행도 55% 도달 시 임계값 햅틱 (1회만)
                                                if trashProgress > 0.55 && !hapticThresholdTriggered {
                                                    hapticThresholdTriggered = true
                                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                } else if trashProgress <= 0.55 {
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
                // 카드 원위치 중심 캡처 (offset/scale은 렌더 변환이라 layout frame은 고정)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                let f = geo.frame(in: .global)
                                cardRestCenter = CGPoint(x: f.midX, y: f.midY)
                            }
                    }
                )
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

    /// 릴리즈 시 카드가 날아갈 목적지: 실제 헤더 휴지통 버튼 중심
    /// (좌표 캡처 전이면 우상단 근사값으로 폴백)
    private var flyTargetOffset: CGSize {
        guard trashButtonCenter != .zero, cardRestCenter != .zero else {
            return CGSize(width: 150, height: -330)
        }
        return CGSize(width: trashButtonCenter.x - cardRestCenter.x,
                      height: trashButtonCenter.y - cardRestCenter.y)
    }

    /// 현재 카드의 실제 스케일
    /// 드래그 중엔 진행도에 따라 살짝만 축소(들어올린 느낌), 흡입 애니메이션은 imageScale이 담당
    private var cardScaleEffect: CGFloat {
        let trashShrink: CGFloat = 1.0 - trashProgress * 0.12
        return imageScale * trashShrink * (isPullingDown ? 0.95 : 1.0) * currentZoom * totalZoom
    }

    /// 휴지통 방향 진행 시 던지는 듯한 시계방향 기울기
    private var dragRotation: Double {
        guard trashProgress > 0 else { return 0 }
        return Double(trashProgress) * 14.0
    }

    /// 진행도 55% 이상이면 휴지통 임계값 도달
    private var isTrashThreshold: Bool {
        trashProgress > 0.55
    }

    /// 즐겨찾기 방향 임계값 도달 여부 (수직 의도 확정 후에만)
    private var isFavoriteThreshold: Bool {
        dragIntent == .vertical && offset.height > 100
    }

    /// 드래그 의도에 따른 카드 테두리 색상 (topLeading, bottomTrailing)
    private var cardBorderColors: (Color, Color) {
        if trashProgress > 0 {
            return (Color.red.opacity(0.15 + trashProgress * 0.65),
                    Color.red.opacity(0.08 + trashProgress * 0.32))
        }
        let v = offset.height
        let dist = sqrt(offset.width * offset.width + v * v)
        let progress = min(dist / 80.0, 1.0)
        if dragIntent == .vertical && v > 20 {
            return (Color.green.opacity(0.15 + progress * 0.65),
                    Color.green.opacity(0.08 + progress * 0.32))
        }
        return (AppTheme.gracefulGold.opacity(0.3), AppTheme.lightPurple.opacity(0.25))
    }

    // MARK: - 방향 힌트 아이콘 (카드 뒤 배경)
    // 휴지통 힌트는 실제 헤더 버튼이 진행도에 반응하므로 별도 아이콘 없음
    private var guideIcons: some View {
        Group {
            // 아래 방향 힌트
            Image(systemName: "star.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.goldenGradient)
                .opacity({
                    if isFavoriteThreshold { return 0.65 }
                    if dragIntent == .vertical && offset.height > 25 { return 0.25 }
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
        let intent = dragIntent
        dragIntent = .undecided

        let h = gesture.translation.width
        let v = gesture.translation.height

        switch intent {
        case .trash:
            // 느린 드래그: trashProgress 기반 확정
            // 빠른 플릭: predictedEnd로 추정 progress 계산 후 max 적용
            let pUp    = max(0, -gesture.predictedEndTranslation.height)
            let pRight = max(0, gesture.predictedEndTranslation.width) * 0.4
            let predictedProgress = min((pUp + pRight) / 200.0, 1.0)
            let effectiveProgress = max(trashProgress, predictedProgress)

            if effectiveProgress > 0.42 {
                flyToTrash(velocity: gesture.velocity)
            } else {
                resetPosition()
            }

        case .horizontal:
            // 좌/우: 정확한 수평 임계값 판단
            if h < -80 {
                changePhoto(next: true)
            } else if h > 80 {
                changePhoto(next: false)
            } else {
                resetPosition()
            }

        case .vertical:
            // 아래: 즐겨찾기 임계값 판단
            if v > 100 {
                toggleFavorite()
                resetPosition()
            } else {
                resetPosition()
            }

        case .undecided:
            resetPosition()
        }
    }

    // ... [중략: changePhoto, resetPosition, loadImg, updateStarStatus, formatDate 로직은 동일] ...
    
    private func changePhoto(next: Bool) {
        // 다음 인덱스 계산
        let nextIndex: Int
        if next {
            guard currentIndex < photos.count - 1 else {
                if let onFinish = onFinishGroup { onFinish() } else { isPresented = false }
                return
            }
            nextIndex = currentIndex + 1
        } else {
            guard currentIndex > 0 else { return }
            nextIndex = currentIndex - 1
        }

        // 캐시에 다음 사진이 있으면 뒤에서 나타나는 카드로 미리 표시
        if let cached = imageCache[nextIndex] {
            nextCardUIImage = cached
            nextCardScale = 0.88
            nextCardOpacity = 0.6
            nextCardVisible = true
        }

        // 현재 카드 퇴장 + 뒤 카드 등장 동시 애니메이션
        withAnimation(.easeIn(duration: 0.18)) {
            imageOpacity = 0.0
            imageScale = 0.85
            if nextCardVisible {
                nextCardScale = 1.0
                nextCardOpacity = 1.0
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                currentIndex = nextIndex

                if let cached = imageCache[currentIndex] {
                    currentUIImage = cached
                } else {
                    currentUIImage = nil
                    loadImgWithPreview(at: currentIndex)
                }
                preloadAdjacent(around: currentIndex)
                updateStarStatus()

                // 다음 카드 오버레이 해제
                nextCardVisible = false
                nextCardUIImage = nil
                nextCardScale = 0.88
                nextCardOpacity = 0.6

                // 위치/의도 리셋 (애니메이션 없이 즉시)
                offset = .zero
                isPullingDown = false
                dragIntent = .undecided
                currentZoom = 1.0
                totalZoom = 1.0

                if currentUIImage != nil {
                    // 캐시 히트: 오버레이 카드가 이미 등장 애니메이션을 마치고 완전히 보이는 상태.
                    // 메인 카드가 opacity 0에서 다시 페이드인하면 같은 사진이
                    // "나타남→꺼짐→재등장"으로 깜빡이므로, 그대로 이어받는다.
                    imageOpacity = 1.0
                    imageScale = 1.0
                } else {
                    // 로딩 대기: 빈 상태로 페이드인하지 않고,
                    // 이미지 도착 시점에 loadImgWithPreview가 등장 애니메이션을 실행
                    imageOpacity = 0.0
                    imageScale = 0.88
                }
            }
        }
    }

    private func resetPosition() {
        dragIntent = .undecided
        // trashProgress → 0 도 spring으로 부드럽게 복귀 (포물선 역방향)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            trashProgress = 0.0
            offset = .zero
            isPullingDown = false
            currentZoom = 1.0
            totalZoom = 1.0
        }
    }

    // MARK: - 제스처 확정 애니메이션

    /// 휴지통 확정: 손을 뗀 지점에서 플릭 속도를 이어받아
    /// 실제 헤더 휴지통 버튼으로 빨려 들어가며 축소
    private func flyToTrash(velocity: CGSize = .zero) {
        guard photos.indices.contains(currentIndex) else { return }
        // 릴리즈 순간: 가벼운 시작 햅틱
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let target = flyTargetOffset

        // 손을 뗀 순간의 플릭 속도를 목적지 방향 성분으로 투영해
        // 스프링 초기 속도로 전달 → 던진 기세 그대로 날아감
        let dx = target.width - offset.width
        let dy = target.height - offset.height
        let distance = max(sqrt(dx * dx + dy * dy), 1)
        let velocityAlongPath = max(0, (velocity.width * dx + velocity.height * dy) / distance)
        // interpolatingSpring의 initialVelocity는 (초당 이동량 / 전체 거리) 정규화 단위
        let initialVelocity = min(velocityAlongPath / distance, 10)

        withAnimation(.interpolatingSpring(stiffness: 240, damping: 26, initialVelocity: initialVelocity)) {
            offset = target
            trashProgress = 1.0
            imageScale = 0.05
        }
        // 이동 후반부에 페이드아웃 (버튼 안으로 사라지는 느낌)
        withAnimation(.easeIn(duration: 0.15).delay(0.18)) {
            imageOpacity = 0
        }

        Task {
            try? await Task.sleep(nanoseconds: 340_000_000)
            await MainActor.run {
                // 도착 순간: 묵직한 햅틱 + trashAlbum 증가로 버튼 팝 애니메이션 발동
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                let asset = photos[currentIndex]
                if !trashAlbum.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                    print("ZAKAR Log: CleanUpView - Adding to trash, total count will be: \(trashAlbum.count + 1)")
                    trashAlbum.append(asset)
                } else {
                    print("ZAKAR Log: CleanUpView - Photo already in trash")
                }
                // 상태 초기화 후 다음 사진으로
                trashProgress = 0.0
                imageScale = 1.0
                offset = .zero
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
            if index == currentIndex {
                currentUIImage = cached
                if imageOpacity == 0 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        imageOpacity = 1.0
                        imageScale = 1.0
                    }
                }
            }
            return
        }
        
        print("ZAKAR Log: loadImgWithPreview - Requesting image for index \(index)")

        // opportunistic 한 번으로 저화질 프리뷰 → 최종 고화질까지 순차 배달됨.
        // (기존에는 같은 크기로 highQualityFormat을 한 번 더 요청해 화면 교체가
        //  한 번 더 일어났음 — 중복 요청 제거)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact  // 정확한 리사이징으로 품질 향상

        let reqID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 340 * displayScale, height: 500 * displayScale),  // 표시 크기에 맞춤
            contentMode: .aspectFit,
            options: options
        ) { img, info in
            if let img = img {
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                print("ZAKAR Log: Preview callback - index \(index), isDegraded: \(isDegraded), size: \(img.size)")
                Task { @MainActor in
                    if index == self.currentIndex {
                        // 저화질은 빈 화면일 때만 채우고, 최종본은 항상 반영
                        if self.currentUIImage == nil || !isDegraded {
                            self.currentUIImage = img
                        }
                        // 로딩을 기다리던 카드: 이미지가 도착한 시점에 등장 애니메이션
                        // (advanceToNext가 opacity 0으로 대기시켜 둠)
                        if self.imageOpacity == 0, self.currentUIImage != nil {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                self.imageOpacity = 1.0
                                self.imageScale = 1.0
                            }
                        }
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
        let exportedURL: URL? = await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, uti, _, info in
                guard let data = data else { cont.resume(returning: nil); return }
                let original = (info?["PHImageFileURLKey"] as? URL)?.lastPathComponent ?? "photo.jpg"
                let fileName = self.buildFileName(original: original, albumName: self.lastUsedAlbum?.localizedTitle, createdAt: asset.creationDate)
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try data.write(to: tmpURL, options: .atomic)
                    cont.resume(returning: tmpURL)
                } catch {
                    print("Export write error: \(error)")
                    cont.resume(returning: nil)
                }
            }
        }
        // @State writes must happen on the main actor; after await we're back on the caller's context
        if let url = exportedURL {
            self.shareItems = [url]
            self.showShareSheet = true
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
