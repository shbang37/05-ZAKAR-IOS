import SwiftUI
import Photos

struct HomeView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var metadata: AppMetadata = LocalDB.shared.loadMetadata()

    var body: some View {
        NavigationStack {
            ZStack {
                // Premium warm background
                PremiumBackground(style: .warm)

                ScrollView {
                    VStack(spacing: 18) {
                        headerSection

                        summarySection
                            .padding(.horizontal)

                        recentPhotoSection
                            .padding(.horizontal)

                        navigationSections
                        
                        monthlyCleanupSection
                            .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("홈")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.pureWhite)
                }
            }
            // NavigationStack 내부 콘텐츠에 onAppear을 붙여야
            // NavigationLink 자식 뷰에서 뒤로 돌아왔을 때도 호출됨
            .onAppear {
                print("ZAKAR Log: HomeView - onAppear, resetting filters and reloading all photos")
                
                // 1. 필터 상태 및 캐시 명시적 초기화
                photoManager.resetAnalysisState()
                
                // 2. 전체 사진 로드 (필터 없음) - 필터된 뷰에서 복귀 시에도 올바르게 전체 로드
                photoManager.fetchPhotos(year: nil, month: nil)
                
                // 3. 메타데이터 로드
                metadata = LocalDB.shared.loadMetadata()
                
                // 4. 휴지통 동기화: PhotoManager 공유 상태 갱신
                photoManager.loadTrash()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sub Views
    
    // 1. 상단 로고 및 타이틀 분리 (은혜의 새벽 테마)
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(AppTheme.goldenPurpleGradient, lineWidth: 3)
                )
                .shadow(color: AppTheme.goldenRoseShadow(opacity: 0.3), radius: 15, x: 0, y: 5)
                .shadow(color: AppTheme.goldenShadow(opacity: 0.2), radius: 10, x: 0, y: 0)
                .accessibilityLabel("ZAKAR 로고")

            Text("ZAKAR")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.goldenPurpleGradient)

            Text("모든 은혜를 기억합니다")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.pureWhite.opacity(0.85))
        }
        .padding(.top, 12)
    }

    // 2. 요약 카드 섹션 분리
    private var summarySection: some View {
        HomeSummaryCard(
            groupsCount: photoManager.groupedPhotos.count,
            lastCleanupDate: metadata.lastCleanupDate,
            estimatedSavedMB: metadata.estimatedSavedMB
        )
    }

    // 3. 최근 사진 섹션
    private var recentPhotoSection: some View {
        RecentPhotoCard(photoManager: photoManager)
    }

    // 4. 주요 네비게이션 링크 섹션 분리
    private var navigationSections: some View {
        Group {
            NavigationLink(destination: ContentView(initialTab: 1)) {
                GlassSectionCard(
                    title: "모든 사진",
                    subtitle: "필요 없는 사진을 손쉽게 정리",
                    icon: "photo.stack",
                    count: photoManager.allPhotos.count,
                    isLoading: photoManager.isLoadingList
                )
            }

            NavigationLink(destination: ContentView(initialTab: 0).id(UUID())) {
                GlassSectionCard(
                    title: "유사 사진",
                    subtitle: "비슷한 사진들을 모아서 빠르게 확인",
                    icon: "square.on.square.dashed",
                    count: photoManager.groupedPhotos.reduce(0) { $0 + $1.count },
                    isLoading: photoManager.isAnalyzing
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
    
    // 5. 월별 정리 섹션
    private var monthlyCleanupSection: some View {
        MonthlyCleanupSection(photoManager: photoManager)
    }
}

// MARK: - 최근 사진 카드
private struct RecentPhotoCard: View {
    @ObservedObject var photoManager: PhotoManager
    @State private var recentPhoto: PHAsset?
    @State private var thumbnail: UIImage?
    @State private var showCleanUpView = false
    @State private var showTrashView = false
    @State private var isLoading = false
    
    var body: some View {
        Button {
            if recentPhoto != nil {
                showCleanUpView = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // 헤더
                HStack {
                    Text("최근 사진")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.dualGradient)
                }
                
                // 썸네일 이미지 (화면 너비에 맞게 크게)
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.gracefulGold.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: AppTheme.gracefulGold.opacity(0.15), radius: 12, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.lightPurple.opacity(0.15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white.opacity(0.5))
                                Text("사진 불러오는 중...")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        )
                }
                
                // 하단 텍스트
                Text("방금 찍은 사진을 바로 정리해보세요")
                    .font(.caption)
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.6))
            }
            .padding(16)
            .background(GlassCard(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            loadRecentPhoto()
        }
        .onChange(of: photoManager.allPhotos.count) { _, _ in
            // PhotoManager가 사진을 로드하면 자동으로 다시 시도
            if thumbnail == nil {
                loadRecentPhoto()
            }
        }
        .fullScreenCover(isPresented: $showCleanUpView) {
            if let photo = recentPhoto,
               let index = photoManager.allPhotos.firstIndex(of: photo) {
                CleanUpView(
                    photos: photoManager.allPhotos,
                    startIndex: index,
                    isPresented: $showCleanUpView,
                    trashAlbum: Binding(
                        get: { photoManager.trashAssets },
                        set: { photoManager.trashAssets = $0; photoManager.saveTrash() }
                    ),
                    photoManager: photoManager
                )
            }
        }
        // 임시 휴지통 시트: CleanUpView의 휴지통 버튼에서 OpenTrash 알림 수신 시 표시
        .sheet(isPresented: $showTrashView) {
            TrashView(
                trashAssets: Binding(
                    get: { photoManager.trashAssets },
                    set: { photoManager.trashAssets = $0; photoManager.saveTrash() }
                ),
                photoManager: photoManager
            ) {
                photoManager.fetchPhotos()
            }
        }
        // CleanUpView에서 보낸 OpenTrash 신호 수신
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenTrash"))) { _ in
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.showTrashView = true
            }
        }
    }
    
    private func loadRecentPhoto() {
        guard !photoManager.allPhotos.isEmpty else {
            print("ZAKAR Log: RecentPhoto - allPhotos is empty, waiting...")
            return
        }
        
        print("ZAKAR Log: RecentPhoto - allPhotos has \(photoManager.allPhotos.count) photos")
        
        // 가장 최근 사진 (첫 번째)
        recentPhoto = photoManager.allPhotos.first
        
        guard let asset = recentPhoto else {
            print("ZAKAR Log: RecentPhoto - Failed to get first asset")
            return
        }
        
        print("ZAKAR Log: RecentPhoto - Starting image request for asset: \(asset.localIdentifier)")
        
        isLoading = true
        
        // 1단계: 매우 작은 썸네일로 초고속 로드
        let manager = PHImageManager.default()
        let fastOptions = PHImageRequestOptions()
        fastOptions.deliveryMode = .fastFormat  // 가장 빠른 모드
        fastOptions.resizeMode = .fast
        fastOptions.isNetworkAccessAllowed = true  // iCloud 사진도 로드 가능
        fastOptions.isSynchronous = false
        
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 300, height: 200),  // 작은 크기로 먼저
            contentMode: .aspectFill,
            options: fastOptions
        ) { image, info in
            print("ZAKAR Log: RecentPhoto - Image callback received")
            
            if let image = image {
                Task { @MainActor in
                    self.thumbnail = image
                    self.isLoading = false
                    print("ZAKAR Log: RecentPhoto - Fast thumbnail loaded successfully!")
                }
                
                // 2단계: 고화질 로드 (백그라운드)
                self.loadHighQualityImage(for: asset, manager: manager)
            } else {
                print("ZAKAR Log: RecentPhoto - Image is nil, info: \(String(describing: info))")
            }
        }
    }
    
    private func loadHighQualityImage(for asset: PHAsset, manager: PHImageManager) {
        let hqOptions = PHImageRequestOptions()
        hqOptions.deliveryMode = .opportunistic
        hqOptions.isNetworkAccessAllowed = true
        hqOptions.isSynchronous = false
        
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 600),
            contentMode: .aspectFill,
            options: hqOptions
        ) { image, info in
            if let image = image {
                Task { @MainActor in
                    self.thumbnail = image
                    print("ZAKAR Log: High quality thumbnail loaded")
                }
            }
        }
    }
}

