import Foundation
import Photos
import Combine

// ============================================================
// 그룹 비교 모드 상태 모델
// 핵심 결정: 비대표 사진의 기본 상태 = "삭제" (keepSet 초기값 = {대표} ∪ 즐겨찾기)
// ⏎는 화면에 보이는 선택 그대로 정리한다 — 손대지 않았으면 "대표만 남기기"와 같다.
// 정리 파이프라인: 휴지통 등록(LocalDB)만, PHAsset 실삭제는 휴지통 비우기(Phase 7)에서.
// ============================================================

struct GroupDecision {
    let assets: [PHAsset]
    var representative: PHAsset          // 대표 (엔진 선정, 사용자 교체 가능)
    var keepSet: Set<String>            // 유지할 localIdentifier — 기본값 {대표}
    var skipped: Bool = false
    /// 이 그룹을 정리하며 휴지통에 넣은 사진 — 이전 그룹으로 돌아가 다시 반영할 때
    /// "이번엔 남기기로 한 사진"을 휴지통에서 빼내기 위해 기억한다.
    var trashedIDs: Set<String> = []
    var cleaned: Bool = false
    /// 사용자가 ⌫·↑·↓·R·클릭으로 바꾼 적이 있는지 — 있으면 엔진이 대표를 다시 고르지 않는다
    var userEdited: Bool = false
    /// 사용자가 직접 "유지"로 정한 사진. 다른 화면에서 이미 휴지통에 넣었더라도
    /// 여기서 유지로 정하고 정리하면 휴지통에서 꺼낸다 (화면의 "유지"를 믿고 비우는 일이 없도록).
    var explicitKeep: Set<String> = []

    /// 삭제 예정 장수 (현재 선택 기준)
    var deleteCount: Int { assets.count - keepSet.count }

    func isRepresentative(_ asset: PHAsset) -> Bool {
        asset.localIdentifier == representative.localIdentifier
    }
    func isKept(_ asset: PHAsset) -> Bool {
        keepSet.contains(asset.localIdentifier)
    }
}

@MainActor
final class GroupCompareSession: ObservableObject {
    @Published var decisions: [GroupDecision] = []
    @Published var currentIndex: Int = 0
    @Published var cleanedCount: Int = 0        // 이번 세션 정리한 총 장수
    @Published var savedMB: Double = 0          // 이번 세션 확보 용량(추정)

    private weak var photoManager: PhotoManager?
    private(set) var started = false
    /// 즐겨찾기 여부 (MacAppState.favoriteIDs) — 즐겨찾기한 사진은 기본값을 "유지"로 시작한다
    var isFavorite: ((String) -> Bool)?

    /// 발견된 모든 그룹을 처리했는지 (progressive: 분석이 더 찾을 수 있으므로 뷰에서 isAnalyzing과 함께 판단)
    var reachedEnd: Bool { started && currentIndex >= decisions.count }
    var current: GroupDecision? {
        decisions.indices.contains(currentIndex) ? decisions[currentIndex] : nil
    }

    /// groupedPhotos는 순수 append로 성장(재정렬 없음)하므로, 새로 발견된 그룹만
    /// decisions에 이어붙인다 — 진행 인덱스·사용자 편집을 보존하는 progressive 구성.
    ///
    /// 단, 휴지통 비우기 등으로 사진 목록을 다시 읽으면 분석이 처음부터 다시 돌아 그룹 목록이 바뀐다.
    /// 그때 옛 그룹(지워진 사진 포함)을 붙들고 있으면 안 되므로 겹치는 그룹이 하나라도 다르면 처음부터 다시 맞춘다.
    func syncGroups(_ groups: [[PHAsset]], photoManager: PhotoManager) {
        self.photoManager = photoManager
        if needsReset(for: groups) {
            decisions = []
            currentIndex = 0
            print("ZAKAR Log: [Mac] 유사 그룹이 다시 분석되어 세션을 새로 맞춤")
        }
        guard groups.count > decisions.count else { return }
        let newSlice = groups[decisions.count..<groups.count]
        let newDecisions = newSlice.compactMap { g -> GroupDecision? in
            guard let rep = g.first else { return nil }
            return GroupDecision(assets: g, representative: rep, keepSet: defaultKeep(g, rep: rep))
        }
        decisions.append(contentsOf: newDecisions)
        started = true
        // 현재 인덱스가 가리키는 그룹의 대표를 엔진 점수로 정교화 (idempotent)
        if decisions.indices.contains(currentIndex) {
            let idx = currentIndex
            Task { await refineRepresentative(at: idx) }
        }
    }

