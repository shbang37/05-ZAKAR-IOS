import SwiftUI
import Photos
import AppKit

// ============================================================
// FavoritesView — 즐겨찾기한 사진 그리드
// F(리뷰·그룹 비교)로 표시한 사진이 실제로 들어갔는지 여기서 확인한다.
// 사진 앱의 "즐겨찾는 항목"과 같은 값(PHAsset.isFavorite)을 본다.
// ============================================================

struct FavoritesView: View {
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
        .task(id: appState.libraryRevision) { await reload() }   // F로 바뀌면 다시 읽는다
    }

    private var header: some View {
        HStack {
            Text("즐겨찾기")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(assets.count)장")
                .font(.callout)
                .foregroundStyle(AppTheme.subText)
            Spacer()
            Text("하트를 누르면 즐겨찾기가 해제됩니다")
                .font(.caption)
                .foregroundStyle(AppTheme.subText.opacity(0.7))
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
                        // 하트를 누르면 즐겨찾기 해제 — 이 화면에서 바로 정리할 수 있게
                        .overlay(alignment: .bottomLeading) {
                            FavoriteHeart {
                                appState.setFavorite(asset.localIdentifier, to: false)
                            }
                            .padding(4)
                        }
                        .draggable(asset.localIdentifier)
                        .accessibilityLabel("즐겨찾기한 사진")
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
                    MacPlaceholderView(systemImage: "heart",
                                       title: "즐겨찾기한 사진이 없습니다",
                                       subtitle: "리뷰나 그룹 비교에서 F를 누르면 여기에 모입니다.")
                }
            }
        }
    }

    private func reload() async {
        isLoading = true
        let fetched: [PHAsset] = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "favorite == YES")
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            var list: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in list.append(asset) }
            return list
        }.value
        assets = fetched
        isLoading = false
    }
}
