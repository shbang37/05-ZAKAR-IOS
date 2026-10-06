import Foundation
import Photos
import Combine

// ============================================================
// 그룹 비교 모드 상태 모델
// 핵심 결정: 비대표 사진의 기본 상태 = "삭제" (keepSet 초기값 = {대표})
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

    /// 발견된 모든 그룹을 처리했는지 (progressive: 분석이 더 찾을 수 있으므로 뷰에서 isAnalyzing과 함께 판단)
    var reachedEnd: Bool { started && currentIndex >= decisions.count }
    var current: GroupDecision? {
        decisions.indices.contains(currentIndex) ? decisions[currentIndex] : nil
    }

    /// groupedPhotos는 순수 append로 성장(재정렬 없음)하므로, 새로 발견된 그룹만
    /// decisions에 이어붙인다 — 진행 인덱스·사용자 편집을 보존하는 progressive 구성.
    func syncGroups(_ groups: [[PHAsset]], photoManager: PhotoManager) {
        self.photoManager = photoManager
        guard groups.count > decisions.count else { return }
        let newSlice = groups[decisions.count..<groups.count]
        let newDecisions = newSlice.compactMap { g -> GroupDecision? in
            guard let rep = g.first else { return nil }
            return GroupDecision(assets: g, representative: rep, keepSet: [rep.localIdentifier])
        }
        decisions.append(contentsOf: newDecisions)
        started = true
        // 현재 인덱스가 가리키는 그룹의 대표를 엔진 점수로 정교화 (idempotent)
        if decisions.indices.contains(currentIndex) {
            let idx = currentIndex
            Task { await refineRepresentative(at: idx) }
        }
    }

    /// 엔진 품질 점수로 대표를 정교화 (사용자가 아직 대표를 안 바꿨을 때만 반영)
    func refineRepresentative(at index: Int) async {
        guard let pm = photoManager, decisions.indices.contains(index),
              !decisions[index].cleaned else { return }   // 정리한 그룹은 대표를 바꾸지 않는다
        let group = decisions[index].assets
        guard let best = await pm.selectBestPhoto(from: group) else { return }
        guard decisions.indices.contains(index) else { return }
        var d = decisions[index]
        // 초기 기본 상태(대표만 유지)일 때만 대표·keepSet 갱신 — 사용자 편집 보존
        if d.keepSet == [d.representative.localIdentifier] {
            d.representative = best
            d.keepSet = [best.localIdentifier]
            decisions[index] = d
        }
    }

    // MARK: - 사용자 조작 (모두 ⌘Z로 되돌릴 수 있다)

    /// 유지/삭제 토글 (대표는 항상 유지 — 삭제 불가)
    func toggleKeep(_ asset: PHAsset, undoManager: UndoManager? = nil) {
        guard var d = current else { return }
        let id = asset.localIdentifier
        guard id != d.representative.localIdentifier else { return }   // 대표는 토글 불가
        if d.keepSet.contains(id) { d.keepSet.remove(id) } else { d.keepSet.insert(id) }
        replaceDecision(at: currentIndex, with: d, actionName: "유지·삭제 전환", undoManager: undoManager)
    }

    /// 대표 교체 (교체 대상은 자동으로 유지 집합에 포함)
    func setRepresentative(_ asset: PHAsset, undoManager: UndoManager? = nil) {
        guard var d = current else { return }
        d.representative = asset
        d.keepSet.insert(asset.localIdentifier)
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
    /// keepOnlyRepresentative=true 면 현재 선택 무시하고 대표만 남긴다(Primary ⏎).
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
        let toRestore = before.assets.filter {
            before.trashedIDs.contains($0.localIdentifier) && !deleteIDs.contains($0.localIdentifier)
                && inTrash.contains($0.localIdentifier)
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
