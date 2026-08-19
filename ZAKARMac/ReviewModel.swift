import Foundation
import Photos
import SwiftUI
import Combine

// ============================================================
// 리뷰 모드 상태 모델
// allPhotos를 1장씩 대량 선별. 처리 이력(history)은 필름스트립 오버레이용.
// 삭제/앨범이동은 자동 다음 진행, 즐겨찾기는 제자리 토글.
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

    private weak var photoManager: PhotoManager?
    private weak var flyController: FlyToTrashController?

    func configure(_ pm: PhotoManager, _ fly: FlyToTrashController) {
        photoManager = pm
        flyController = fly
    }

    var assets: [PHAsset] { photoManager?.allPhotos ?? [] }
    var current: PHAsset? { assets.indices.contains(currentIndex) ? assets[currentIndex] : nil }

    // MARK: - 이동

    func advance() { if currentIndex < assets.count - 1 { currentIndex += 1 } }
    func back() { if currentIndex > 0 { currentIndex -= 1 } }
    func jump(to index: Int) { if assets.indices.contains(index) { currentIndex = index } }

    // MARK: - 처리

    func deleteCurrent(reduceMotion: Bool, undoManager: UndoManager? = nil) {
        guard let pm = photoManager, let asset = current else { return }
        let index = currentIndex
        flyController?.fly(assets: [asset], reduceMotion: reduceMotion)   // 흡입
        let existing = Set(pm.trashAssets.map { $0.localIdentifier })
        let wasAdded = !existing.contains(asset.localIdentifier)
        if wasAdded {
            pm.trashAssets.append(asset)
            pm.saveTrash()
        }
        history[asset.localIdentifier] = .deleted

        let id = asset.localIdentifier
        undoManager?.registerUndo(withTarget: self) { s in
            s.undoDelete(id: id, wasAdded: wasAdded, index: index, undoManager: undoManager)
        }
        undoManager?.setActionName("삭제 취소")
        advance()
    }

    func undoDelete(id: String, wasAdded: Bool, index: Int, undoManager: UndoManager?) {
        guard let pm = photoManager else { return }
        if wasAdded {
            pm.trashAssets.removeAll { $0.localIdentifier == id }
            pm.saveTrash()
        }
        history[id] = nil
        jump(to: index)
        undoManager?.registerUndo(withTarget: self) { s in
            s.deleteCurrent(reduceMotion: true, undoManager: undoManager)
        }
        undoManager?.setActionName("삭제 취소")
    }

    func toggleFavoriteCurrent(undoManager: UndoManager? = nil) {
        guard let asset = current else { return }
        // allPhotos에 담긴 PHAsset은 페치 시점 스냅샷이라 isFavorite이 갱신되지 않는다.
        // 최신 값을 다시 읽지 않으면 F가 토글이 아니라 "설정"만 반복하게 된다.
        let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [asset.localIdentifier], options: nil).firstObject
        let newValue = !(fresh?.isFavorite ?? asset.isFavorite)
        setFavorite(id: asset.localIdentifier, to: newValue)
        undoManager?.registerUndo(withTarget: self) { s in
            s.setFavorite(id: asset.localIdentifier, to: !newValue)
            undoManager?.setActionName("즐겨찾기 취소")
            undoManager?.registerUndo(withTarget: s) { s2 in s2.setFavorite(id: asset.localIdentifier, to: newValue) }
        }
        undoManager?.setActionName("즐겨찾기 취소")
    }

    func setFavorite(id: String, to value: Bool) {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest(for: asset).isFavorite = value
        }, completionHandler: { _, _ in })
        history[id] = value ? .favorited : nil
    }

    func moveCurrentToAlbum(_ index: Int, undoManager: UndoManager? = nil) {
        guard let pm = photoManager, let asset = current, pm.albums.indices.contains(index) else { return }
        let album = pm.albums[index]
        let assetIndex = currentIndex
        pm.addAssets([asset], toAlbum: album.collection) { _ in }
        history[asset.localIdentifier] = .moved(album.title)

        let id = asset.localIdentifier
        undoManager?.registerUndo(withTarget: self) { s in
            s.undoMoveToAlbum(id: id, albumIndex: index, assetIndex: assetIndex, undoManager: undoManager)
        }
        undoManager?.setActionName("앨범 이동 취소")
        advance()
    }

    func undoMoveToAlbum(id: String, albumIndex: Int, assetIndex: Int, undoManager: UndoManager?) {
        guard let pm = photoManager, pm.albums.indices.contains(albumIndex) else { return }
        let album = pm.albums[albumIndex]
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return }
        // 앨범에서 제거
        PHPhotoLibrary.shared().performChanges({
            if let req = PHAssetCollectionChangeRequest(for: album.collection) {
                req.removeAssets([asset] as NSArray)
            }
        }, completionHandler: { _, _ in })
        history[id] = nil
        jump(to: assetIndex)
        undoManager?.registerUndo(withTarget: self) { s in
            s.moveCurrentToAlbum(albumIndex, undoManager: undoManager)
        }
        undoManager?.setActionName("앨범 이동 취소")
    }
}
