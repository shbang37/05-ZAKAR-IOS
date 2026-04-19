import SwiftUI
import Photos
import Combine

// MARK: - NAS Mock 업로드 항목
struct NASUploadItem: Identifiable {
    let id = UUID()
    let filename: String
    let size: String          // 표시용 문자열 (e.g. "3.2 MB")
    var progress: Double      // 0.0 ~ 1.0
    var status: UploadStatus

    enum UploadStatus {
        case waiting, uploading, done, failed
    }
}

// MARK: - NAS Mock 서비스
/// 실제 NAS 하드웨어 없이 업로드 흐름을 시연하는 Mock 서비스입니다.
/// 나중에 Synology WebDAV/API로 교체할 수 있도록 ZKDriveSyncing 프로토콜을 따릅니다.
@MainActor
final class NASMockService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var nasAddress: String = "192.168.1.100"   // 사용자가 입력할 NAS IP
    @Published var uploadQueue: [NASUploadItem] = []
    @Published var isUploading: Bool = false
    @Published var lastSyncAt: Date?

    private var simulationTask: Task<Void, Never>?

    // NAS 연결 시뮬레이션 (실제 구현 시 WebDAV ping으로 교체)
    func connect() async {
        // 1.5초 딜레이로 네트워크 연결 체험
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        isConnected = true
    }

    func disconnect() {
        isConnected = false
        simulationTask?.cancel()
        uploadQueue.removeAll()
        isUploading = false
    }

    // 사진 배열을 Mock 업로드 큐에 추가하고 순서대로 업로드 시연
    func enqueueAndUpload(assets: [PHAsset]) async {
        guard isConnected, !isUploading else { return }

        // 큐 생성 (PHAsset 이름을 못 읽으므로 mock 파일명 생성)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let newItems: [NASUploadItem] = assets.enumerated().map { i, _ in
            let stamp = dateFormatter.string(from: Date().addingTimeInterval(Double(i)))
            let kb = Int.random(in: 800...6000)
            let sizeStr = kb >= 1000 ? String(format: "%.1f MB", Double(kb) / 1000) : "\(kb) KB"
            return NASUploadItem(
                filename: "ZAKAR_\(stamp)_\(String(format: "%03d", i+1)).heic",
                size: sizeStr,
                progress: 0,
                status: .waiting
            )
        }
        uploadQueue.append(contentsOf: newItems)

        await runUploadSimulation()
    }

    // 전체 Queue 업로드 시뮬레이션
    private func runUploadSimulation() async {
        isUploading = true
        defer {
            isUploading = false
            lastSyncAt = Date()
        }

        for i in uploadQueue.indices {
            // 이미 완료된 항목 건너뜀
            guard uploadQueue[i].status != .done else { continue }

            uploadQueue[i].status = .uploading

            // 0.0 → 1.0 까지 진행 애니메이션 (0.05 단위로 20 steps)
            for step in 1...20 {
                // 취소 확인
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64.random(in: 30_000_000...90_000_000))
                uploadQueue[i].progress = Double(step) / 20.0
            }

            uploadQueue[i].status = .done
        }
    }

    func clearCompleted() {
        uploadQueue.removeAll { $0.status == .done }
    }
}

// MARK: - 통합 아카이브(업로드) 탭
struct ArchiveView: View {
    @StateObject private var nasMock = NASMockService()
    @EnvironmentObject private var googleDrive: GoogleDriveService
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var auth: AuthService

    @State private var isConnecting = false
    @State private var showNASDemo = false
    @State private var selectedProvider: ArchiveProvider = .nas
    @State private var uploadMode: UploadMode = .album
    @State private var showAlbumPicker = false
    @State private var showPhotoPicker = false
    @State private var showVideoPicker = false
    @State private var showDocumentPicker = false
    
    enum UploadMode {
        case album, photos, videos, documents
    }

    enum ArchiveProvider: String, CaseIterable {
        case nas = "NAS"
        case googleDrive = "Google Drive"

