import SwiftUI
import Photos
import AppKit

// ============================================================
// AllPhotosGridView — 모든 사진 그리드 (LazyVGrid + 프리페치 + 다중 선택)
// 셀 identity는 localIdentifier 기반 (iOS ContentView 규칙 동일).
// 다중 선택은 클릭 토글(기본); 키보드 다중선택은 Phase 4.
// ============================================================

struct AllPhotosGridView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @StateObject private var prefetcher = ThumbnailPrefetcher()
    @State private var selection: Set<String> = []

    private let cellSize = ThumbnailCache.macGridSize   // 160
    private let spacing: CGFloat = 6

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cellSize, maximum: cellSize), spacing: spacing)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.divider)
            grid
        }
    }

    private var header: some View {
        HStack {
            Text("모든 사진")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(photoManager.allPhotos.count)장")
                .font(.callout)
                .foregroundStyle(AppTheme.subText)
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count)장 선택")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.gracefulGold)
                Button("선택 해제") { selection.removeAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.subText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(photoManager.allPhotos.enumerated()), id: \.element.localIdentifier) { index, asset in
                    cell(asset: asset, index: index)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .center) {
            if photoManager.allPhotos.isEmpty {
                if photoManager.isLoadingList {
                    ProgressView("사진 불러오는 중…")
                        .tint(AppTheme.gracefulGold)
                        .foregroundStyle(.white)
                } else {
                    MacPlaceholderView(systemImage: "photo.on.rectangle.angled",
                                       title: "사진이 없습니다",
                                       subtitle: "사진 접근을 허용하면 라이브러리가 표시됩니다.")
                }
            }
        }
    }

    private func cell(asset: PHAsset, index: Int) -> some View {
        let isSelected = selection.contains(asset.localIdentifier)
        return MacAssetThumbnail(asset: asset, size: cellSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? AppTheme.gracefulGold : Color.white.opacity(0.08),
                                  lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.gracefulGold)
                        .background(Circle().fill(.black.opacity(0.4)))
                        .padding(6)
                }
            }
            .onTapGesture { toggle(asset) }
            .draggable(asset.localIdentifier)   // 앨범/휴지통으로 드래그
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isSelected ? "사진, 선택됨" : "사진")
            .accessibilityAddTraits(.isButton)
            .onAppear {
                prefetcher.update(
                    window: ThumbnailPrefetcher.window(photoManager.allPhotos, around: index),
                    size: cellSize,
                    scale: NSScreen.main?.backingScaleFactor ?? 2.0
                )
            }
    }

    private func toggle(_ asset: PHAsset) {
        let key = asset.localIdentifier
        if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
    }
}
