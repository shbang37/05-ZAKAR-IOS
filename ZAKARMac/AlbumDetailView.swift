import SwiftUI
import Photos
import AppKit

// ============================================================
// AlbumDetailView — 앨범에 담긴 사진 그리드
// 리뷰 모드의 ⌘1~9 이동이 실제로 반영됐는지 여기서 바로 확인한다.
// ============================================================

struct AlbumDetailView: View {
    let album: AlbumInfo

    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @StateObject private var prefetcher = ThumbnailPrefetcher()
    @State private var assets: [PHAsset] = []
    @State private var isLoading = true

    private let cellSize = ThumbnailCache.macGridSize
    private let spacing: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.divider)
            grid
        }
        // 앨범을 바꾸거나 사진이 추가되면 다시 읽는다
        .task(id: album.id) { await reload() }
        .task(id: appState.albumRevision) { await reload() }   // 앨범 이동·드롭 후 갱신
    }

    private var header: some View {
        HStack {
            Text(album.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(assets.count)장")
                .font(.callout)
                .foregroundStyle(AppTheme.subText)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize), spacing: spacing)],
                      spacing: spacing) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    MacAssetThumbnail(asset: asset, size: cellSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        }
                        .draggable(asset.localIdentifier)
                        .accessibilityLabel("\(album.title) 앨범의 사진")
                        .onAppear {
                            prefetcher.update(
                                window: ThumbnailPrefetcher.window(assets, around: index),
                                size: cellSize,
                                scale: NSScreen.main?.backingScaleFactor ?? 2.0
                            )
                        }
                }
            }
            .padding(16)
        }
        .overlay(alignment: .center) {
            if assets.isEmpty {
                if isLoading {
                    ProgressView().tint(AppTheme.gracefulGold)
                } else {
                    MacPlaceholderView(systemImage: "folder",
                                       title: "앨범이 비어 있습니다",
                                       subtitle: "리뷰 모드에서 ⌘\(shortcutNumber ?? 1)을 누르거나 사진을 이 앨범으로 끌어다 놓으세요.")
                }
            }
        }
    }

    /// 사이드바에 표시되는 ⌘n 번호 (앞쪽 9개만)
    private var shortcutNumber: Int? {
        guard let idx = photoManager.albums.firstIndex(where: { $0.id == album.id }), idx < 9 else { return nil }
        return idx + 1
    }

    private func reload() async {
        isLoading = true
        let collection = album.collection
        let fetched: [PHAsset] = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(in: collection, options: options)
            var list: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in list.append(asset) }
            return list
        }.value
        assets = fetched
        isLoading = false
    }
}