    private func needsReset(for groups: [[PHAsset]]) -> Bool {
        if groups.count < decisions.count { return true }
        for i in 0..<min(groups.count, decisions.count)
        where groups[i].map(\.localIdentifier) != decisions[i].assets.map(\.localIdentifier) {
            return true
        }
        return false
    }

    /// 기본 유지 집합 = 대표 + 즐겨찾기 (즐겨찾기한 사진이 ⏎ 한 번에 휴지통으로 가지 않게)
    private func defaultKeep(_ assets: [PHAsset], rep: PHAsset) -> Set<String> {
        var keep: Set<String> = [rep.localIdentifier]
        if let isFavorite {
            keep.formUnion(assets.map(\.localIdentifier).filter(isFavorite))
        }
        return keep
    }

    private func isUntouched(_ index: Int) -> Bool {
        decisions.indices.contains(index) && !decisions[index].cleaned && !decisions[index].userEdited
    }

    /// 엔진 품질 점수로 대표를 정교화 (손대지 않은 그룹만)
    func refineRepresentative(at index: Int) async {
        guard let pm = photoManager, isUntouched(index) else { return }
        // 그사이 즐겨찾기한 사진도 기본 유지에 반영 (그룹이 화면에 올 때마다)
        let current = decisions[index]
        decisions[index].keepSet = defaultKeep(current.assets, rep: current.representative)
        let group = current.assets
        guard let best = await pm.selectBestPhoto(from: group) else { return }
        // 계산하는 동안 사용자가 ⏎로 정리했거나 손댔을 수 있다 — 기다린 뒤 다시 확인해야
        // 이미 휴지통에 들어간 사진이 '대표(유지)'로 바뀌어 보이는 일이 없다.
        guard isUntouched(index), decisions[index].assets.map(\.localIdentifier) == group.map(\.localIdentifier) else { return }
        var d = decisions[index]
        d.representative = best
        d.keepSet = defaultKeep(d.assets, rep: best)
        decisions[index] = d
    }

    // MARK: - 사용자 조작 (모두 ⌘Z로 되돌릴 수 있다)

    /// 유지/삭제 토글 (대표는 항상 유지 — 삭제 불가)
    func toggleKeep(_ asset: PHAsset, undoManager: UndoManager? = nil) {
        guard var d = current else { return }
        let id = asset.localIdentifier
        guard id != d.representative.localIdentifier else { return }   // 대표는 토글 불가
        if d.keepSet.contains(id) {
            d.keepSet.remove(id); d.explicitKeep.remove(id)
        } else {
            d.keepSet.insert(id); d.explicitKeep.insert(id)
        }
        d.userEdited = true
        replaceDecision(at: currentIndex, with: d, actionName: "유지·삭제 전환", undoManager: undoManager)
    }

