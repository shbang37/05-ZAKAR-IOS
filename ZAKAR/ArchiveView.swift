import SwiftUI
import Photos
import Combine
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// MARK: - 통합 아카이브 탭
struct ArchiveView: View {
    @StateObject private var aws = AWSService()
    @EnvironmentObject private var googleDrive: GoogleDriveService
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject private var auth: AuthService

    // MARK: UI 상태
    @State private var selectedProvider: ArchiveProvider = .aws
    @State private var uploadMode: UploadMode = .album
    // AWS 전용 picker 표시 State
    @State private var awsShowAlbumPicker    = false
    @State private var awsShowPhotoPicker    = false
    @State private var awsShowVideoPicker    = false
    @State private var awsShowDocumentPicker = false
    // Google Drive 전용 picker 표시 State
    @State private var gdriveShowAlbumPicker    = false
    @State private var gdriveShowPhotoPicker    = false
    @State private var gdriveShowVideoPicker    = false
    @State private var gdriveShowDocumentPicker = false
    @State private var eventNameInput: String = ""
    @State private var showEventNameSheet = false
    @State private var pendingAssets: [PHAsset] = []
    @State private var pendingFileType: UploadMode = .album
    @State private var selectedFile: AWSArchiveFile?
    @State private var viewURL: String?
    @State private var showFileViewer = false
    @State private var fileActionError: String?

    enum UploadMode {
        case album, photos, videos, documents
        var fileType: String {
            switch self {
            case .album, .photos: return "photo"
            case .videos:         return "video"
            case .documents:      return "document"
            }
        }
        var contentType: String {
            switch self {
            case .album, .photos: return "image/heic"
            case .videos:         return "video/mp4"
            case .documents:      return "application/pdf"
            }
        }
    }

    enum ArchiveProvider: String, CaseIterable {
        case aws         = "AWS"
        case googleDrive = "Google Drive"

        var icon: String {
            switch self {
            case .aws:         return "cloud.fill"
            case .googleDrive: return "arrow.up.to.line.compact"
            }
        }
    }

    /// 업로드 목적지 — picker 뷰에 전달하여 AWS / Google Drive 중 하나를 선택
    enum UploadDestination {
        case aws(service: AWSService, department: String, userId: String)
        case googleDrive
    }

    // MARK: - 현재 사용자 부서 정보
    private var userDepartment: String {
        auth.currentUser?.department ?? "shared"
    }
    private var userDeptKey: String {
        AWSService.s3Key(for: userDepartment)
    }
    private var userRole: String {
        auth.currentUser?.role.rawValue ?? "member"
    }
    private var userId: String {
        auth.currentUser?.id ?? "unknown"
    }

