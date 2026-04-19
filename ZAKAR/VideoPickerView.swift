import SwiftUI
import Photos
import PhotosUI

// MARK: - 영상 선택 뷰
struct VideoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var googleDrive: GoogleDriveService
    @EnvironmentObject private var auth: AuthService
    
    @State private var selectedAssets: Set<PHAsset> = []
    @State private var eventName: String = ""
    @State private var showUploadConfirmation = false
    @State private var isLoadingVideos = false
    @State private var videoAssets: [PHAsset] = []
    
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                PremiumBackground(style: .warm)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerSection
                    
                    if isLoadingVideos {
                        ProgressView("영상 불러오는 중...")
                            .tint(.white)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if videoAssets.isEmpty {
                        emptyStateView
                    } else {
                        videoGridSection
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("영상 선택")
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
            loadVideos()
        }
        .sheet(isPresented: $showUploadConfirmation) {
            uploadConfirmationView
        }
    }
    
    // MARK: - 헤더 섹션
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                Text("업로드할 영상을 선택하세요")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(selectedAssets.isEmpty ? .white.opacity(0.3) : .green)
                    Text("\(selectedAssets.count)개 선택됨")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                if !videoAssets.isEmpty {
                    Button {
                        if selectedAssets.count == videoAssets.count {
                            selectedAssets.removeAll()
                        } else {
                            selectedAssets = Set(videoAssets)
                        }
                    } label: {
                        Text(selectedAssets.count == videoAssets.count ? "전체 해제" : "전체 선택")
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
    
    // MARK: - 영상 그리드
    private var videoGridSection: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(videoAssets, id: \.localIdentifier) { asset in
                    videoCell(asset: asset)
                }
            }
            .padding(8)
        }
    }
    
    private func videoCell(asset: PHAsset) -> some View {
        let isSelected = selectedAssets.contains(asset)
        
        return Button {
            if isSelected {
                selectedAssets.remove(asset)
            } else {
                selectedAssets.insert(asset)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                // 영상 썸네일
                VideoThumbnail(asset: asset)
                    .frame(width: 120, height: 120)
                    .clipped()
                
                // 재생 시간 표시
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(asset.duration))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
                
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
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("영상이 없습니다")
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
                        selectionInfoCard
                        eventNameInputCard
                        uploadPathPreviewCard
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
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.9))
                Text("선택된 영상")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Label("\(selectedAssets.count)개", systemImage: "checkmark.circle.fill")
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
        let sampleFileName = "VIDEO_\(dateStr.replacingOccurrences(of: "-", with: ""))_001.mp4"
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.9))
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
                Text("\(selectedAssets.count)개 업로드 시작")
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
    
    // MARK: - Helper Functions
    private func loadVideos() {
        isLoadingVideos = true
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        var videos: [PHAsset] = []
        
        fetchResult.enumerateObjects { asset, _, _ in
            videos.append(asset)
        }
        
        self.videoAssets = videos
        isLoadingVideos = false
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func startUpload() async {
        guard !selectedAssets.isEmpty else { return }
        
        showUploadConfirmation = false
        
        let assetArray = Array(selectedAssets)
        let department = auth.currentUser?.department ?? "미분류"
        
        print("[VideoPicker] Current user: \(String(describing: auth.currentUser))")
        print("[VideoPicker] Department: '\(department)', eventName: '\(eventName)'")
        
        // 업로드 시작 (백그라운드에서 실행)
        Task {
            do {
                // PHAsset 기반 업로드 (영상도 PHAsset으로 처리)
                try await googleDrive.uploadAssets(
                    assetArray,
                    department: department,
                    eventName: eventName
                ) { completed, total in
                    print("[VideoPicker] Upload progress: \(completed)/\(total)")
                }
            } catch {
                print("[VideoPicker] Upload failed: \(error)")
                await MainActor.run {
                    // 에러 알림 표시 (나중에 추가 가능)
                }
            }
        }
        
        // 즉시 화면 닫기 (업로드는 백그라운드에서 계속 진행)
        selectedAssets.removeAll()
        dismiss()
    }
}

// MARK: - 영상 썸네일 뷰
struct VideoThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        ZStack {
                            ProgressView()
                                .tint(.white.opacity(0.5))
                                .scaleEffect(0.7)
                            
                            Image(systemName: "video.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    )
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: 120, height: 120),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                DispatchQueue.main.async {
                    self.image = result
                }
            }
        }
    }
}
