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
    /// configure 완료 신호.
    /// photoManager는 @Published가 아니라 여기에 넣어도 뷰가 다시 그려지지 않는다.
    /// 첫 렌더는 photoManager가 nil이라 current도 nil(빈 화면)인데, onAppear에서
    /// 연결만 하고 발행을 안 하면 키를 누를 때까지 빈 화면이 그대로 남는다.
    @Published private(set) var isConfigured = false

    private weak var photoManager: PhotoManager?
    private weak var flyController: FlyToTrashController?

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

    /// 즐겨찾기 기록(필름스트립 하트)은 **라이브러리 쓰기가 성공한 뒤** 갱신한다.
    /// 결과를 버리고 미리 표시하면 실패했는데 하트가 남아 "됐다"고 오해하게 된다.
    func setFavorite(id: String, to value: Bool) {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest(for: asset).isFavorite = value
        }, completionHandler: { success, error in
            Task { @MainActor in
                guard success else {
                    print("ZAKAR Log: 즐겨찾기 실패 - \(error?.localizedDescription ?? "알 수 없음")")
                    return
                }
                self.history[id] = value ? .favorited : nil
            }
        })
    }

    /// 사진을 앨범에 실제로 추가한다. PhotoKit 쓰기가 실패할 수 있으므로
    /// 결과를 버리지 않고 `onResult`로 돌려준다 (실패를 조용히 넘기면 "넣었는데 없다"가 된다).
    func moveCurrentToAlbum(_ index: Int,
                            undoManager: UndoManager? = nil,
                            onResult: ((Bool) -> Void)? = nil) {
        guard let pm = photoManager, let asset = current, pm.albums.indices.contains(index) else {
            onResult?(false); return
        }
        let album = pm.albums[index]
        let assetIndex = currentIndex
        pm.addAssets([asset], toAlbum: album.collection) { success in onResult?(success) }
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
