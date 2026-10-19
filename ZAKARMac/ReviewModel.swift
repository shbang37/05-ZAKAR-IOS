import Foundation
import Photos
import SwiftUI
import Combine

// ============================================================
// 리뷰 모드 상태 모델
// allPhotos를 1장씩 대량 선별. 처리 이력(history)은 필름스트립 오버레이용.
// 삭제(↑·⌫)/앨범이동은 자동 다음 진행, 즐겨찾기·살리기(↓)는 제자리.
// ============================================================

enum ReviewAction: Equatable {
    case deleted
    case favorited
    case moved(String)   // 앨범명
}

@MainActor
final class ReviewSession: ObservableObject {
    @Published var currentIndex = 0
    @Published var history: [String: ReviewAction] = [:]
    /// configure 완료 신호.
    /// photoManager는 @Published가 아니라 여기에 넣어도 뷰가 다시 그려지지 않는다.
    /// 첫 렌더는 photoManager가 nil이라 current도 nil(빈 화면)인데, onAppear에서
    /// 연결만 하고 발행을 안 하면 키를 누를 때까지 빈 화면이 그대로 남는다.
    @Published private(set) var isConfigured = false

    private weak var photoManager: PhotoManager?
    private weak var flyController: FlyToTrashController?
    /// 즐겨찾기·앨범처럼 라이브러리를 바꿨을 때 호출 — 즐겨찾기/앨범 화면 갱신용
    var onLibraryChanged: (() -> Void)?

    func configure(_ pm: PhotoManager, _ fly: FlyToTrashController) {
        photoManager = pm
        flyController = fly
        if !isConfigured { isConfigured = true }   // 첫 사진이 바로 뜨도록 갱신을 건다
    }

    var assets: [PHAsset] { photoManager?.allPhotos ?? [] }
    var current: PHAsset? { assets.indices.contains(currentIndex) ? assets[currentIndex] : nil }

    // MARK: - 이동

    func advance() { if currentIndex < assets.count - 1 { currentIndex += 1 } }
    func back() { if currentIndex > 0 { currentIndex -= 1 } }
    func jump(to index: Int) { if assets.indices.contains(index) { currentIndex = index } }

    /// 사진 위치는 목록이 다시 읽히면 바뀌므로, 되돌리기·다시 실행은 **사진 id로** 찾아간다.
    /// (번호로 기억하면 휴지통 비우기·새로고침 뒤 엉뚱한 사진에 적용된다)
    @discardableResult
    func jump(toID id: String) -> Bool {
        guard let i = assets.firstIndex(where: { $0.localIdentifier == id }) else { return false }
        currentIndex = i
        return true
    }

    // MARK: - 처리 (되돌리기·다시 실행은 모두 처음 처리한 사진 id 기준)

    /// ↑·⌫ — 지금 사진을 휴지통에 넣고 다음 사진으로
    func deleteCurrent(reduceMotion: Bool, undoManager: UndoManager? = nil) {
        guard let asset = current else { return }
        flyController?.fly(assets: [asset], reduceMotion: reduceMotion)   // 흡입
        delete(asset, undoManager: undoManager)
        advance()
    }

    private func delete(_ asset: PHAsset, undoManager: UndoManager?) {
        guard let pm = photoManager else { return }
        let id = asset.localIdentifier
        let wasAdded = !pm.trashAssets.contains { $0.localIdentifier == id }
        if wasAdded {
            pm.trashAssets.append(asset)
            pm.saveTrash()
        }
        let previous = history[id]
        history[id] = .deleted
        undoManager?.registerUndo(withTarget: self) { s in
            s.undoDelete(asset, wasAdded: wasAdded, previous: previous, undoManager: undoManager)
        }
        undoManager?.setActionName("삭제")
    }

    private func undoDelete(_ asset: PHAsset, wasAdded: Bool, previous: ReviewAction?, undoManager: UndoManager?) {
        guard let pm = photoManager else { return }
        let id = asset.localIdentifier
        if wasAdded {
            pm.trashAssets.removeAll { $0.localIdentifier == id }
            pm.saveTrash()
        }
        history[id] = previous
        jump(toID: id)   // 되돌린 사진을 보여 준다
        undoManager?.registerUndo(withTarget: self) { s in
            s.jump(toID: id)
            s.delete(asset, undoManager: undoManager)   // 다시 실행 = 같은 사진을 다시 휴지통으로
        }
        undoManager?.setActionName("삭제")
    }