    // MARK: - body
    var body: some View {
        NavigationView {
            ZStack {
                PremiumBackground(style: .warm)

                ScrollView {
                    VStack(spacing: 20) {
                        providerPicker
                            .padding(.horizontal)
                            .padding(.top, 8)

                        if selectedProvider == .aws {
                            awsPanel
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
        // AWS 인증: 앱 시작 시 Firebase 토큰으로 자동 인증
        .task {
            await authenticateAWS()
        }
        // 이벤트명 입력 Sheet
        .sheet(isPresented: $showEventNameSheet) {
            eventNameSheet
        }
        // 파일 뷰어 Sheet
        .sheet(isPresented: $showFileViewer) {
            if let urlStr = viewURL, let url = URL(string: urlStr) {
                SafariViewWrapper(url: url)
            }
        }
        // 파일 액션 오류 알림
        .alert("오류", isPresented: Binding(
            get: { fileActionError != nil },
            set: { if !$0 { fileActionError = nil } }
        )) {
            Button("확인", role: .cancel) { fileActionError = nil }
        } message: {
            Text(fileActionError ?? "")
        }
    }

    // MARK: - AWS 인증
    private func authenticateAWS() async {
        guard !aws.isAuthenticated else { return }
        guard auth.authState == .approved else { return }

        #if canImport(FirebaseAuth)
        if let firebaseUser = Auth.auth().currentUser {
            do {
                let token = try await firebaseUser.getIDToken()
                await aws.authenticate(
                    firebaseToken: token,
                    department:    userDepartment,
                    role:          userRole
                )
                if aws.isAuthenticated {
                    await aws.fetchFiles(department: userDepartment)
                }
            } catch {
                aws.errorMessage = "Firebase 토큰 오류: \(error.localizedDescription)"
            }
        }
        #else
        // Firebase 미설치 시 — 데모 모드로 인증 스킵
        print("[AWSService] Firebase 미설치: 인증 생략 (데모 모드)")
        #endif
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
                            .fill(selectedProvider == provider
                                  ? AppTheme.lightPurple.opacity(0.15)
                                  : Color.clear)
                    )
                }
            }
        }
        .padding(4)
        .background(GlassCard(cornerRadius: 14))
    }

    // =========================================================
    // MARK: - AWS 패널
    // =========================================================
    private var awsPanel: some View {
        VStack(spacing: 16) {
            awsStatusCard

            if aws.isAuthenticated {
                uploadModeSelector
                awsUploadActionCard

                if !aws.uploadQueue.isEmpty {
                    awsQueueCard
                }
            } else if aws.errorMessage != nil {
                awsErrorCard
            } else {
                awsLoadingCard
            }
        }
        .padding(.horizontal)
    }

    // ── 연결 상태 카드 ─────────────────────────────────────────
    private var awsStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 헤더
            HStack {
                ZStack {
                    Circle()
                        .fill(aws.isAuthenticated
                              ? Color.green.opacity(0.15)
                              : Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(aws.isAuthenticated ? .green : .white.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("은혜의 교회 아카이브")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(aws.isAuthenticated
                         ? "연결됨 · AWS S3 (서울)"
                         : (aws.errorMessage != nil ? "연결 실패" : "연결 중..."))
                        .font(.system(size: 12))
                        .foregroundColor(aws.isAuthenticated ? .green.opacity(0.9) : .white.opacity(0.4))
                }

                Spacer()

                if aws.isAuthenticated {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 9, height: 9)
                        .shadow(color: .green.opacity(0.6), radius: 4)
                } else if aws.errorMessage != nil {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                } else {
                    ProgressView().tint(.white.opacity(0.5)).scaleEffect(0.75)
                }
            }

            // 부서 & 권한 정보
            if aws.isAuthenticated, let creds = aws.credentials {
                HStack(spacing: 12) {
                    infoChip(
                        icon: "person.2.fill",
                        label: AWSService.displayName(for: creds.department),
                        color: AppTheme.gracefulGold
                    )
                    infoChip(
                        icon: "key.fill",
                        label: creds.role == "admin" ? "관리자" : (creds.role == "leader" ? "리더" : "일반"),
                        color: AppTheme.lavender
                    )
                    if creds.canDownload {
                        infoChip(icon: "arrow.down.circle.fill", label: "다운로드", color: .green)
                    }
                    Spacer()
                }

                // 마지막 동기화
                if let lastSync = aws.lastSyncAt {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.35))
                        Text("마지막 동기화: \(lastSync, style: .relative) 전")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }

            // 새로고침 버튼
            if aws.isAuthenticated {
                Button {
                    Task { await aws.fetchFiles(department: userDepartment) }
                } label: {
                    HStack(spacing: 6) {
                        if aws.isLoadingFiles {
                            ProgressView().tint(.white).scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(aws.isLoadingFiles ? "불러오는 중..." : "파일 목록 새로고침")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AppTheme.lightPurple.opacity(0.1))
                            .background(.ultraThinMaterial,
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.gracefulGold.opacity(0.3),
                                             AppTheme.lightPurple.opacity(0.2)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .disabled(aws.isLoadingFiles)
            }
        }
        .padding(18)
        .background(GlassCard())
    }

    // ── 파일 브라우저 카드 ─────────────────────────────────────
    private var awsFileBrowserCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold)
                Text("\(AWSService.displayName(for: userDeptKey)) 파일")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(aws.files.count)개")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }

            if aws.isLoadingFiles {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.gracefulGold)
                        .scaleEffect(0.9)
                    Spacer()
                }
                .padding(.vertical, 20)

            } else if aws.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.2))
                    Text("업로드된 파일이 없습니다")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

            } else {
                // 최근 10개 파일 목록
                VStack(spacing: 8) {
                    ForEach(aws.files.prefix(10)) { file in
                        AWSFileRow(
                            file: file,
                            canDownload: aws.credentials?.canDownload ?? false
                        ) { action in
                            Task { await handleFileAction(action, file: file) }
                        }
                    }
                }

                if aws.files.count > 10 {
                    Text("외 \(aws.files.count - 10)개 파일...")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(16)
        .background(GlassCard())
    }

    // ── 오류 카드 ──────────────────────────────────────────────
    private var awsErrorCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.red.opacity(0.7))
            Text("AWS 연결 실패")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(aws.errorMessage ?? "")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Button {
                Task { await authenticateAWS() }
            } label: {
                Text("재연결")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppTheme.purpleGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(GlassCard())
    }

    // ── 로딩 카드 ──────────────────────────────────────────────
    private var awsLoadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.gracefulGold)
                .scaleEffect(1.2)
            Text("AWS 연결 중...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(GlassCard())
    }

    // ── 업로드 모드 선택 ───────────────────────────────────────
    private var uploadModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("업로드 방식 선택")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    modeButton(icon: "photo.on.rectangle.angled", title: "앨범",  subtitle: "앨범 선택",  mode: .album,     isSelected: uploadMode == .album)
                    modeButton(icon: "photo.stack",               title: "사진",  subtitle: "개별 선택",  mode: .photos,    isSelected: uploadMode == .photos)
                }
                HStack(spacing: 10) {
                    modeButton(icon: "video.fill",                title: "영상",  subtitle: "영상 선택",  mode: .videos,    isSelected: uploadMode == .videos)
                    modeButton(icon: "doc.fill",                  title: "문서",  subtitle: "문서 선택",  mode: .documents, isSelected: uploadMode == .documents)
                }
            }
        }
        .padding(16)
        .background(GlassCard())
    }

    private func modeButton(icon: String, title: String, subtitle: String,
                            mode: UploadMode, isSelected: Bool) -> some View {
        let theme = AppTheme.UploadModeTheme.from(mode)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { uploadMode = mode }
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
            .background(isSelected ? theme.accentColor.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? theme.gradient : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // ── AWS 업로드 액션 카드 ───────────────────────────────────
    private var awsUploadActionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            awsUploadSection
        }
        .padding(18)
        .background(GlassCard())
    }

    private var awsUploadSection: some View {
        let theme = AppTheme.UploadModeTheme.from(uploadMode)
        let (icon, title, btnLabel): (String, String, String) = {
            switch uploadMode {
            case .album:     return ("photo.on.rectangle.angled", "앨범 업로드",        "앨범 선택하기")
            case .photos:    return ("photo.stack",               "개별 사진 업로드",   "사진 선택하기")
            case .videos:    return ("video.fill",                "영상 업로드",        "영상 선택하기")
            case .documents: return ("doc.fill",                  "문서 업로드",        "문서 선택하기")
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            // 제목
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.gradient)
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            // 경로 안내
            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "folder",   text: "zakar/\(userDeptKey)/\(Calendar.current.component(.year, from: Date()))/이벤트명/")
                infoRow(icon: "doc.text", text: "ZAKAR_날짜_001.heic")
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

            // 선택 버튼
            Button {
                switch uploadMode {
                case .album:     photoManager.fetchAlbums(); awsShowAlbumPicker    = true
                case .photos:    awsShowPhotoPicker    = true
                case .videos:    awsShowVideoPicker    = true
                case .documents: awsShowDocumentPicker = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                    Text(btnLabel)
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
            .disabled(aws.isUploading)
        }
        // AWS 업로드용 Sheet — destination: .aws 전달
        .sheet(isPresented: $awsShowAlbumPicker) {
            AlbumPickerView(
                destination: .aws(service: aws, department: userDeptKey, userId: userId)
            )
            .environmentObject(photoManager)
            .environmentObject(googleDrive)
            .environmentObject(auth)
        }
        .sheet(isPresented: $awsShowPhotoPicker) {
            PhotoSelectionView(
                destination: .aws(service: aws, department: userDeptKey, userId: userId)
            )
            .environmentObject(photoManager)
            .environmentObject(googleDrive)
            .environmentObject(auth)
        }
        .sheet(isPresented: $awsShowVideoPicker) {
            VideoPickerView(
                destination: .aws(service: aws, department: userDeptKey, userId: userId)
            )
            .environmentObject(photoManager)
            .environmentObject(googleDrive)
            .environmentObject(auth)
        }
        .sheet(isPresented: $awsShowDocumentPicker) {
            // 문서: AWS는 현재 준비 중 — GoogleDrive destination으로 임시 처리
            DocumentPickerView(destination: .googleDrive)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
    }

    // ── AWS 업로드 큐 카드 ─────────────────────────────────────
    private var awsQueueCard: some View {
        let doneCount  = aws.uploadQueue.filter { $0.status == .done }.count
        let total      = aws.uploadQueue.count
        let totalProg  = Double(doneCount) / Double(max(total, 1))

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
                    if aws.isUploading {
                        ProgressView().tint(AppTheme.gracefulGold).scaleEffect(0.7)
                    }
                    Text("\(doneCount) / \(total)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(aws.isUploading ? AppTheme.gracefulGold : .green.opacity(0.9))
                }
            }

            // 전체 진행률 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [AppTheme.gracefulGold, AppTheme.goldenRose],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * totalProg, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: totalProg)
                }
            }
            .frame(height: 6)

            Divider().background(Color.white.opacity(0.1))

            ForEach(aws.uploadQueue.prefix(5)) { item in
                AWSUploadRow(item: item)
            }
            if aws.uploadQueue.count > 5 {
                Text("외 \(aws.uploadQueue.count - 5)개 항목...")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.leading, 30)
            }

            if aws.uploadQueue.contains(where: { $0.status == .done }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { aws.clearCompleted() }
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

    // MARK: - 파일 액션 처리
    enum FileAction { case view, download }

    private func handleFileAction(_ action: FileAction, file: AWSArchiveFile) async {
        do {
            switch action {
            case .view:
                let url = try await aws.getViewURL(fileId: file.fileId, userId: userId)
                viewURL = url
                showFileViewer = true
            case .download:
                let url = try await aws.getDownloadURL(fileId: file.fileId, userId: userId)
                if let urlObj = URL(string: url) {
                    await UIApplication.shared.open(urlObj)
                }
            }
        } catch {
            fileActionError = error.localizedDescription
        }
    }

    // MARK: - 이벤트명 입력 Sheet
    private var eventNameSheet: some View {
        NavigationView {
            ZStack {
                PremiumBackground(style: .warm)
                VStack(spacing: 20) {
                    Text("이벤트명을 입력하세요")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    TextField("예: 수련회, 주일예배, 창립기념", text: $eventNameInput)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .padding(14)
                        .background(GlassCard(cornerRadius: 12))
                    Button {
                        showEventNameSheet = false
                        let assets   = pendingAssets
                        let evtName  = eventNameInput.isEmpty ? "general" : eventNameInput
                        Task {
                            await aws.enqueueAndUpload(
                                assets:     assets,
                                department: userDepartment,
                                eventName:  evtName,
                                userId:     userId
                            )
                        }
                        eventNameInput = ""
                        pendingAssets  = []
                    } label: {
                        Text("업로드 시작")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(AppTheme.purpleGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        showEventNameSheet = false
                        pendingAssets = []
                        eventNameInput = ""
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // =========================================================
    // MARK: - Google Drive 패널 (기존 유지)
    // =========================================================
    private var googleDrivePanel: some View {
        VStack(spacing: 16) {
            googleDriveStatusCard
            if googleDrive.isLinked {
                uploadModeSelector
                googleDriveUploadActionCard

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
        // Google Drive 업로드용 Sheet — destination: .googleDrive 전달
        .sheet(isPresented: $gdriveShowAlbumPicker) {
            AlbumPickerView(destination: .googleDrive)
                .environmentObject(photoManager)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
        .sheet(isPresented: $gdriveShowPhotoPicker) {
            PhotoSelectionView(destination: .googleDrive)
                .environmentObject(photoManager)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
        .sheet(isPresented: $gdriveShowVideoPicker) {
            VideoPickerView(destination: .googleDrive)
                .environmentObject(photoManager)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
        .sheet(isPresented: $gdriveShowDocumentPicker) {
            DocumentPickerView(destination: .googleDrive)
                .environmentObject(googleDrive)
                .environmentObject(auth)
        }
    }

    private var googleDriveStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
            }

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

    private var googleDriveUploadActionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch uploadMode {
            case .album:     albumUploadSection
            case .photos:    photosUploadSection
            case .videos:    videosUploadSection
            case .documents: documentsUploadSection
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
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(theme.gradient)
                Text("앨범 선택 업로드")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            Text("사진 앨범을 선택하면 자동으로 폴더명이 생성되고 파일명이 변환됩니다.")
                .font(.system(size: 13)).foregroundColor(AppTheme.gracefulGold.opacity(0.7)).lineSpacing(3)
            Button { photoManager.fetchAlbums(); gdriveShowAlbumPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 14, weight: .semibold))
                    Text("앨범 선택하기").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.gradient))
                .shadow(color: theme.glowColor, radius: 8, x: 0, y: 4)
            }
        }
    }

    private var photosUploadSection: some View {
        let theme = AppTheme.UploadModeTheme.photos
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "photo.stack").font(.system(size: 14, weight: .semibold)).foregroundColor(theme.gradient)
                Text("개별 사진 선택 업로드").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            Text("원하는 사진만 선택하여 업로드합니다.")
                .font(.system(size: 13)).foregroundColor(AppTheme.gracefulGold.opacity(0.7)).lineSpacing(3)
            Button { gdriveShowPhotoPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack").font(.system(size: 14, weight: .semibold))
                    Text("사진 선택하기").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.gracefulGold))
                .shadow(color: AppTheme.gracefulGold.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
    }

    private var videosUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "video.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(AppTheme.gracefulGold)
                Text("영상 선택 업로드").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            Text("MP4, MOV 등의 영상 파일을 지원합니다.")
                .font(.system(size: 13)).foregroundColor(AppTheme.gracefulGold.opacity(0.7)).lineSpacing(3)
            Button { gdriveShowVideoPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "video.fill").font(.system(size: 14, weight: .semibold))
                    Text("영상 선택하기").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.gracefulGold))
                .shadow(color: AppTheme.gracefulGold.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
    }

    private var documentsUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.fill").font(.system(size: 14, weight: .semibold)).foregroundColor(AppTheme.gracefulGold)
                Text("문서 선택 업로드").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            Text("PDF, Word, Excel, PowerPoint 등을 지원합니다.")
                .font(.system(size: 13)).foregroundColor(AppTheme.gracefulGold.opacity(0.7)).lineSpacing(3)
            Button { gdriveShowDocumentPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill").font(.system(size: 14, weight: .semibold))
                    Text("문서 선택하기").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.gracefulGold))
                .shadow(color: AppTheme.gracefulGold.opacity(0.4), radius: 8, x: 0, y: 4)
            }
        }
    }

    private var googleDriveGuideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("연동 설정 안내", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.7))
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

    private var driveQueueCard: some View {
        let doneCount    = googleDrive.uploadQueue.filter { $0.status == .done }.count
        let uploadingCnt = googleDrive.uploadQueue.filter { $0.status == .uploading }.count
        let totalProg    = Double(doneCount) / Double(max(googleDrive.uploadQueue.count, 1))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(AppTheme.gracefulGold)
                    Text("업로드 현황")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
                Spacer()
                HStack(spacing: 4) {
                    if uploadingCnt > 0 { ProgressView().tint(AppTheme.gracefulGold).scaleEffect(0.7) }
                    Text("\(doneCount) / \(googleDrive.uploadQueue.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(uploadingCnt > 0 ? AppTheme.gracefulGold : .green.opacity(0.9))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [AppTheme.gracefulGold, AppTheme.goldenRose],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * totalProg, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: totalProg)
                }
            }
            .frame(height: 6)
            Divider().background(Color.white.opacity(0.1))
            ForEach(googleDrive.uploadQueue.prefix(5)) { item in DriveUploadRow(item: item) }
            if googleDrive.uploadQueue.count > 5 {
                Text("외 \(googleDrive.uploadQueue.count - 5)개 항목...")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.4)).padding(.leading, 30)
            }
            if googleDrive.uploadQueue.contains(where: { $0.status == .done }) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { googleDrive.clearCompletedUploads() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                        Text("완료 항목 정리").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.gracefulGold.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.gracefulGold.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .background(GlassCard())
    }

    // MARK: - 공통 유틸 뷰
    private func infoChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color.opacity(0.9))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
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
}