        var icon: String {
            switch self {
            case .nas: return "externaldrive.connected.to.line.below"
            case .googleDrive: return "arrow.up.to.line.compact"
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Premium warm background
                PremiumBackground(style: .warm)

                ScrollView {
                    VStack(spacing: 20) {
                        // 제공자 선택 세그먼트
                        providerPicker
                            .padding(.horizontal)
                            .padding(.top, 8)

                        // 선택된 제공자에 따른 패널
                        if selectedProvider == .nas {
                            nasPanel
                        } else {
                            googleDrivePanel
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("아카이브")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 제공자 선택 피커
    private var providerPicker: some View {
        HStack(spacing: 0) {
            ForEach(ArchiveProvider.allCases, id: \.self) { provider in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedProvider = provider
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: provider.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(provider.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(selectedProvider == provider ? .white : .white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                selectedProvider == provider
                                    ? AppTheme.lightPurple.opacity(0.15)
                                    : Color.clear
                            )
                    )
                }
            }
        }
        .padding(4)
        .background(GlassCard(cornerRadius: 14))
    }

    // MARK: - NAS 패널
    private var nasPanel: some View {
        VStack(spacing: 16) {
            nasStatusCard
            if nasMock.isConnected {
                nasUploadDemoCard
                if !nasMock.uploadQueue.isEmpty {
                    nasQueueCard
                }
            }
        }
        .padding(.horizontal)
    }

    private var nasStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 헤더
            HStack {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(nasMock.isConnected ? .green : .white.opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synology NAS")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(nasMock.isConnected ? "연결됨 · \(nasMock.nasAddress)" : "연결되지 않음")
                        .font(.system(size: 12))
                        .foregroundColor(nasMock.isConnected ? .green.opacity(0.9) : .white.opacity(0.4))
                }
                Spacer()
                // 상태 점
                Circle()
                    .fill(nasMock.isConnected ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 9, height: 9)
                    .shadow(color: nasMock.isConnected ? .green.opacity(0.6) : .clear, radius: 4)
            }

            // NAS 주소 입력 (비연결 상태일 때)
            if !nasMock.isConnected {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 13))
                    TextField("NAS IP 주소 (예: 192.168.1.100)", text: $nasMock.nasAddress)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .keyboardType(.decimalPad)
                }
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.lightPurple.opacity(0.06))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.gracefulGold.opacity(0.15), lineWidth: 0.5)
                )
            }

            // 마지막 동기화 시간
            if let lastSync = nasMock.lastSyncAt, nasMock.isConnected {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Text("마지막 동기화: \(lastSync, style: .relative) 전")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // 폴더 열기 버튼 (연결 시에만 표시)
            if nasMock.isConnected {
                Button {
                    // NAS 웹 인터페이스 열기 (예: Synology DSM)
                    let nasURL = "http://\(nasMock.nasAddress):5000"
                    if let url = URL(string: nasURL) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 14, weight: .semibold))
                        Text("NAS 폴더 열기")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.lightPurple.opacity(0.08))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.gracefulGold.opacity(0.3), AppTheme.lightPurple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                }
            }

            // 연결/해제 버튼
            Button {
                if nasMock.isConnected {
                    nasMock.disconnect()
                } else {
                    isConnecting = true
                    Task {
                        await nasMock.connect()
                        isConnecting = false
                    }
                }
            } label: {
                HStack {
                    if isConnecting {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text(isConnecting ? "연결 중..." : (nasMock.isConnected ? "연결 해제" : "NAS 연결"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(nasMock.isConnected ? .red.opacity(0.9) : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            nasMock.isConnected
                                ? Color.red.opacity(0.15)
                                : AppTheme.lightPurple.opacity(0.08)
                        )
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            nasMock.isConnected 
                                ? LinearGradient(colors: [Color.red.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(
                                    colors: [AppTheme.gracefulGold.opacity(0.3), AppTheme.lightPurple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: 1.0
                        )
                )
            }
            .disabled(isConnecting)
        }
        .padding(18)
        .background(GlassCard())
    }

    private var nasUploadDemoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "arrow.up.to.line.compact")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue.opacity(0.9))
                Text("NAS 업로드 시연")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if nasMock.isUploading {
                    ProgressView().tint(.blue).scaleEffect(0.75)
                }
            }

            Text("실제 NAS 하드웨어 없이도 업로드 흐름을 확인할 수 있습니다.\n연결 후 아래 버튼으로 시연을 시작하세요.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .lineSpacing(3)

            HStack(spacing: 10) {
                // 최근 사진 5장 Mock 업로드
                Button {
                    let assets = Array(photoManager.allPhotos.prefix(5))
                    Task { await nasMock.enqueueAndUpload(assets: assets) }
                } label: {
                    Label("최근 5장 업로드", systemImage: "photo.stack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AppTheme.purpleGradient)
                        )
                }
                .disabled(nasMock.isUploading || photoManager.allPhotos.isEmpty)

                // 완료 항목 정리
                if nasMock.uploadQueue.contains(where: { $0.status == .done }) {
                    Button {
                        nasMock.clearCompleted()
                    } label: {
                        Image(systemName: "checkmark.circle.trianglebadge.exclamationmark")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AppTheme.lightPurple.opacity(0.08))
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
        .padding(18)
        .background(GlassCard())
    }

    private var nasQueueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("업로드 현황")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                let doneCount = nasMock.uploadQueue.filter { $0.status == .done }.count
                Text("\(doneCount) / \(nasMock.uploadQueue.count) 완료")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
            }

            ForEach(nasMock.uploadQueue) { item in
                NASUploadRow(item: item)
            }
        }
        .padding(16)
        .background(GlassCard())
    }

    // MARK: - Google Drive 패널
    private var googleDrivePanel: some View {
        VStack(spacing: 16) {
            googleDriveStatusCard
            if googleDrive.isLinked {
                uploadModeSelector
                uploadActionCard
                
                // 업로드 큐 표시
                if !googleDrive.uploadQueue.isEmpty {
                    driveQueueCard
                }
            } else {
                googleDriveGuideCard
            }
        }
        .padding(.horizontal)
        .alert("연결 오류", isPresented: Binding(
            get: { googleDrive.linkError != nil },
            set: { if !$0 { googleDrive.linkError = nil } }
        )) {
            Button("확인", role: .cancel) { googleDrive.linkError = nil }
        } message: {
            Text(googleDrive.linkError ?? "")
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerView()
                .environmentObject(photoManager)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoSelectionView()
                .environmentObject(photoManager)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPickerView()
                .environmentObject(photoManager)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView()
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
    }

    private var googleDriveStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 헤더
            HStack {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(googleDrive.isLinked ? .green : .white.opacity(0.55))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Drive")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(googleDrive.isLinked ? "계정 연결됨" : (googleDrive.isLinking ? "연결 중..." : "연결되지 않음"))
                        .font(.system(size: 12))
                        .foregroundColor(googleDrive.isLinked ? .green.opacity(0.9) : .white.opacity(0.4))
                }
                Spacer()
                if googleDrive.isLinking {
                    ProgressView().tint(.white.opacity(0.6)).scaleEffect(0.75)
                } else {
                    Circle()
                        .fill(googleDrive.isLinked ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 9, height: 9)
                        .shadow(color: googleDrive.isLinked ? .green.opacity(0.6) : .clear, radius: 4)
                }
            }

            if let lastSync = googleDrive.lastSyncAt, googleDrive.isLinked {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Text("마지막 동기화: \(lastSync, style: .relative) 전")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // 폴더 열기 버튼 (연결 시에만 표시)
            if googleDrive.isLinked {
                Button {
                    if let url = URL(string: "https://drive.google.com/drive/folders/root") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Google Drive 열기")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.lightPurple.opacity(0.08))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.gracefulGold.opacity(0.3), AppTheme.lightPurple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                }
            }

            // 연결/해제 버튼
            Button {
                Task {
                    if googleDrive.isLinked { googleDrive.unlink() }
                    else { await googleDrive.link() }
                }
            } label: {
                HStack(spacing: 6) {
                    if googleDrive.isLinking {
                        ProgressView().tint(.white).scaleEffect(0.75)
                    } else {
                        Image(systemName: googleDrive.isLinked ? "link.badge.minus" : "link")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(googleDrive.isLinking ? "Google 로그인 중..." :
                         (googleDrive.isLinked ? "연결 해제" : "Google 계정 연결"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(googleDrive.isLinked ? .red.opacity(0.9) : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(googleDrive.isLinked ? Color.red.opacity(0.15) : Color.blue.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(googleDrive.isLinked ? Color.red.opacity(0.3) : Color.blue.opacity(0.4), lineWidth: 0.5)
                )
            }
            .disabled(googleDrive.isLinking)
        }
        .padding(18)
        .background(GlassCard())
    }
    
    // MARK: - 업로드 모드 선택
    private var uploadModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("업로드 방식 선택")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    modeButton(
                        icon: "photo.on.rectangle.angled",
                        title: "앨범",
                        subtitle: "앨범 선택",
                        mode: .album,
                        isSelected: uploadMode == .album
                    )
                    
                    modeButton(
                        icon: "photo.stack",
                        title: "사진",
                        subtitle: "개별 선택",
                        mode: .photos,
                        isSelected: uploadMode == .photos
                    )
                }
                
                HStack(spacing: 10) {
                    modeButton(
                        icon: "video.fill",
                        title: "영상",
                        subtitle: "영상 선택",
                        mode: .videos,
                        isSelected: uploadMode == .videos
                    )
                    
                    modeButton(
                        icon: "doc.fill",
                        title: "문서",
                        subtitle: "문서 선택",
                        mode: .documents,
                        isSelected: uploadMode == .documents
                    )
                }
            }
        }
        .padding(16)
        .background(GlassCard())
    }
    
    private func modeButton(icon: String, title: String, subtitle: String, mode: UploadMode, isSelected: Bool) -> some View {
        let theme = AppTheme.UploadModeTheme.from(mode)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                uploadMode = mode
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? theme.gradient : .white.opacity(0.5))
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? theme.accentColor.opacity(0.8) : .white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSelected
                    ? theme.accentColor.opacity(0.15)
                    : Color.white.opacity(0.05)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? theme.gradient : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - 업로드 액션 카드
    private var uploadActionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch uploadMode {
            case .album:
                albumUploadSection
            case .photos:
                photosUploadSection
            case .videos:
                videosUploadSection
            case .documents:
                documentsUploadSection
            }
        }
        .padding(18)
        .background(GlassCard())
    }
    
    private var albumUploadSection: some View {
        let theme = AppTheme.UploadModeTheme.album
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.gradient)
                Text("앨범 선택 업로드")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("사진 앨범을 선택하면 자동으로 폴더명이 생성되고 파일명이 변환됩니다.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.gracefulGold.opacity(0.7))
                .lineSpacing(3)
            
            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "folder", text: "폴더: ZAKAR/일반/2026/일반_날짜_이벤트명/")
                infoRow(icon: "doc.text", text: "파일: 원본명.jpg")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accentColor.opacity(0.06))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentColor.opacity(0.2), lineWidth: 0.5)
            )
            
            Button {
                photoManager.fetchAlbums()
                showAlbumPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .semibold))
                    Text("앨범 선택하기")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.gradient)
                )
                .shadow(color: theme.glowColor, radius: 8, x: 0, y: 4)
            }
        }
    }
    
    private var photosUploadSection: some View {
        let theme = AppTheme.UploadModeTheme.photos
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.stack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.gradient)
                Text("개별 사진 선택 업로드")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("원하는 사진만 선택하여 업로드합니다. 폴더명과 이벤트명을 직접 입력할 수 있습니다.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.gracefulGold.opacity(0.7))
                .lineSpacing(3)
            
            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "folder", text: "폴더: ZAKAR/일반/2026/일반_날짜_이벤트명/")
                infoRow(icon: "doc.text", text: "파일: 원본명.jpg")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accentColor.opacity(0.06))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentColor.opacity(0.2), lineWidth: 0.5)
            )
            
            Button {
                showPhotoPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 14, weight: .semibold))
                    Text("사진 선택하기")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.gracefulGold)
                )
                .shadow(color: AppTheme.gracefulGold.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
    }
    
    private var videosUploadSection: some View {
        let theme = AppTheme.UploadModeTheme.photos
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold)
                Text("영상 선택 업로드")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("영상 파일을 선택하여 업로드합니다. MP4, MOV 등의 영상 파일을 지원합니다.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.gracefulGold.opacity(0.7))
                .lineSpacing(3)
            
            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "folder", text: "폴더: ZAKAR/일반/2026/일반_날짜_이벤트명/")
                infoRow(icon: "doc.text", text: "파일: 원본명.mp4")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accentColor.opacity(0.06))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentColor.opacity(0.2), lineWidth: 0.5)
            )
            
            Button {
                showVideoPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("영상 선택하기")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.gracefulGold)
                )
                .shadow(color: AppTheme.gracefulGold.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
    }
    
    private var documentsUploadSection: some View {
        let theme = AppTheme.UploadModeTheme.photos
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold)
                Text("문서 선택 업로드")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("문서 파일을 선택하여 업로드합니다. PDF, Word, Excel, PowerPoint 등을 지원합니다.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.gracefulGold.opacity(0.7))
                .lineSpacing(3)
            
            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "folder", text: "폴더: ZAKAR/일반/2026/일반_날짜_이벤트명/")
                infoRow(icon: "doc.text", text: "파일: 원본명.pdf")
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accentColor.opacity(0.06))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accentColor.opacity(0.2), lineWidth: 0.5)
            )
            
            Button {
                showDocumentPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("문서 선택하기")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.gracefulGold)
                )
                .shadow(color: AppTheme.gracefulGold.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    // Google Drive 연동을 위한 개발자 안내 카드
    private var googleDriveGuideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("연동 설정 안내", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 6) {
                guideStep(num: "1", text: "Google Cloud Console → 새 프로젝트 생성")
                guideStep(num: "2", text: "OAuth 2.0 클라이언트 ID → iOS 앱 선택")
                guideStep(num: "3", text: "번들 ID: 앱과 동일하게 입력")
                guideStep(num: "4", text: "발급된 Client ID를 GoogleDriveService.swift에 입력")
            }
        }
        .padding(16)
        .background(GlassCard(cornerRadius: 16))
    }

    private func guideStep(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.blue.opacity(0.8))
                .frame(width: 16, height: 16)
                .background(Color.blue.opacity(0.15))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(2)
        }
    }
    
    // MARK: - Google Drive 업로드 큐 카드
    private var driveQueueCard: some View {
        let doneCount = googleDrive.uploadQueue.filter { $0.status == .done }.count
        let uploadingCount = googleDrive.uploadQueue.filter { $0.status == .uploading }.count
        let totalProgress = Double(doneCount) / Double(max(googleDrive.uploadQueue.count, 1))
        
        return VStack(alignment: .leading, spacing: 12) {
            // 헤더
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.gracefulGold)
                    Text("업로드 현황")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    if uploadingCount > 0 {
                        ProgressView()
                            .tint(AppTheme.gracefulGold)
                            .scaleEffect(0.7)
                    }
                    Text("\(doneCount) / \(googleDrive.uploadQueue.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(uploadingCount > 0 ? AppTheme.gracefulGold : .green.opacity(0.9))
                }
            }
            
            // 전체 진행률 바
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.gracefulGold, AppTheme.goldenRose],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * totalProgress, height: 6)
                            .animation(.easeInOut(duration: 0.3), value: totalProgress)
                    }
                }
                .frame(height: 6)
                
                if uploadingCount > 0 {
                    Text("\(uploadingCount)개 업로드 중...")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))

            // 업로드 항목 리스트 (최대 5개만 표시)
            ForEach(googleDrive.uploadQueue.prefix(5)) { item in
                DriveUploadRow(item: item)
            }
            
            // 더 많은 항목이 있으면 표시
            if googleDrive.uploadQueue.count > 5 {
                Text("외 \(googleDrive.uploadQueue.count - 5)개 항목...")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.leading, 30)
            }
            
            // 완료 항목 정리 버튼
            if googleDrive.uploadQueue.contains(where: { $0.status == .done }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        googleDrive.clearCompletedUploads()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                        Text("완료 항목 정리")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.gracefulGold.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.gracefulGold.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(GlassCard())
    }
}