    /// ↓ — 지금 보는 사진이 휴지통에 있으면 꺼낸다. 휴지통에 없으면 false (뷰가 안내를 띄운다).
    /// 이번 세션 기록(history)이 아니라 **실제 휴지통**을 본다 — 지난번에 버린 사진도 살릴 수 있게.
    @discardableResult
    func restoreCurrent(undoManager: UndoManager? = nil) -> Bool {
        guard let asset = current else { return false }
        return restore(asset, undoManager: undoManager)
    }

    @discardableResult
    private func restore(_ asset: PHAsset, undoManager: UndoManager?) -> Bool {
        guard let pm = photoManager else { return false }
        let id = asset.localIdentifier
        guard let trashIndex = pm.trashAssets.firstIndex(where: { $0.localIdentifier == id }) else { return false }
        pm.trashAssets.remove(at: trashIndex)
        pm.saveTrash()
        let previous = history[id]
        history[id] = nil
        undoManager?.registerUndo(withTarget: self) { s in
            s.undoRestore(asset, trashIndex: trashIndex, previous: previous, undoManager: undoManager)
        }
        undoManager?.setActionName("휴지통에서 살리기")
        return true
    }

    /// 살리기 취소 — 휴지통의 원래 자리로 되돌리고 그 사진으로 돌아간다
    private func undoRestore(_ asset: PHAsset, trashIndex: Int, previous: ReviewAction?,
                             undoManager: UndoManager?) {
        guard let pm = photoManager else { return }
        let id = asset.localIdentifier
        if !pm.trashAssets.contains(where: { $0.localIdentifier == id }) {
            pm.trashAssets.insert(asset, at: min(trashIndex, pm.trashAssets.count))
            pm.saveTrash()
        }
        history[id] = previous ?? .deleted
        jump(toID: id)
        undoManager?.registerUndo(withTarget: self) { s in
            s.jump(toID: id)
            s.restore(asset, undoManager: undoManager)
        }
        undoManager?.setActionName("휴지통에서 살리기")
    }

    // 즐겨찾기(F)는 MacAppState.toggleFavorite을 쓴다 — 사진 id 기준이고 되돌리기·다시 실행이 이미 맞물려 있다.

    /// ⌘1~9 — 사진을 앨범에 넣고 다음 사진으로.
    /// 앨범은 **번호가 아니라 앨범 자체**로 기억하고, 되돌릴 땐 이번에 새로 들어간 경우에만 뺀다
    /// (PhotoManager.addToAlbumUndoably). 원래 그 앨범에 있던 사진은 그대로 둔다.
    func moveCurrentToAlbum(_ index: Int, undoManager: UndoManager, onResult: ((Bool) -> Void)? = nil) {
        guard let pm = photoManager, let asset = current, pm.albums.indices.contains(index) else {
            onResult?(false); return
        }
        let album = pm.albums[index]
        pm.addToAlbumUndoably([asset], album: album, undo: undoManager,
                              completion: { success in onResult?(success) },
                              onChange: { [weak self] in self?.onLibraryChanged?() })
        // 같은 이벤트 안의 등록이라 위 앨범 되돌리기와 한 묶음으로 ⌘Z 된다
        markMoved(asset.localIdentifier, to: album.title, undoManager: undoManager)
        advance()
    }

    /// 필름스트립 폴더 표시 + 되돌릴 때 그 사진으로 돌아가기 (앨범 쓰기 자체는 PhotoManager가 되돌린다)
    private func markMoved(_ id: String, to title: String, undoManager: UndoManager) {
        let previous = history[id]
        history[id] = .moved(title)
        undoManager.registerUndo(withTarget: self) { s in
            s.history[id] = previous
            s.jump(toID: id)
            undoManager.registerUndo(withTarget: s) { s2 in s2.markMoved(id, to: title, undoManager: undoManager) }
        }
    }
}
