import SwiftUI
import Photos

struct PhotoSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var googleDrive: GoogleDriveService
    @EnvironmentObject private var auth: AuthService
    
    @State private var selectedAssets: Set<PHAsset> = []
    @State private var eventName: String = ""
    @State private var showUploadConfirmation = false
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var currentUploadIndex = 0
    @State private var isLoadingPhotos = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Premium background
                PremiumBackground(style: .warm)
                
                VStack(spacing: 0) {
                        // 상단 안내 및 선택 카운트
                        headerSection
                        
                        // 사진 그리드
                        if isLoadingPhotos {
                            ProgressView("사진 불러오는 중...")
                                .tint(.white)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if photoManager.allPhotos.isEmpty {
                            emptyStateView
                        } else {
                            photoGridSection
                        }
                    }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("사진 선택")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !selectedAssets.isEmpty {
                        Button {
                            showUploadConfirmation = true
                        } label: {
                            Text("다음")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.gracefulGold)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadPhotos()
        }
        .sheet(isPresented: $showUploadConfirmation) {
            uploadConfirmationView
        }
    }
    
    // MARK: - 헤더 섹션
    private var headerSection: some View {
        VStack(spacing: 12) {
            // 안내 카드
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                Text("업로드할 사진을 선택하세요")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // 선택 카운트 및 전체 선택/해제
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(selectedAssets.isEmpty ? .white.opacity(0.3) : .green)
                    Text("\(selectedAssets.count)장 선택됨")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                if !photoManager.allPhotos.isEmpty {
                    Button {
                        if selectedAssets.count == photoManager.allPhotos.count {
                            selectedAssets.removeAll()
                        } else {
                            selectedAssets = Set(photoManager.allPhotos)
                        }
                    } label: {
                        Text(selectedAssets.count == photoManager.allPhotos.count ? "전체 해제" : "전체 선택")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.gracefulGold)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - 사진 그리드
    private var photoGridSection: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(photoManager.allPhotos, id: \.localIdentifier) { asset in
                    photoCell(asset: asset)
                }
            }
            .padding(2)
        }
    }
    
    private func photoCell(asset: PHAsset) -> some View {
        let isSelected = selectedAssets.contains(asset)
        
        return Button {
            if isSelected {
                selectedAssets.remove(asset)
            } else {
                selectedAssets.insert(asset)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                // 사진 썸네일
                AsyncImage(asset: asset)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
                
                // 선택 오버레이
                if isSelected {
                    AppTheme.gracefulGold.opacity(0.3)
                    
                    // 체크마크
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.gracefulGold)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                        )
                        .padding(6)
                }
                
                // 선택 안 된 상태 원형 테두리
                if !isSelected {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .padding(6)
                }
            }
        }
        .clipShape(Rectangle())
    }
    
    // MARK: - 빈 상태
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("사진이 없습니다")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 업로드 확인 뷰
    private var uploadConfirmationView: some View {
        NavigationView {
            ZStack {
                PremiumBackground(style: .warm)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 선택 정보
                        selectionInfoCard
                        
                        // 이벤트명 입력
                        eventNameInputCard
                        
                        // 업로드 경로 미리보기
                        uploadPathPreviewCard
                        
                        // 업로드 버튼
                        uploadButtonCard
                        
                        Spacer(minLength: 30)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("업로드 확인")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showUploadConfirmation = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var selectionInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.stack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green.opacity(0.9))
                Text("선택된 사진")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Label("\(selectedAssets.count)장", systemImage: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(16)
        .background(GlassCard())
    }
    
    private var eventNameInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.9))
                Text("이벤트명")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("업로드할 폴더의 이벤트명을 입력하세요")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            
            TextField("예: 주일예배, 수련회, 크리스마스", text: $eventName)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
        .padding(16)
        .background(GlassCard())
    }
    
    private var uploadPathPreviewCard: some View {
        let department = auth.currentUser?.department ?? "부서"
        let year = Calendar.current.component(.year, from: Date())
        let dateStr = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        let folderPath = "ZAKAR/\(department)/\(year)/\(dateStr)_\(eventName.isEmpty ? "이벤트명" : eventName)/"
        let sampleFileName = "\(department)_\(dateStr.replacingOccurrences(of: "-", with: ""))_143022_IMG_1234.jpg"
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange.opacity(0.9))
                Text("업로드 경로 미리보기")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                pathRow(label: "폴더", value: folderPath)
                pathRow(label: "파일 예시", value: sampleFileName)
            }
        }
        .padding(16)
        .background(GlassCard())
    }
    
    private func pathRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var uploadButtonCard: some View {
        Button {
            Task {
                await startUpload()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(selectedAssets.count)장 업로드 시작")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppTheme.gracefulGold)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AppTheme.gracefulGold.opacity(0.3), radius: 10, y: 4)
        }
        .disabled(eventName.isEmpty)
        .opacity(eventName.isEmpty ? 0.5 : 1)
        .padding(16)
        .background(GlassCard())
    }
    
    // MARK: - 업로드 진행률 화면
    private var uploadProgressView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 진행률 원형
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 12)
                    .frame(width: 140, height: 140)
                
                Circle()
                    .trim(from: 0, to: uploadProgress)
                    .stroke(
                        AppTheme.gracefulGold,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: uploadProgress)
                
                VStack(spacing: 4) {
                    Text("\(Int(uploadProgress * 100))%")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(currentUploadIndex) / \(selectedAssets.count)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            VStack(spacing: 8) {
                Text("업로드 중...")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("Google Drive에 사진을 업로드하고 있습니다")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Helper Functions
    private func loadPhotos() {
        isLoadingPhotos = true
        photoManager.fetchPhotos()
        
        // PhotoManager의 로딩 완료 대기
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoadingPhotos = false
        }
    }
    
    private func startUpload() async {
        guard !selectedAssets.isEmpty else { return }
        
        showUploadConfirmation = false
        
        let assetArray = Array(selectedAssets)
        let department = auth.currentUser?.department ?? "미분류"
        print("[PhotoSelection] Current user: \(String(describing: auth.currentUser))")
        print("[PhotoSelection] Department: '\(department)', eventName: '\(eventName)'")
        
        // 업로드 시작 (백그라운드에서 실행)
        Task {
            do {
                try await googleDrive.uploadAssets(
                    assetArray,
                    department: department,
                    eventName: eventName
                )
            } catch {
                print("[PhotoSelection] Upload failed: \(error)")
            }
        }
        
        // 즉시 화면 닫기 (업로드는 백그라운드에서 계속)
        selectedAssets.removeAll()
        dismiss()
    }
}
