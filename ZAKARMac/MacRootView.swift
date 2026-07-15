import SwiftUI
import Photos

// ============================================================
// MacRootView — 앱 셸 (NavigationSplitView)
// 사이드바(236pt) + detail. 시작 시 사진 권한 확보 후 라이브러리·앨범·
// 휴지통 로드 및 유사 분석을 트리거한다.
// ============================================================

struct MacRootView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @StateObject private var flyController = FlyToTrashController()
    @State private var authStatus: PHAuthorizationStatus =
        PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(selection: $appState.selection)
                    .navigationSplitViewColumnWidth(min: 216, ideal: 236, max: 300)
            } detail: {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.backgroundGradient.ignoresSafeArea())
            }
            .navigationTitle("ZAKAR")
            .background(albumShortcuts)   // ⌘1~9 앨범 네비게이션 (숨김 버튼)

            // 흡입 애니메이션 전용 최상위 레이어 (SplitView 간 단일 좌표계)
            FlyToTrashLayer(controller: flyController)
        }
        .coordinateSpace(name: "root")
        .environmentObject(flyController)
        .task { await ensureAccessAndLoad() }
    }

    /// ⌘1~9로 앞쪽 9개 앨범으로 이동 (사이드바 ⌘n 힌트와 일치)
    private var albumShortcuts: some View {
        ForEach(Array(photoManager.albums.prefix(9).enumerated()), id: \.element.id) { index, album in
            Button("") { appState.selection = .album(id: album.id) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .hidden()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if authStatus == .denied || authStatus == .restricted {
            MacPlaceholderView(systemImage: "lock.shield",
                               title: "사진 접근이 필요합니다",
                               subtitle: "시스템 설정 → 개인정보 보호 및 보안 → 사진에서 ZAKAR Mac을 허용해 주세요.")
        } else {
            switch appState.selection ?? .allPhotos {
            case .allPhotos:
                AllPhotosGridView()
            case .similarGroups:
                GroupCompareView()
            case .review:
                ReviewView()
            case .favorites:
                MacPlaceholderView(systemImage: "heart",
                                   title: "즐겨찾기",
                                   subtitle: "곧 제공됩니다.")
            case .album(let id):
                MacPlaceholderView(systemImage: "folder",
                                   title: photoManager.albums.first { $0.id == id }?.title ?? "앨범",
                                   subtitle: "앨범 상세는 곧 제공됩니다.")
            case .trash:
                TrashView()
            }
        }
    }

    private func ensureAccessAndLoad() async {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        authStatus = status
        print("[ZAKAR Mac] 사진 권한: \(status.rawValue)")
        guard status == .authorized || status == .limited else { return }

        photoManager.fetchPhotos()
        photoManager.fetchAlbums()
        photoManager.loadTrash()
        photoManager.analyzeSimilaritiesIfNeeded()
    }
}