// MARK: - NAS 업로드 항목 행 (진행률 포함)
struct NASUploadRow: View {
    let item: NASUploadItem

    var statusColor: Color {
        switch item.status {
        case .waiting:   return .white.opacity(0.3)
        case .uploading: return .blue
        case .done:      return .green
        case .failed:    return .red
        }
    }

    var statusIcon: String {
        switch item.status {
        case .waiting:   return "clock"
        case .uploading: return "arrow.up.circle"
        case .done:      return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.filename)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Text(item.size)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                if item.status == .uploading {
                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue.opacity(0.8))
                } else if item.status == .done {
                    Text("완료")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green.opacity(0.8))
                }
            }

            // 진행률 바
            if item.status == .uploading || item.status == .done {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.status == .done ? Color.green : Color.blue)
                            .frame(width: geo.size.width * item.progress, height: 3)
                            .animation(.easeInOut(duration: 0.15), value: item.progress)
                    }
                }
                .frame(height: 3)
                .padding(.leading, 30)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

// MARK: - Google Drive 업로드 항목 행
struct DriveUploadRow: View {
    let item: DriveUploadItem

    var statusColor: Color {
        switch item.status {
        case .waiting:   return .white.opacity(0.4)
        case .uploading: return AppTheme.gracefulGold
        case .done:      return .green
        case .failed:    return .red
        }
    }

