import SwiftUI
import Photos

// ============================================================
// GroupCompareView — 그룹 비교 모드 (차별화 기능)
// 헤더(진행률) + 사진 카드(≤5장 1행, 초과 시 격자) + 액션 바.
// 키보드: ⏎ 정리 · R 대표 지정 · S 건너뛰기 · ←→ 포커스 · ⌫ 삭제 토글 · F 즐겨찾기 · Space 확대.
// ============================================================

struct GroupCompareView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @EnvironmentObject var flyController: FlyToTrashController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 포커스와 무관하게 동작하도록 앱 소유 UndoManager 사용 (MacAppState 주석 참고)
    private var undoManager: UndoManager { appState.undo }
    @StateObject private var session = GroupCompareSession()

    @State private var focusedIndex = 0        // 현재 그룹 내 포커스된 카드
    @State private var gridWidth: CGFloat = 900 // 카드 크기 계산용 가용 폭
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
            .background(
                // 카드 크기를 계산할 가용 폭 측정 (padding 24×2 제외)
                GeometryReader { geo in
                    Color.clear
                        .onAppear { gridWidth = geo.size.width - 48 }
                        .onChange(of: geo.size.width) { _, w in gridWidth = w - 48 }
                }
            )
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
        .macKeys(for: .similarGroups) { handleKey($0, $1, decision) }   // keyCode 기반 — 한글 입력기·포커스 무관
    }

    // MARK: - 키보드 동작

    /// 키 처리 — QuickLook이 떠 있으면 오버레이 동작이 우선.
    private func handleKey(_ key: MacKey, _ mods: NSEvent.ModifierFlags, _ decision: GroupDecision) -> Bool {
        // ⌘Z/⌘⇧Z는 여기서 처리 (메뉴 단축키는 입력기 상태에 흔들릴 수 있음)
        if mods.zakarIsCommandOnly, key == .letterZ {
            mods.contains(.shift) ? undoManager.redo() : undoManager.undo()
            return true
        }
        guard mods.zakarIsPlainKey else { return false }   // 나머지 ⌘·⌥ 조합은 시스템/메뉴에 양보

        if let ql = appState.quickLook {
            switch key {
            case .leftArrow:
                if ql.index > 0 { appState.quickLook?.index = ql.index - 1; focusedIndex = ql.index - 1 }
            case .rightArrow:
                if ql.index < decision.assets.count - 1 {
                    appState.quickLook?.index = ql.index + 1
                    focusedIndex = ql.index + 1
                }
            case .space, .escape:
                appState.quickLook = nil
                contentFocused = true
            default:
                break
            }
            return true
        }

        switch key {
        case .enter:      performClean(keepOnlyRepresentative: true)
        case .space:      openQuickLook(decision)
        case .leftArrow:  moveFocus(-1, in: decision)
        case .rightArrow: moveFocus(1, in: decision)
        case .delete:     toggleFocusedDelete(decision)
        case .letterS:    session.skipCurrent()
        case .letterR:    makeFocusedRepresentative(decision)
        case .letterF:    favoriteFocused(decision)
        default: return false
        }
        return true
    }

    private func moveFocus(_ delta: Int, in decision: GroupDecision) {
        let count = decision.assets.count
        guard count > 0 else { return }
        focusedIndex = min(max(0, focusedIndex + delta), count - 1)
    }

    private func openQuickLook(_ decision: GroupDecision) {
        appState.quickLook = QuickLookRequest(assets: decision.assets,
                                              index: min(focusedIndex, max(0, decision.assets.count - 1)))
    }

    /// R — 포커스된 카드를 대표로 지정 (기존 대표는 자동으로 삭제 후보가 된다)
    private func makeFocusedRepresentative(_ decision: GroupDecision) {
        guard decision.assets.indices.contains(focusedIndex) else { return }
        let asset = decision.assets[focusedIndex]
        guard !decision.isRepresentative(asset) else { return }
        session.setRepresentative(asset)
        appState.showToast("대표 사진을 바꿨습니다")
    }

    private func toggleFocusedDelete(_ decision: GroupDecision) {
        guard decision.assets.indices.contains(focusedIndex) else { return }
        session.toggleKeep(decision.assets[focusedIndex])
    }

    private func favoriteFocused(_ decision: GroupDecision) {
        guard decision.assets.indices.contains(focusedIndex) else { return }
        appState.toggleFavorite(decision.assets[focusedIndex].localIdentifier)
    }

    /// 카드 격자.
    /// GeometryReader + 고정 minHeight + 내부 ScrollView 조합을 쓰면 6장 이상일 때
    /// 두 번째 행이 잘려 보였다. 자연 높이로 두고 바깥 ScrollView 하나만 스크롤하게 한다.
    @ViewBuilder
    private func thumbnailGrid(_ decision: GroupDecision) -> some View {
        let n = decision.assets.count
        let spacing: CGFloat = 16

        if n <= 5 {
            // ≤5장: 1행 나란히 (가용 폭에 맞춰 카드 크기 계산)
            let available = max(gridWidth - spacing * CGFloat(max(n - 1, 0)), 120)
            let cardSize = min(340, available / CGFloat(max(n, 1)))
            HStack(spacing: spacing) {
                ForEach(Array(decision.assets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                    card(asset, index: idx, in: decision, size: cardSize)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            // 초과: 격자 — 가용 폭에 맞춰 열 수를 정하고 남는 폭을 카드에 나눠준다
            let maxCard: CGFloat = 240
            let columnCount = max(Int((gridWidth + spacing) / (maxCard + spacing)), 2)
            let cardSize = min(maxCard,
                               (gridWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardSize), spacing: spacing),
                                     count: columnCount),
                      spacing: spacing) {
                ForEach(Array(decision.assets.enumerated()), id: \.element.localIdentifier) { idx, asset in
                    card(asset, index: idx, in: decision, size: cardSize)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func card(_ asset: PHAsset, index: Int, in decision: GroupDecision, size: CGFloat) -> some View {
        ComparableThumbnail(
            asset: asset,
            size: size,
            isRepresentative: decision.isRepresentative(asset),
            isKept: decision.isKept(asset),
            isFavorite: appState.isFavorite(asset.localIdentifier),
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
                Text("⏎ 정리 · R 대표 지정 · ⌫ 삭제 토글 · F 즐겨찾기 · ←→ 이동 · Space 확대 · S 건너뛰기")
                    .font(.caption)
                    .foregroundStyle(AppTheme.subText.opacity(0.7))
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