// MARK: - AWS 파일 행
struct AWSFileRow: View {
    let file: AWSArchiveFile
    let canDownload: Bool
    let onAction: (ArchiveView.FileAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 파일 타입 아이콘
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: file.fileIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(file.originalName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(file.eventName.isEmpty ? "일반" : file.eventName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.2))
                    Text(file.uploadedDate)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer()

            // 버튼
            HStack(spacing: 6) {
                // 보기
                Button { onAction(.view) } label: {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.gracefulGold)
                        .padding(8)
                        .background(AppTheme.gracefulGold.opacity(0.1))
                        .clipShape(Circle())
                }

                // 다운로드 (권한 있을 때만)
                if canDownload {
                    Button { onAction(.download) } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }

    private var iconColor: Color {
        switch file.fileType {
        case "photo":    return AppTheme.gracefulGold
        case "video":    return AppTheme.lavender
        case "document": return .blue.opacity(0.8)
        default:         return .white.opacity(0.5)
        }
    }
}

// MARK: - AWS 업로드 항목 행
struct AWSUploadRow: View {
    let item: AWSUploadItem

    var statusColor: Color {
        switch item.status {
        case .waiting:   return .white.opacity(0.3)
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

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: statusIcon)
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
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                        if item.status == .uploading {
                            Text("•").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                            Text("\(Int(item.progress * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                        }
                    }
                }

                Spacer()

                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            // 진행률 바
            if item.status == .uploading || item.status == .done {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5).fill(Color.white.opacity(0.08)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(item.status == .done
                                  ? LinearGradient(colors: [.green, .green.opacity(0.8)],
                                                   startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [AppTheme.gracefulGold, AppTheme.goldenRose],
                                                   startPoint: .leading, endPoint: .trailing))
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

// MARK: - Google Drive 업로드 행 (기존 유지)
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
        case "jpg", "jpeg", "png", "heic", "heif": return "photo.fill"
        case "mp4", "mov", "m4v":                  return "video.fill"
        case "pdf":                                 return "doc.fill"
        case "doc", "docx":                        return "doc.text.fill"
        case "xls", "xlsx":                        return "tablecells.fill"
        case "ppt", "pptx":                        return "play.rectangle.fill"
        default:                                    return "doc.fill"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: fileIcon)
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(statusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename)
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.9)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.size).font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                        if item.status == .uploading {
                            Text("•").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                            Text("\(Int(item.progress * 100))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.gracefulGold.opacity(0.8))
                        }
                    }
                }
                Spacer()
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(statusColor)
                    .symbolEffect(.pulse, options: .repeating, value: item.status == .uploading)
            }
            if item.status == .uploading || item.status == .done {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5).fill(Color.white.opacity(0.08)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(item.status == .done
                                  ? LinearGradient(colors: [.green, .green.opacity(0.8)],
                                                   startPoint: .leading, endPoint: .trailing)
                                  : LinearGradient(colors: [AppTheme.gracefulGold, AppTheme.goldenRose],
                                                   startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * item.progress, height: 4)
                            .animation(.easeInOut(duration: 0.2), value: item.progress)
                    }
                }
                .frame(height: 4).padding(.leading, 42)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(item.status == .uploading ? 0.03 : 0.01)))
    }
}

// MARK: - Safari View (파일 뷰어용)
import SafariServices

struct SafariViewWrapper: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview {
    ArchiveView()
        .environmentObject(PhotoManager())
        .environmentObject(GoogleDriveService(userID: "preview-user"))
        .environmentObject(AuthService())
}
