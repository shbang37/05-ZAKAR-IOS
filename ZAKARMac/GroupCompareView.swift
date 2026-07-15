import SwiftUI
import Photos

// ============================================================
// GroupCompareView — 그룹 비교 모드 (차별화 기능)
// 헤더(진행률) + 사진 카드(≤5장 1행, 초과 시 격자) + 액션 바.
// 키보드: ⏎ 정리 · S 건너뛰기 · ←→ 포커스 · ⌫ 삭제 토글 · F 즐겨찾기 · Space QuickLook.
// 흡입 애니메이션은 Phase 5, Undo는 Phase 7.
// ============================================================

struct GroupCompareView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var flyController: FlyToTrashController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @StateObject private var session = GroupCompareSession()

    @State private var focusedIndex = 0        // 현재 그룹 내 포커스된 카드
    @State private var showQuickLook = false
    @State private var quickLookIndex = 0
    @FocusState private var contentFocused: Bool

    /// 흡입 발사(정리 전, 카드 프레임 유효할 때) 후 데이터 커밋 — 비차단
    private func performClean(keepOnlyRepresentative: Bool) {
        guard let d = session.current else { return }
        let keep = keepOnlyRepresentative ? [d.representative.localIdentifier] : d.keepSet
        let deleteAssets = d.assets.filter { !keep.contains($0.localIdentifier) }
        flyController.fly(assets: deleteAssets, reduceMotion: reduceMotion)
        session.cleanCurrent(keepOnlyRepresentative: keepOnlyRepresentative, undoManager: undoManager)
    }

    var body: some View {
        Group {
            if let decision = session.current {
                content(decision)
            } else if session.reachedEnd {
                if photoManager.isAnalyzing {
                    MacPlaceholderView(systemImage: "square.on.square",
                                       title: "다음 그룹 분석 중…",
                                       subtitle: "완료된 그룹부터 바로 정리할 수 있어요")
                } else {
                    completionView
                }
            } else {
                MacPlaceholderView(systemImage: "square.on.square",
                                   title: photoManager.isAnalyzing ? "유사 사진 분석 중…" : "유사 그룹이 없습니다",
                                   subtitle: photoManager.isAnalyzing ? "완료된 그룹부터 바로 정리할 수 있어요" : "정리할 유사 사진 그룹이 발견되지 않았습니다.")
            }
        }
        .task { session.syncGroups(photoManager.groupedPhotos, photoManager: photoManager) }
        .onChange(of: photoManager.groupedPhotos.count) { _, _ in
            session.syncGroups(photoManager.groupedPhotos, photoManager: photoManager)
        }
        .onChange(of: session.currentIndex) { _, _ in focusedIndex = 0 }   // 그룹 전환 시 포커스 리셋
    }

    // MARK: - 본문

    private func content(_ decision: GroupDecision) -> some View {
        VStack(spacing: 0) {
            GroupProgressHeader(current: session.currentIndex + 1,
                                total: session.decisions.count,
                                cleanedCount: session.cleanedCount,
                                savedMB: session.savedMB)
            Divider().overlay(AppTheme.divider)

            ScrollView {
                thumbnailGrid(decision)
                    .padding(24)
                    .id(session.currentIndex)   // 그룹 전환 시 재생성 → 트랜지션
                    .transition(reduceMotion ? .identity
                                : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                              removal: .opacity))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: session.currentIndex)

            GroupActionBar(deleteCount: decision.assets.count - 1,
                           selectedDeleteCount: decision.deleteCount,
                           onKeepRepresentative: { performClean(keepOnlyRepresentative: true) },
                           onApplySelection: { performClean(keepOnlyRepresentative: false) },
                           onSkip: { session.skipCurrent() })
        }
        // 콘텐츠 영역 단일 focusable — 텍스트 필드가 없으므로 키가 항상 여기로 전달됨
        .focusable()
        .focused($contentFocused)
        .focusEffectDisabled()
        .onAppear { contentFocused = true }
        .onKeyPress(.return) { performClean(keepOnlyRepresentative: true); return .handled }
        .onKeyPress(.space) { openQuickLook(decision); return .handled }
        .onKeyPress(.leftArrow) { moveFocus(-1, in: decision); return .handled }
        .onKeyPress(.rightArrow) { moveFocus(1, in: decision); return .handled }
        .onKeyPress(.delete) { toggleFocusedDelete(decision); return .handled }
        .onKeyPress(KeyEquivalent("s")) { session.skipCurrent(); return .handled }
        .onKeyPress(KeyEquivalent("f")) { favoriteFocused(decision); return .handled }
        .overlay {
            if showQuickLook {
                QuickLookOverlay(assets: decision.assets,
                                 index: $quickLookIndex,
                                 onClose: { showQuickLook = false; contentFocused = true })
            }
        }
    }

    // MARK: - 키보드 동작

    private func moveFocus(_ delta: Int, in decision: GroupDecision) {
        let count = decision.assets.count
        guard count > 0 else { return }
        focusedIndex = min(max(0, focusedIndex + delta), count - 1)
    }

    private func openQuickLook(_ decision: GroupDecision) {
        quickLookIndex = min(focusedIndex, max(0, decision.assets.count - 1))
        showQuickLook = true
    }

    private func toggleFocusedDelete(_ decision: GroupDecision) {
        guard decision.assets.indices.contains(focusedIndex) else { return }
        session.toggleKeep(decision.assets[focusedIndex])
    }

    private func favoriteFocused(_ decision: GroupDecision) {
        guard decision.assets.indices.contains(focusedIndex) else { return }
        let asset = decision.assets[focusedIndex]
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetChangeRequest(for: asset)
            req.isFavorite = !asset.isFavorite
        }, completionHandler: { _, _ in })
    }

    @ViewBuilder
    private func thumbnailGrid(_ decision: GroupDecision) -> some View {
        GeometryReader { geo in
            let n = decision.assets.count
            let spacing: CGFloat = 16
            if n <= 5 {
                // ≤5장: 1행 나란히 (가용 폭에 맞춰 카드 크기 계산)
                let cardSize = min(340, (geo.size.width - spacing * CGFloat(n - 1)) / CGFloat(max(n, 1)))
                HStack(spacing: spacing) {
                    ForEach(Array(decision.assets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                        card(asset, index: idx, in: decision, size: cardSize)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                // 초과: 격자
                let cardSize: CGFloat = 220
                let columns = [GridItem(.adaptive(minimum: cardSize, maximum: cardSize), spacing: spacing)]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(Array(decision.assets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                            card(asset, index: idx, in: decision, size: cardSize)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 380)
    }

    private func card(_ asset: PHAsset, index: Int, in decision: GroupDecision, size: CGFloat) -> some View {
        ComparableThumbnail(
            asset: asset,
            size: size,
            isRepresentative: decision.isRepresentative(asset),
            isKept: decision.isKept(asset),
            onToggle: { focusedIndex = index; session.toggleKeep(asset) },
            onMakeRepresentative: { session.setRepresentative(asset) }
        )
        // 키보드 포커스 링 (골드 대표/선택과 구분되는 흰 링)
        .overlay {
            if index == focusedIndex {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    .padding(-3)
            }
        }
        .reportCardFrame(id: asset.localIdentifier, to: flyController)   // 흡입 시작 위치
    }

    // MARK: - 완료 화면

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.gracefulGold)
            Text("모든 그룹을 정리했어요")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text("이번 세션 \(session.cleanedCount)장 정리 · \(String(format: "%.0f", session.savedMB))MB 확보")
                .font(.title3)
                .foregroundStyle(AppTheme.subText)
            Text("휴지통을 비우면 실제 저장 공간이 확보됩니다.")
                .font(.callout)
                .foregroundStyle(AppTheme.subText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 진행 헤더

private struct GroupProgressHeader: View {
    let current: Int
    let total: Int
    let cleanedCount: Int
    let savedMB: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("그룹 \(current)/\(total)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if cleanedCount > 0 {
                    Text("이번 세션 \(cleanedCount)장 정리 · \(String(format: "%.0f", savedMB))MB 확보")
                        .font(.callout)
                        .foregroundStyle(AppTheme.gracefulGold)
                }
            }
            ProgressView(value: Double(current), total: Double(max(total, 1)))
                .tint(AppTheme.gracefulGold)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - 액션 바

private struct GroupActionBar: View {
    let deleteCount: Int            // 대표만 남길 때 삭제 장수 (Primary)
    let selectedDeleteCount: Int    // 현재 선택 기준 삭제 장수 (Secondary)
    let onKeepRepresentative: () -> Void
    let onApplySelection: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSkip) {
                Text("이 그룹 건너뛰기  S")
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.subText)

            Spacer()

            Button(action: onApplySelection) {
                Text("선택대로 반영 (\(selectedDeleteCount)장)")
                    .fontWeight(.medium)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.gracefulGold, lineWidth: 1.5))
                    .foregroundStyle(AppTheme.gracefulGold)
            }
            .buttonStyle(.plain)

            Button(action: onKeepRepresentative) {
                Text("⏎  대표만 남기고 \(deleteCount)장 정리")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.gracefulGold))
                    .foregroundStyle(AppTheme.deepPurple)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
}
