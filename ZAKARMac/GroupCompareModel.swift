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
        guard let pm = photoManager, decisions.indices.contains(index) else { return }
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

    // MARK: - 사용자 조작

    /// 유지/삭제 토글 (대표는 항상 유지 — 삭제 불가)
    func toggleKeep(_ asset: PHAsset) {
        guard decisions.indices.contains(currentIndex) else { return }
        var d = decisions[currentIndex]
        let id = asset.localIdentifier
        guard id != d.representative.localIdentifier else { return }   // 대표는 토글 불가
        if d.keepSet.contains(id) { d.keepSet.remove(id) } else { d.keepSet.insert(id) }
        decisions[currentIndex] = d
    }

    /// 대표 교체 (교체 대상은 자동으로 유지 집합에 포함)
    func setRepresentative(_ asset: PHAsset) {
        guard decisions.indices.contains(currentIndex) else { return }
        var d = decisions[currentIndex]
        d.representative = asset
        d.keepSet.insert(asset.localIdentifier)
        decisions[currentIndex] = d
    }

    // MARK: - 정리 실행

    /// 현재 그룹 정리 → 휴지통 등록(LocalDB) + 취향 신호 + 통계, 다음 그룹으로.
    /// keepOnlyRepresentative=true 면 현재 선택 무시하고 대표만 남긴다(Primary ⏎).
    func cleanCurrent(keepOnlyRepresentative: Bool, undoManager: UndoManager? = nil) {
        guard let pm = photoManager, let d = current else { return }
        let cleanedIndex = currentIndex
        let keep = keepOnlyRepresentative ? [d.representative.localIdentifier] : d.keepSet
        let deleteAssets = d.assets.filter { !keep.contains($0.localIdentifier) }

        if !deleteAssets.isEmpty {
            // 휴지통 등록 (중복 방지) — @Published 갱신으로 배지 즉시 반영
            let existing = Set(pm.trashAssets.map { $0.localIdentifier })
            let toAdd = deleteAssets.filter { !existing.contains($0.localIdentifier) }
            pm.trashAssets.append(contentsOf: toAdd)
            pm.saveTrash()

            // 취향 학습 신호 (iOS와 동일 계약)
            pm.recordUserChoice(kept: d.representative, discarded: deleteAssets)

            // 세션 통계
            let addedMB = deleteAssets.reduce(0.0) { $0 + ($1.mediaType == .image ? 3.5 : 15.0) }
            cleanedCount += deleteAssets.count
            savedMB += addedMB

            // Undo 등록 — 그룹 단위 일괄 복원 (⌘Z 1회에 N장)
            let addedIds = toAdd.map { $0.localIdentifier }
            let deletedCount = deleteAssets.count
            undoManager?.registerUndo(withTarget: self) { s in
                s.undoClean(indexToRestore: cleanedIndex, trashedIds: addedIds,
                            deletedCount: deletedCount, savedMB: addedMB,
                            keepOnlyRepresentative: keepOnlyRepresentative, undoManager: undoManager)
            }
            undoManager?.setActionName("정리 취소")
        }
        advance()
    }

    /// 그룹 일괄 정리 취소 — 휴지통에서 N장 복원 + 진행 인덱스 원위치
    func undoClean(indexToRestore: Int, trashedIds: [String], deletedCount: Int, savedMB addedMB: Double,
                   keepOnlyRepresentative: Bool, undoManager: UndoManager?) {
        guard let pm = photoManager else { return }
        pm.trashAssets.removeAll { trashedIds.contains($0.localIdentifier) }
        pm.saveTrash()
        cleanedCount = max(0, cleanedCount - deletedCount)
        savedMB = max(0, savedMB - addedMB)
        if decisions.indices.contains(indexToRestore) { currentIndex = indexToRestore }

        // Redo 등록
        undoManager?.registerUndo(withTarget: self) { s in
            s.cleanCurrent(keepOnlyRepresentative: keepOnlyRepresentative, undoManager: undoManager)
        }
        undoManager?.setActionName("정리 취소")
    }

    func skipCurrent() {
        if decisions.indices.contains(currentIndex) { decisions[currentIndex].skipped = true }
        advance()
    }

    private func advance() {
        currentIndex += 1
        if decisions.indices.contains(currentIndex) {
            let next = currentIndex
            Task { await refineRepresentative(at: next) }
        }
    }
}