private struct GlassSectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let count: Int
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.goldenGradient)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.lightPurple.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.7))
            }

            Spacer()

            // 개수 표시
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(AppTheme.lightPurple.opacity(0.6))
                        .scaleEffect(0.7)
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.dualGradient)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.5))
            }
        }
        .padding(16)
        .background(GlassCard(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

// MARK: - 월별 데이터 모델
struct MonthData: Identifiable {
    let id = UUID()
    let year: Int
    let month: Int
    let photoCount: Int
    let isCurrentMonth: Bool
    
    var displayText: String {
        return "\(year)년 \(month)월"
    }
}

// MARK: - 월별 정리 섹션
private struct MonthlyCleanupSection: View {
    @ObservedObject var photoManager: PhotoManager
    @State private var monthlyData: [MonthData] = []
    @State private var shouldReload: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 월별 리스트
            ForEach(monthlyData) { data in
                MonthCard(data: data)
            }
        }
        .onAppear {
            // 항상 최신 데이터로 재로드
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                loadMonthlyData()
            }
        }
        .onChange(of: photoManager.allPhotos.count) { _, newCount in
            // 사진 수가 변경되었을 때만 재로드
            // 단, 전체 사진이 로드되었을 때(필터 해제) 확실히 재로드
            if newCount > 100 || monthlyData.isEmpty {
                loadMonthlyData()
            }
        }
    }
    
    private func loadMonthlyData() {
        print("ZAKAR Log: MonthlyCleanupSection - Loading monthly data from \(photoManager.allPhotos.count) photos")
        monthlyData = photoManager.getMonthlyPhotoData()
        print("ZAKAR Log: MonthlyCleanupSection - Loaded \(monthlyData.count) months")
    }
}

// MARK: - 개별 월 카드 (GlassSectionCard 스타일)
private struct MonthCard: View {
    let data: MonthData
    
    var body: some View {
        NavigationLink(destination: ContentView(initialTab: 1, year: data.year, month: data.month)) {
            HStack(spacing: 14) {
                // 좌측: 캘린더 아이콘
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.purpleLavenderGradient)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.lightPurple.opacity(0.3), lineWidth: 1)
                    )
                
                // 중앙: 년월 표시
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.displayText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(formatMonthSubtitle(data))
                        .font(.caption)
                        .foregroundColor(AppTheme.gracefulGold.opacity(0.7))
                }
                
                Spacer()
                
                // 우측: 사진 개수
                HStack(spacing: 6) {
                    if data.photoCount > 0 {
                        Text("\(data.photoCount)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.purpleLavenderGradient)
                            .monospacedDigit()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.gracefulGold.opacity(0.5))
                }
            }
            .padding(16)
            .background(GlassCard(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func formatMonthSubtitle(_ data: MonthData) -> String {
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let monthName = months[data.month]
        return data.isCurrentMonth ? "이번 달 사진 보기" : "\(monthName) \(data.year)"
    }
}