    /// ↑ 삭제 예정 / ↓ 유지로 **지정**한다 (⌫는 전환). 이미 그 상태면 아무것도 하지 않는다.
    /// 대표는 삭제 예정이 될 수 없으므로 false — 뷰가 안내를 띄운다.
    @discardableResult
    func setKeep(_ asset: PHAsset, keep: Bool, undoManager: UndoManager? = nil) -> Bool {
        guard var d = current else { return false }
        let id = asset.localIdentifier
        if id == d.representative.localIdentifier { return keep }   // 대표는 언제나 유지
        guard d.keepSet.contains(id) != keep else { return true }
        if keep {
            d.keepSet.insert(id); d.explicitKeep.insert(id)
        } else {
            d.keepSet.remove(id); d.explicitKeep.remove(id)
        }
        d.userEdited = true
        replaceDecision(at: currentIndex, with: d, actionName: keep ? "유지 표시" : "삭제 예정 표시",
                        undoManager: undoManager)
        return true
    }

    /// 대표 교체 (교체 대상은 자동으로 유지 집합에 포함)
    func setRepresentative(_ asset: PHAsset, undoManager: UndoManager? = nil) {
        guard var d = current else { return }
        d.representative = asset
        d.keepSet.insert(asset.localIdentifier)
        d.explicitKeep.insert(asset.localIdentifier)
        d.userEdited = true
        replaceDecision(at: currentIndex, with: d, actionName: "대표 지정", undoManager: undoManager)
    }

