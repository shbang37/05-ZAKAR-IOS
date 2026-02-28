import SwiftUI
import Photos

struct AlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var googleDrive: GoogleDriveService
    @EnvironmentObject private var auth: AuthService
    
    @State private var selectedAlbum: AlbumInfo?
    @State private var eventName: String = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var currentUploadIndex = 0
    @State private var totalUploadCount = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // 배경 그라디언트
                LinearGradient(
                    colors: [Color.black, Color(red: 0.06, green: 0.07, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                        VStack(spacing: 16) {
                            // 안내 카드
                            instructionCard
                            
                            // 앨범 목록
                            if photoManager.albums.isEmpty {
                                emptyStateView
                            } else {
                                albumListSection
                            }
                            
                            Spacer(minLength: 30)
                        }
                        .padding()
                    }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("앨범 선택")
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
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedAlbum) { album in
            albumDetailView(album: album)
        }
    }
    
    // MARK: - 안내 카드
    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue.opacity(0.8))
                Text("업로드 방식")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("1. 앨범을 선택하면 앨범명 기반 이벤트명이 자동 생성됩니다")
                Text("2. 폴더 경로: ZAKAR/\(auth.currentUser?.department ?? "부서")/연도/\(auth.currentUser?.department ?? "부서")_날짜_이벤트명/")
                Text("3. 파일명: 원본명.확장자")
            }
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.5))
        }
        .padding(14)
        .background(GlassCard())
    }
    
    // MARK: - 앨범 목록
    private var albumListSection: some View {
        VStack(spacing: 12) {
            ForEach(photoManager.albums) { album in
                albumRow(album: album)
            }
        }
    }
    
    private func albumRow(album: AlbumInfo) -> some View {
        Button {
            selectedAlbum = album
        } label: {
            HStack(spacing: 12) {
                // 앨범 썸네일
                albumThumbnail(album: album)
                
                // 앨범 정보
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 10))
                        Text("\(album.assetCount)장")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.white.opacity(0.5))
                    
                    if let date = album.endDate {
                        Text(date, style: .date)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(14)
            .background(GlassCard())
        }
    }
    
    private func albumThumbnail(album: AlbumInfo) -> some View {
        let assets = PHAsset.fetchAssets(in: album.collection, options: nil)
        let asset = assets.firstObject
        
        return Group {
            if let asset = asset {
                AsyncImage(asset: asset)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.white.opacity(0.3))
                    )
            }
        }
    }
    
    // MARK: - 빈 상태
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("앨범이 없습니다")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - 앨범 상세 (이벤트명 입력 및 확인)
    private func albumDetailView(album: AlbumInfo) -> some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.06, green: 0.07, blue: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 앨범 정보
                        albumInfoCard(album: album)
                        
                        // 이벤트명 입력
                        eventNameInputCard(album: album)
                        
                        // 업로드 경로 미리보기
                        uploadPathPreview(album: album)
                        
                        // 업로드 버튼
                        uploadButton(album: album)
                        
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
                        selectedAlbum = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            eventName = generateEventName(from: album)
        }
    }
    
    private func albumInfoCard(album: AlbumInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.purple.opacity(0.9))
                Text("선택된 앨범")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(album.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            
            HStack(spacing: 16) {
                Label("\(album.assetCount)장", systemImage: "photo.stack")
                if let date = album.endDate {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.5))
        }
        .padding(16)
        .background(GlassCard())
    }
    
    private func eventNameInputCard(album: AlbumInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue.opacity(0.9))
                Text("이벤트명")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            TextField("이벤트명 입력", text: $eventName)
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
    
    private func uploadPathPreview(album: AlbumInfo) -> some View {
        let department = auth.currentUser?.department ?? "부서"
        let year = Calendar.current.component(.year, from: album.endDate ?? Date())
        let dateStr = (album.endDate ?? Date()).formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        let folderPath = "ZAKAR/\(department)/\(year)/\(department)_\(dateStr)_\(eventName)/"
        let sampleFileName = "IMG_1234.jpg"
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green.opacity(0.9))
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
    
    private func uploadButton(album: AlbumInfo) -> some View {
        Button {
            Task {
                await startUpload(album: album)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(album.assetCount)장 업로드 시작")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.purple, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .purple.opacity(0.3), radius: 10, y: 4)
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
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: uploadProgress)
                
                VStack(spacing: 4) {
                    Text("\(Int(uploadProgress * 100))%")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(currentUploadIndex) / \(totalUploadCount)")
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
    private func generateEventName(from album: AlbumInfo) -> String {
        // 앨범명만 반환 (날짜는 GoogleDriveService에서 폴더명에 추가함)
        return album.title
    }
    
    private func startUpload(album: AlbumInfo) async {
        // 앨범에서 PHAsset 가져오기
        let assets = PHAsset.fetchAssets(in: album.collection, options: nil)
        var assetArray: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            assetArray.append(asset)
        }
        
        guard !assetArray.isEmpty else { return }
        
        // Google Drive에 업로드 (진행상황은 ArchiveView에서 표시)
        let department = auth.currentUser?.department ?? "미분류"
        print("[AlbumPicker] Current user: \(String(describing: auth.currentUser))")
        print("[AlbumPicker] Department: '\(department)', eventName: '\(eventName)'")
        
        // 업로드 시작 (백그라운드에서 실행)
        Task {
            do {
                try await googleDrive.uploadAssets(
                    assetArray,
                    department: department,
                    eventName: eventName
                )
            } catch {
                print("[AlbumPicker] Upload failed: \(error)")
            }
        }
        
        // 즉시 화면 닫기 (업로드는 백그라운드에서 계속)
        selectedAlbum = nil
        dismiss()
    }
}

// MARK: - PHAsset 비동기 이미지 로더
struct AsyncImage: View {
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
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .scaleEffect(0.7)
                    )
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
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
