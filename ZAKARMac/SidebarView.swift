import SwiftUI
import Photos

// ============================================================
// SidebarView — NavigationSplitView 사이드바
// 섹션: 라이브러리(모든 사진[리뷰 포함]/유사 그룹) · 모음(즐겨찾기/앨범 ⌘1~9) · 휴지통(골드 배지)
// 하단: 유사 분석 진행 표시. 사이드바 vibrancy는 .listStyle(.sidebar) 기본 제공.
// ============================================================

struct SidebarView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @EnvironmentObject var flyController: FlyToTrashController
    @Binding var selection: MacDestination?
    @State private var favoriteCount = 0

    var body: some View {
        List(selection: $selection) {
            Section("라이브러리") {
                // 리뷰는 "모든 사진" 안에 있다 (더블클릭·⏎로 들어감)
                Label("모든 사진", systemImage: "photo.on.rectangle")
                    .badge(photoManager.allPhotos.count)
                    .tag(MacDestination.allPhotos)

                Label("유사 그룹", systemImage: "square.on.square")
                    .badge(photoManager.groupedPhotos.count)
                    .tag(MacDestination.similarGroups)
            }

            Section("모음") {
                HStack {
                    Label("즐겨찾기", systemImage: "heart")
                    Spacer()
                    if favoriteCount > 0 {
                        Text("\(favoriteCount)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.subText.opacity(0.8))
                    }
                }
                .tag(MacDestination.favorites)

                ForEach(Array(photoManager.albums.enumerated()), id: \.element.id) { index, album in
                    HStack {
                        Label(album.title, systemImage: "folder")
                        Spacer()
                        Text("\(album.assetCount)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.subText.opacity(0.8))
                        if index < 9 {
                            Text("⌘\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.subText)
                        }
                    }
                    .tag(MacDestination.album(id: album.id))
                    .dropDestination(for: String.self) { ids, _ in   // 드래그한 사진을 앨범에 추가
                        let assets = fetchAssets(ids)
                        guard !assets.isEmpty else { return false }
                        photoManager.addToAlbumUndoably(assets, album: album, undo: appState.undo,
                                                        completion: { success in
                            appState.showToast(success ? "‘\(album.title)’ 앨범에 \(assets.count)장 추가"
                                                       : "‘\(album.title)’ 앨범에 넣지 못했습니다")
                        }, onChange: {
                            photoManager.fetchUserAlbumsForMac()
                            appState.bumpLibrary()
                        })
                        return true
                    }
                }

                Button {
                    appState.showNewAlbum = true
                } label: {
                    Label("새 앨범…", systemImage: "plus")
                        .foregroundStyle(AppTheme.subText)
                }
                .buttonStyle(.plain)
            }

            Section {
                HStack {
                    Label("휴지통", systemImage: "trash")
                        .reportTrashIconFrame(to: flyController)   // 흡입 도착 지점
                    Spacer()
                    if !photoManager.trashAssets.isEmpty {
                        GoldBadge(count: photoManager.trashAssets.count, pulse: flyController.badgePulse)
                    }
                }
                .tag(MacDestination.trash)
                .dropDestination(for: String.self) { ids, _ in   // 드래그한 사진을 휴지통에 등록
                    let assets = fetchAssets(ids)
                    guard !assets.isEmpty else { return false }
                    photoManager.addToTrashUndoably(assets, undo: appState.undo)
                    appState.showToast("휴지통으로 \(assets.count)장 — ⌘Z로 되돌릴 수 있어요")
                    return true
                }
            }
        }
        .listStyle(.sidebar)
        .task(id: appState.libraryRevision) {       // F로 즐겨찾기가 바뀌면 숫자도 따라 바뀐다
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "favorite == YES")
            favoriteCount = PHAsset.fetchAssets(with: options).count
        }
        .safeAreaInset(edge: .bottom) {
            if photoManager.isAnalyzing {
                AnalysisProgressIndicator(groupCount: photoManager.groupedPhotos.count)
            }
        }
    }

    /// 드롭된 id → PHAsset. 모든 사진에서 여러 장을 끌면 id들이 줄바꿈으로 이어져 한 덩어리로 온다.
    /// 끈 순서(격자 순서)를 지킨다 — fetchAssets 결과 순서는 보장되지 않는다.
    private func fetchAssets(_ items: [String]) -> [PHAsset] {
        var seen = Set<String>()
        let ids = items.flatMap { $0.split(separator: "\n").map(String.init) }
            .filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return [] }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        fetch.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return ids.compactMap { byID[$0] }
    }
}

/// 휴지통 골드 배지 (시스템 배지 대신 디자인 토큰 적용) — 흡입 도착 시 펄스
private struct GoldBadge: View {
    let count: Int
    let pulse: Int
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.deepPurple)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppTheme.gracefulGold))
            .scaleEffect(scale)
            .onChange(of: pulse) { _, _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { scale = 1.35 }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.12)) { scale = 1.0 }
            }
            .accessibilityLabel("휴지통 \(count)장")
    }
}

/// 유사 분석 진행 표시 — % 발행이 없어 발견 그룹 수로 진행을 알린다 (progressive).
private struct AnalysisProgressIndicator: View {
    let groupCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("유사 분석 중… \(groupCount)개 그룹")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
            }
            Text("완료된 그룹부터 바로 정리할 수 있어요")
                .font(.caption2)
                .foregroundStyle(AppTheme.subText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
    }
}