    /// 그룹 상태를 통째로 바꾸고, 되돌리기엔 바꾸기 전 상태를 등록한다.
    /// 되돌리면 그 그룹으로 화면도 돌아간다 — 다른 그룹을 보다가 ⌘Z를 눌러도 무엇이 바뀌었는지 보이도록.
    private func replaceDecision(at index: Int, with newValue: GroupDecision,
                                 actionName: String, undoManager: UndoManager?) {
        guard decisions.indices.contains(index) else { return }
        let old = decisions[index]
        decisions[index] = newValue
        currentIndex = index
        undoManager?.registerUndo(withTarget: self) { s in
            s.replaceDecision(at: index, with: old, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    // MARK: - 이동

    var canGoBack: Bool { currentIndex > 0 && !decisions.isEmpty }

    /// 이전 그룹으로 (A). 정리한 그룹이면 정리된 상태 그대로 보여 주고, 다시 반영할 수 있다.
    func goBack() {
        guard canGoBack else { return }
        currentIndex = min(currentIndex, decisions.count) - 1
    }

    // MARK: - 정리 실행

    /// 현재 그룹 정리 → 휴지통 등록(LocalDB) + 취향 신호 + 통계, 다음 그룹으로.
    /// keepOnlyRepresentative=false(⏎·기본)면 화면에 보이는 선택대로, true면 선택을 무시하고 대표만 남긴다.
    ///
    /// 이미 정리한 그룹을 다시 반영하면 **차이만** 적용한다:
    /// 새로 삭제로 바뀐 사진은 휴지통에 넣고, 이번엔 남기기로 한 사진은 휴지통에서 뺀다.
    func cleanCurrent(keepOnlyRepresentative: Bool, undoManager: UndoManager? = nil) {
        guard let pm = photoManager, let before = current else { return }
        let index = currentIndex
        let keep = keepOnlyRepresentative ? [before.representative.localIdentifier] : before.keepSet
        let deleteIDs = Set(before.assets.map(\.localIdentifier)).subtracting(keep)
        let inTrash = Set(pm.trashAssets.map(\.localIdentifier))

        let toAdd = before.assets.filter { deleteIDs.contains($0.localIdentifier) && !inTrash.contains($0.localIdentifier) }
        // 휴지통에서 꺼낼 사진: 이 그룹이 전에 넣었는데 이번엔 남기는 사진 +
        // 다른 화면에서 휴지통에 넣었지만 여기서 사용자가 직접 "유지"로 정한 사진
        let toRestore = before.assets.filter {
            let id = $0.localIdentifier
            return inTrash.contains(id) && !deleteIDs.contains(id)
                && (before.trashedIDs.contains(id) || before.explicitKeep.contains(id))
        }

        if !toAdd.isEmpty {
            pm.trashAssets.append(contentsOf: toAdd)   // @Published — 배지 즉시 반영
            pm.recordUserChoice(kept: before.representative, discarded: toAdd)   // 취향 학습 (iOS와 동일 계약)
        }
        if !toRestore.isEmpty {
            let ids = Set(toRestore.map(\.localIdentifier))
            pm.trashAssets.removeAll { ids.contains($0.localIdentifier) }
        }
        if !toAdd.isEmpty || !toRestore.isEmpty { pm.saveTrash() }

        let deltaCount = toAdd.count - toRestore.count
        let deltaMB = Self.estimatedMB(toAdd) - Self.estimatedMB(toRestore)
        cleanedCount = max(0, cleanedCount + deltaCount)
        savedMB = max(0, savedMB + deltaMB)

        var after = before
        after.keepSet = keep                 // 돌아왔을 때 실제로 반영된 상태가 보이도록
        after.trashedIDs = before.trashedIDs
            .subtracting(toRestore.map(\.localIdentifier))
            .union(toAdd.map(\.localIdentifier))
        after.cleaned = true
        decisions[index] = after

        // Undo — 그룹 단위 일괄 복원 (⌘Z 1회에 N장)
        undoManager?.registerUndo(withTarget: self) { s in
            s.revertClean(index: index, before: before, added: toAdd, restored: toRestore,
                          deltaCount: deltaCount, deltaMB: deltaMB,
                          keepOnlyRepresentative: keepOnlyRepresentative, undoManager: undoManager)
        }
        undoManager?.setActionName("그룹 정리")
        advance()
    }

    /// 그룹 정리 취소 — 휴지통을 정리 전으로 되돌리고 그 그룹으로 돌아간다
    private func revertClean(index: Int, before: GroupDecision, added: [PHAsset], restored: [PHAsset],
                             deltaCount: Int, deltaMB: Double,
                             keepOnlyRepresentative: Bool, undoManager: UndoManager?) {
        guard let pm = photoManager, decisions.indices.contains(index) else { return }
        let addedIDs = Set(added.map(\.localIdentifier))
        pm.trashAssets.removeAll { addedIDs.contains($0.localIdentifier) }
        let inTrash = Set(pm.trashAssets.map(\.localIdentifier))
        pm.trashAssets.append(contentsOf: restored.filter { !inTrash.contains($0.localIdentifier) })
        pm.saveTrash()
        cleanedCount = max(0, cleanedCount - deltaCount)
        savedMB = max(0, savedMB - deltaMB)
        decisions[index] = before
        currentIndex = index

        // Redo — 같은 그룹을 같은 방식으로 다시 정리
        undoManager?.registerUndo(withTarget: self) { s in
            s.currentIndex = index
            s.cleanCurrent(keepOnlyRepresentative: keepOnlyRepresentative, undoManager: undoManager)
        }
        undoManager?.setActionName("그룹 정리")
    }

    /// 건너뛰기 (S). 되돌리면 건너뛴 그룹으로 돌아간다.
    func skipCurrent(undoManager: UndoManager? = nil) {
        guard decisions.indices.contains(currentIndex) else { return }
        let index = currentIndex
        let wasSkipped = decisions[index].skipped
        decisions[index].skipped = true
        advance()
        undoManager?.registerUndo(withTarget: self) { s in
            guard s.decisions.indices.contains(index) else { return }
            s.decisions[index].skipped = wasSkipped
            s.currentIndex = index
            undoManager?.registerUndo(withTarget: s) { s2 in
                s2.currentIndex = index
                s2.skipCurrent(undoManager: undoManager)
            }
            undoManager?.setActionName("건너뛰기")
        }
        undoManager?.setActionName("건너뛰기")
    }

    private static func estimatedMB(_ assets: [PHAsset]) -> Double {
        assets.reduce(0.0) { $0 + ($1.mediaType == .image ? 3.5 : 15.0) }
    }

    private func advance() {
        currentIndex += 1
        if decisions.indices.contains(currentIndex) {
            let next = currentIndex
            Task { await refineRepresentative(at: next) }
        }
    }
}
