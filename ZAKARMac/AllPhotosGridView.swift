import SwiftUI
import Photos
import AppKit

// ============================================================
// AllPhotosGridView — 모든 사진 그리드 (LazyVGrid + 프리페치 + 선택)
// 셀 identity는 localIdentifier 기반 (iOS ContentView 규칙 동일).
// 클릭 = 한 장 선택 · ⌘클릭 = 여러 장 더하기/빼기 · 빈 곳 끌기 = 사각형 범위 선택 (Finder·사진 앱과 같은 방식)
// 선택한 사진을 끌면 선택한 **모든** 사진이 함께 앨범·휴지통으로 간다.
// 더블클릭 · ⏎ · 리뷰 시작 버튼 = 그 사진부터 리뷰. 리뷰에서 나오면 마지막으로 본 사진으로 스크롤.
// ============================================================

struct AllPhotosGridView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @StateObject private var prefetcher = ThumbnailPrefetcher()
    @State private var selection: Set<String> = []
    /// 마지막으로 클릭한 사진 — ⏎·리뷰 시작이 여기서부터 시작한다
    @State private var anchorID: String?

    // 사각형 범위 선택
    @State private var cellFrames = CellFrameStore()
    @State private var marquee: CGRect?
    @State private var marqueeBase: Set<String> = []   // ⌘를 누르고 끌면 기존 선택에 더한다
    @State private var viewportHeight: CGFloat = 0
    private static let gridSpace = "allPhotosGrid"

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
            if selection.isEmpty {
                Text("클릭 선택 · ⌘클릭 추가 · 빈 곳 끌어 범위 선택 · 더블클릭 리뷰")
                    .font(.caption)
                    .foregroundStyle(AppTheme.subText.opacity(0.7))
            } else {
                Text("\(selection.count)장 선택")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.gracefulGold)
                Button { selection.removeAll(); anchorID = nil } label: {
                    Text("선택 해제")
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.subText)
            }
            Button { startReview() } label: {
                Label("리뷰 시작  ⏎", systemImage: "eye")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(AppTheme.gracefulGold))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.deepPurple)
            .disabled(photoManager.allPhotos.isEmpty)
            .help("선택한 사진부터 한 장씩 보기 (없으면 첫 사진부터)")
            .padding(.leading, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(Array(photoManager.allPhotos.enumerated()), id: \.element.localIdentifier) { index, asset in
                        cell(asset: asset, index: index)
                    }
                }
                .padding(16)
                // 사진이 적어도 화면 아래 빈 곳까지 끌기·클릭을 받도록
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
                // 사진 사이·주변 빈 곳은 셀이 클릭을 받지 않으므로 이 배경이 받는다
                .background { marqueeSurface }
                .overlay(alignment: .topLeading) { marqueeRectangle }
                .coordinateSpace(name: Self.gridSpace)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .task { await focusAfterReview(proxy) }
        }
        .macKeys(for: .allPhotos) { key, mods in
            guard key == .enter, mods.zakarIsPlainKey else { return false }
            startReview()
            return true
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
            .overlay(alignment: .bottomLeading) {
                if appState.isFavorite(asset.localIdentifier) {
                    FavoriteHeart().padding(4)
                }
            }
            // 한 번 클릭은 즉시 반응해야 하므로 simultaneous로 단다
            // (onTapGesture(count: 1)을 같이 쓰면 더블클릭을 기다리느라 클릭마다 0.3초씩 늦는다)
            .onTapGesture(count: 2) { appState.startReview(at: index) }
            .simultaneousGesture(TapGesture().onEnded { click(asset) })
            // 앨범/휴지통으로 드래그 — 선택한 사진을 끌면 선택 전체가 간다 (끄는 순간에 계산)
            .draggable(dragPayload(for: asset)) {
                DragCountBadge(count: dragCount(for: asset))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.gridSpace)) } action: {
                cellFrames.frames[asset.localIdentifier] = $0   // 범위 선택 판정용 (다시 그리지 않도록 참조 타입에 저장)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(asset, isSelected: isSelected))
            .accessibilityAddTraits(.isButton)
            .onAppear {
                prefetcher.update(
                    window: ThumbnailPrefetcher.window(photoManager.allPhotos, around: index),
                    size: cellSize,
                    scale: NSScreen.main?.backingScaleFactor ?? 2.0
                )
            }
    }

    private func accessibilityLabel(_ asset: PHAsset, isSelected: Bool) -> String {
        var parts = ["사진"]
        if isSelected { parts.append("선택됨") }
        if appState.isFavorite(asset.localIdentifier) { parts.append("즐겨찾기") }
        return parts.joined(separator: ", ")
    }

    // MARK: - 사각형 범위 선택

    private var marqueeSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { selection.removeAll(); anchorID = nil }   // 빈 곳 클릭 = 선택 해제
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.gridSpace))
                    .onChanged { value in
                        if marquee == nil {
                            marqueeBase = NSEvent.modifierFlags.contains(.command) ? selection : []
                        }
                        let rect = CGRect(x: min(value.startLocation.x, value.location.x),
                                          y: min(value.startLocation.y, value.location.y),
                                          width: abs(value.location.x - value.startLocation.x),
                                          height: abs(value.location.y - value.startLocation.y))
                        marquee = rect
                        let hit = cellFrames.frames.compactMap { $0.value.intersects(rect) ? $0.key : nil }
                        selection = marqueeBase.union(hit)
                    }
                    .onEnded { _ in
                        marquee = nil
                        // ⏎·리뷰 시작이 범위의 첫 사진부터 시작하도록
                        anchorID = photoManager.allPhotos.first { selection.contains($0.localIdentifier) }?.localIdentifier
                    }
            )
    }

    @ViewBuilder
    private var marqueeRectangle: some View {
        if let rect = marquee {
            Rectangle()
                .fill(AppTheme.gracefulGold.opacity(0.15))
                .overlay(Rectangle().strokeBorder(AppTheme.gracefulGold, lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 여러 장 끌기

    /// 선택된 사진을 끌면 선택 전체(격자 순서), 아니면 그 한 장.
    /// 드롭 쪽(SidebarView)은 줄바꿈으로 나눠 읽는다.
    private func dragPayload(for asset: PHAsset) -> String {
        let id = asset.localIdentifier
        guard selection.contains(id), selection.count > 1 else { return id }
        return photoManager.allPhotos
            .lazy.map(\.localIdentifier)
            .filter { selection.contains($0) }
            .joined(separator: "\n")
    }

    private func dragCount(for asset: PHAsset) -> Int {
        selection.contains(asset.localIdentifier) ? max(selection.count, 1) : 1
    }

    // MARK: - 선택 · 리뷰

    /// 클릭 = 그 사진만 선택, ⌘클릭 = 더하기/빼기
    private func click(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
        anchorID = id
    }

    /// 마지막으로 클릭한 사진 → 선택 중 가장 앞 사진 → 첫 사진 순으로 시작점을 고른다
    private func startReview() {
        let photos = photoManager.allPhotos
        guard !photos.isEmpty else { return }
        var start = 0
        if let anchorID, selection.contains(anchorID),
           let i = photos.firstIndex(where: { $0.localIdentifier == anchorID }) {
            start = i
        } else if !selection.isEmpty,
                  let i = photos.firstIndex(where: { selection.contains($0.localIdentifier) }) {
            start = i
        }
        appState.startReview(at: start)
    }

    /// 리뷰에서 막 나왔으면 마지막으로 본 사진을 선택하고 화면 가운데로 스크롤한다
    private func focusAfterReview(_ proxy: ScrollViewProxy) async {
        guard let index = appState.pendingGridFocus else { return }
        appState.pendingGridFocus = nil
        let photos = photoManager.allPhotos
        guard photos.indices.contains(index) else { return }
        let id = photos[index].localIdentifier
        selection = [id]
        anchorID = id
        try? await Task.sleep(for: .milliseconds(60))   // 격자가 한 번 배치된 뒤 스크롤해야 위치가 맞는다
        proxy.scrollTo(id, anchor: .center)
    }
}

/// 셀 위치 저장소 — @State 값으로 두면 셀이 보일 때마다 격자 전체가 다시 그려진다
private final class CellFrameStore {
    var frames: [String: CGRect] = [:]
}

/// 끄는 동안 커서에 붙는 표시 — 몇 장이 함께 가는지 보여 준다
private struct DragCountBadge: View {
    let count: Int

    var body: some View {
        Label("사진 \(count)장", systemImage: count > 1 ? "photo.stack" : "photo")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(AppTheme.gracefulGold))
            .foregroundStyle(AppTheme.deepPurple)
    }
}