    var statusIcon: String {
        switch item.status {
        case .waiting:   return "clock"
        case .uploading: return "arrow.up.circle.fill"
        case .done:      return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }
    
    var fileIcon: String {
        let ext = (item.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif":
            return "photo.fill"
        case "mp4", "mov", "m4v":
            return "video.fill"
        case "pdf":
            return "doc.fill"
        case "doc", "docx":
            return "doc.text.fill"
        case "xls", "xlsx":
            return "tablecells.fill"
        case "ppt", "pptx":
            return "play.rectangle.fill"
        default:
            return "doc.fill"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // 파일 타입 아이콘
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: fileIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.size)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                        
                        if item.status == .uploading {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                            Text("\(Int(item.progress * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                        }
                    }
                }

                Spacer()

                // 상태 아이콘
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(statusColor)
                    .symbolEffect(.pulse, options: .repeating, value: item.status == .uploading)
            }

            // 진행률 바
            if item.status == .uploading || item.status == .done {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(
                                item.status == .done 
                                    ? LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [AppTheme.gracefulGold, AppTheme.goldenRose], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: geo.size.width * item.progress, height: 4)
                            .animation(.easeInOut(duration: 0.2), value: item.progress)
                    }
                }
                .frame(height: 4)
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(item.status == .uploading ? 0.03 : 0.01))
        )
    }
}

#Preview {
    ArchiveView()
        .environmentObject(PhotoManager())
}
