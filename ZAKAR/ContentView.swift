import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var selectedTab = 0
    
    // Optional filters for year/month navigation
    private let filterYear: Int?
    private let filterMonth: Int?
    
    private let initialTabParam: Int
    
    // [해결] UIImage 대신 PHAsset 배열을 사용하여 타입 불일치 해결
    @State private var trashAssets: [PHAsset] = []
    
    @State private var showTrashView = false
    @State private var isCleanModeActive = false
    @State private var selectedPhotosForClean: [PHAsset] = []
    @State private var startPosition: Int = 0
    @State private var currentGroupIndex: Int = 0
    @State private var cleanModeID = UUID()  // fullScreenCover 강제 재생성용
    @State private var pendingCleanModeRetry: (photoIndex: Int, groupIndex: Int?)? = nil  // 재시도용

    @State private var showCreateAlbumSheet = false
    @State private var newAlbumName: String = ""
    
    @State private var showTutorialOverlay = false

    init(initialTab: Int = 0, year: Int? = nil, month: Int? = nil) {
        self._selectedTab = State(initialValue: initialTab)
        self.filterYear = year
        self.filterMonth = month
        self.initialTabParam = initialTab
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient
                    .ignoresSafeArea()

                // Vignette
                RadialGradient(gradient: Gradient(colors: [Color.clear, AppTheme.bgDeepPurple.opacity(0.5)]), center: .center, startRadius: 100, endRadius: 600)
                    .ignoresSafeArea()
                    .blendMode(.multiply)

                VStack(spacing: 0) {
                    if photoManager.isLoadingList {
                        VStack(spacing: 15) {
                            ProgressView().tint(AppTheme.dawnPurple)
                            Text("사진 목록 불러오는 중...").foregroundColor(AppTheme.gracefulGold.opacity(0.7)).font(.caption)
                        }
                        .padding(24)
                        .background(GlassCard(cornerRadius: 20))
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Color.clear.frame(height: 10)
                            
                            if selectedTab == 0 {
                                if photoManager.isAnalyzing {
                                    HStack(spacing: 8) {
                                        ProgressView().tint(AppTheme.dawnPurple)
                                        Text("유사 사진 분석 중...")
                                            .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                                            .font(.caption)
                                    }
                                    .padding(.bottom, 8)
                                }
                                
                                // 1. 정리 대상 (유사 그룹 레이아웃)
                                if photoManager.groupedPhotos.isEmpty && !photoManager.isAnalyzing {
                                    VStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle")
                                            .font(.system(size: 50))
                                            .foregroundColor(.green)
                                        Text("유사 사진이 없습니다")
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(40)
                                } else {
                                    LazyVStack(spacing: 16) {
                                        ForEach(photoManager.groupedPhotos.indices, id: \.self) { groupIndex in
                                            SimilarityGroupRow(group: photoManager.groupedPhotos[groupIndex]) { photoIndex in
                                                openCleanMode(at: photoIndex, groupIndex: groupIndex)
                                            }
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                    .fill(Color.white.opacity(0.06))
                                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                            .stroke(LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                                                    )
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            } else {
                                // 2. 모든 사진 그리드
                                if photoManager.allPhotos.isEmpty {
                                    VStack(spacing: 10) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 50))
                                            .foregroundColor(.gray)
                                        Text("사진이 없습니다")
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(40)
                                } else {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 2)], spacing: 2) {
                                        ForEach(photoManager.allPhotos.indices, id: \.self) { photoIndex in
                                            AssetThumbnail(asset: photoManager.allPhotos[photoIndex], size: 125)
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                                                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
                                                .onTapGesture {
                                                    openCleanMode(at: photoIndex, groupIndex: nil)
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 20)
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                if showTutorialOverlay {
                    Color.black.opacity(0.6).ignoresSafeArea()
                        .overlay(
                            VStack(spacing: 16) {
                                Text("유사 사진 정리 튜토리얼")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("위로 스와이프 = 삭제 후보, 아래로 = 즐겨찾기, 좌/우 = 사진 이동")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.85))
                                    .multilineTextAlignment(.center)
                                Button {
                                    withAnimation { showTutorialOverlay = false }
                                } label: {
                                    Text("알겠어요").bold()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                                .accessibilityLabel("튜토리얼 닫기")
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .padding()
                        )
                        .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $selectedTab) {
                        Text("모든 사진").tag(1)
                        Text("유사 사진").tag(0)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 220)
                    .padding(6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    )
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateAlbumSheet = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("새 앨범 만들기")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    // [연결] trashAssets 개수를 버튼에 반영
                    TrashBucketButton(count: trashAssets.count) {
                        showTrashView = true
                    }
                }
            }
            // [해결] CleanUpView에 [PHAsset] 타입의 trashAssets 전달
            .fullScreenCover(isPresented: $isCleanModeActive) {
                CleanUpView(photos: selectedPhotosForClean,
                            startIndex: startPosition,
                            isPresented: $isCleanModeActive,
                            trashAlbum: Binding(get: { trashAssets }, set: { newValue in
                                trashAssets = newValue
                                saveTrashIdentifiers(from: newValue)
                            }),
                            photoManager: photoManager,
                            onFinishGroup: {
                                // 그룹 정리 완료 시 다음 그룹으로 자동 이동
                                moveToNextGroup()
                            })
                .id(cleanModeID)  // ID로 강제 재생성
            }
            // [해결] TrashView 생성자 에러 수정: trashAssets 바인딩과 photoManager 주입
            .sheet(isPresented: $showTrashView) {
                // 삭제 성공 시 photoManager를 통해 목록을 새로고침하는 콜백 추가
                TrashView(trashAssets: Binding(get: { trashAssets }, set: { newValue in
                    trashAssets = newValue
                    saveTrashIdentifiers(from: newValue)
                }), photoManager: photoManager) {
                    photoManager.fetchPhotos()
                }
            }
            .sheet(isPresented: $showCreateAlbumSheet) {
                NavigationView {
                    VStack(spacing: 16) {
                        Text("새 앨범 만들기").font(.headline)
                        TextField("앨범 이름", text: $newAlbumName)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                        HStack {
                            Button("취소") { showCreateAlbumSheet = false }
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("생성") {
                                let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                photoManager.fetchOrCreateAlbum(named: name) { _ in }
                                newAlbumName = ""
                                showCreateAlbumSheet = false
                            }
                            .bold()
                        }
                        .padding(.horizontal)
                        Spacer()
                    }
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .onAppear {
                self.selectedTab = initialTabParam

                // 연/월 필터가 있으면 무조건 새로 fetch
                if filterYear != nil || filterMonth != nil {
                    photoManager.fetchPhotos(year: filterYear, month: filterMonth)
                } else if photoManager.allPhotos.isEmpty && !photoManager.isLoadingList {
                    // 사진이 아직 없고 로딩 중도 아닐 때만 fetch
                    photoManager.fetchPhotos()
                }

                // 유사 사진 탭으로 시작하거나, 사진이 이미 있으면 즉시 분석 시도
                if initialTabParam == 0 || !photoManager.allPhotos.isEmpty {
                    photoManager.analyzeSimilaritiesIfNeeded()
                }

                let hasShown = UserDefaults.standard.bool(forKey: "ZAKAR_TutorialShown")
                if !hasShown {
                    showTutorialOverlay = true
                    UserDefaults.standard.set(true, forKey: "ZAKAR_TutorialShown")
                }
                loadPersistedTrash()
            }
            .onChange(of: selectedTab) { _, newValue in
                if newValue == 0 {
                    photoManager.analyzeSimilaritiesIfNeeded()
                }
            }
            .onChange(of: isCleanModeActive) { oldValue, newValue in
                // CleanUpView가 닫혔을 때 재시도 체크
                if oldValue == true && newValue == false {
                    if let retry = pendingCleanModeRetry {
                        print("ZAKAR Log: Auto-retry detected - photoIndex: \(retry.photoIndex), groupIndex: \(String(describing: retry.groupIndex))")
                        
                        // 0.3초 후 재시도 (데이터 로딩 대기)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.pendingCleanModeRetry = nil
                            self.openCleanMode(at: retry.photoIndex, groupIndex: retry.groupIndex)
                        }
                    }
                }
            }
            // CleanUpView에서 보낸 신호를 받아 휴지통 화면을 띄움
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenTrash"))) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.showTrashView = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func openCleanMode(at photoIndex: Int, groupIndex: Int? = nil) {
        print("ZAKAR Log: openCleanMode called - photoIndex: \(photoIndex), groupIndex: \(String(describing: groupIndex))")
        print("ZAKAR Log: selectedTab: \(selectedTab)")
        print("ZAKAR Log: photoManager.allPhotos.count: \(photoManager.allPhotos.count)")
        print("ZAKAR Log: photoManager.groupedPhotos.count: \(photoManager.groupedPhotos.count)")
        
        // 재시도 정보 저장 (사진이 없을 경우 자동 재시도)
        pendingCleanModeRetry = (photoIndex, groupIndex)
        
        // photoManager에서 직접 가져오기
        let photoList: [PHAsset]
        let actualGroupIndex: Int
        
        if let gIndex = groupIndex {
            // 유사 사진 탭 - groupIndex 지정됨
            guard gIndex < photoManager.groupedPhotos.count else {
                print("ZAKAR Log: ERROR - groupIndex \(gIndex) out of range!")
                pendingCleanModeRetry = nil
                return
            }
            photoList = photoManager.groupedPhotos[gIndex]
            actualGroupIndex = gIndex
            print("ZAKAR Log: Using groupedPhotos[\(gIndex)] - count: \(photoList.count)")
        } else {
            // 모든 사진 탭
            photoList = photoManager.allPhotos
            actualGroupIndex = 0
            print("ZAKAR Log: Using allPhotos - count: \(photoList.count)")
        }
        
        // 빈 배열 체크
        guard !photoList.isEmpty else {
            print("ZAKAR Log: FATAL - photoList is empty! Will auto-retry...")
            // pendingCleanModeRetry는 유지 (자동 재시도)
            return
        }
        
        // 인덱스 범위 체크
        guard photoList.indices.contains(photoIndex) else {
            print("ZAKAR Log: ERROR - photoIndex \(photoIndex) out of range (list size: \(photoList.count))!")
            pendingCleanModeRetry = nil
            return
        }
        
        // 성공적으로 열림 - 재시도 정보 클리어
        pendingCleanModeRetry = nil
        
        self.selectedPhotosForClean = photoList
        self.startPosition = photoIndex
        self.currentGroupIndex = actualGroupIndex
        self.cleanModeID = UUID()  // 매번 새로운 ID로 View 강제 재생성
        
        // Pre-fetch first image before opening CleanUpView
        let asset = photoList[photoIndex]
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        print("ZAKAR Log: Pre-fetching first image before opening CleanUpView - photoIndex: \(photoIndex)")
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 600, height: 600),
            contentMode: .aspectFit,
            options: options
        ) { img, info in
            if let img = img {
                print("ZAKAR Log: Pre-fetch completed - size: \(img.size)")
            } else {
                print("ZAKAR Log: Pre-fetch failed or returned nil")
            }
            // Open CleanUpView after pre-fetch completes (or fails)
            DispatchQueue.main.async {
                self.isCleanModeActive = true
            }
        }
    }
    
    /// CleanUpView 종료 시 다음 그룹으로 자동 이동
    private func moveToNextGroup() {
        // 다음 그룹이 있는지 확인
        let nextIndex = currentGroupIndex + 1
        
        print("ZAKAR Log: moveToNextGroup() - 현재 그룹: \(currentGroupIndex), 다음 그룹: \(nextIndex), 전체 그룹: \(photoManager.groupedPhotos.count)")
        
        if nextIndex < photoManager.groupedPhotos.count {
            // 현재 CleanUpView 닫기
            isCleanModeActive = false
            
            print("ZAKAR Log: 다음 그룹 사진 개수: \(photoManager.groupedPhotos[nextIndex].count)")
            
            // 짧은 delay 후 다음 그룹 열기
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // openCleanMode를 사용하여 다음 그룹 열기
                self.openCleanMode(at: 0, groupIndex: nextIndex)
            }
        } else {
            // 마지막 그룹이었으면 CleanUpView 닫기
            print("ZAKAR Log: 마지막 그룹 완료, CleanUpView 닫기")
            isCleanModeActive = false
        }
    }
    
    private func loadPersistedTrash() {
        let ids = LocalDB.shared.loadTrashIdentifiers()
        guard !ids.isEmpty else { self.trashAssets = []; return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var temp: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in temp.append(asset) }
        self.trashAssets = temp
    }

    private func saveTrashIdentifiers(from assets: [PHAsset]) {
        let ids = assets.map { $0.localIdentifier }
        LocalDB.shared.saveTrashIdentifiers(ids)
    }
}

