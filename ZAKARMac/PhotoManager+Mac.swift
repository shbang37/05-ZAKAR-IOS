import Foundation
import Photos

// ============================================================
// PhotoManager (macOS 전용 확장)
// 앨범 생성 — ⌘1~9 "사진을 앨범으로 이동"의 대상이 되는 **사용자 앨범**을 앱 안에서 만든다.
// 스마트 앨범(최근 항목·스크린샷 등)은 PhotoKit이 사진 추가를 허용하지 않으므로
// 이동 대상이 될 수 없고, 여기서도 만들지 않는다.
// ============================================================

extension PhotoManager {
    /// Mac 전용 앨범 로더.
    /// 공유 코어의 `fetchAlbums()`는 `assetCount > 0`인 앨범만 담는데(iOS 앨범 선택 화면 기준),
    /// Mac은 "방금 만든 빈 앨범"이 바로 ⌘1~9 대상이 되어야 하므로 빈 앨범도 포함한다.
    /// 스마트 앨범은 사진 추가가 불가능하므로 제외한다.
    ///
    /// 정렬은 **이름순 고정**. 날짜순으로 두면 사진을 넣을 때마다 순서가 바뀌어
    /// ⌘1~9 번호가 따라 움직이고, 어제 ⌘2였던 앨범이 오늘 ⌘3이 된다.
    func fetchUserAlbumsForMac() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        Task(priority: .userInitiated) {
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .album, subtype: .albumRegular, options: nil
            )
            var list: [AlbumInfo] = []
            collections.enumerateObjects { collection, _, _ in
                list.append(AlbumInfo(collection: collection))
            }
            list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

            await MainActor.run {
                self.albums = list
                print("ZAKAR Log: [Mac] 사용자 앨범 \(list.count)개 로드 완료")
            }
        }
    }

    enum AlbumCreationError: LocalizedError {
        case emptyName
        case duplicateName
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .emptyName:      return "앨범 이름을 입력해 주세요."
            case .duplicateName:  return "같은 이름의 앨범이 이미 있습니다."
            case .failed(let m):  return "앨범을 만들지 못했습니다 — \(m)"
            }
        }
    }

    /// 사용자 앨범을 만들고 앨범 목록을 갱신한다. 성공 시 생성된 앨범 id 반환.
    @discardableResult
    func createAlbum(named rawName: String) async throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AlbumCreationError.emptyName }
        guard !albums.contains(where: { $0.title == name }) else { throw AlbumCreationError.duplicateName }

        var placeholderID: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                placeholderID = request.placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch {
            throw AlbumCreationError.failed(error.localizedDescription)
        }

        guard let id = placeholderID else {
            throw AlbumCreationError.failed("생성된 앨범을 찾을 수 없습니다.")
        }

        // 빈 앨범은 fetchAlbums의 assetCount > 0 필터에 걸리므로 직접 목록에 넣는다.
        let fetched = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
        if let collection = fetched.firstObject {
            albums.insert(AlbumInfo(collection: collection), at: 0)
        }
        print("ZAKAR Log: 앨범 생성 - \(name) (총 \(albums.count)개)")
        return id
    }
}

// ============================================================
// 되돌릴 수 있는 라이브러리 변경 (⌘Z / ⌘⇧Z)
// 되돌리기 안에서 반대 동작을 다시 "되돌릴 수 있게" 부르므로 다시 실행도 자동으로 쌓인다.
// 휴지통 비우기(영구 삭제)만 예외 — 사진 앱에서 지워진 사진은 되살릴 수 없다.
// ============================================================

extension PhotoManager {
    /// 휴지통에 넣기 (이미 들어 있는 사진은 건너뛴다)
    func addToTrashUndoably(_ assets: [PHAsset], undo: UndoManager, actionName: String = "휴지통으로 이동") {
        var seen = Set(trashAssets.map { $0.localIdentifier })
        let toAdd = assets.filter { seen.insert($0.localIdentifier).inserted }
        guard !toAdd.isEmpty else { return }
        trashAssets.append(contentsOf: toAdd)
        saveTrash()
        undo.registerUndo(withTarget: self) { pm in
            pm.restoreFromTrashUndoably(toAdd, undo: undo, actionName: actionName)
        }
        undo.setActionName(actionName)
    }

    /// 휴지통에서 꺼내기. 되돌리면 **원래 자리**로 돌아간다 (끝에 붙이면 순서가 뒤섞여 보인다).
    func restoreFromTrashUndoably(_ assets: [PHAsset], undo: UndoManager, actionName: String = "복원") {
        let ids = Set(assets.map { $0.localIdentifier })
        let removed = trashAssets.enumerated()
            .filter { ids.contains($0.element.localIdentifier) }
            .map { (index: $0.offset, asset: $0.element) }
        guard !removed.isEmpty else { return }
        trashAssets.removeAll { ids.contains($0.localIdentifier) }
        saveTrash()
        undo.registerUndo(withTarget: self) { pm in
            pm.reinsertIntoTrash(removed, undo: undo, actionName: actionName)
        }
        undo.setActionName(actionName)
    }

    private func reinsertIntoTrash(_ removed: [(index: Int, asset: PHAsset)],
                                   undo: UndoManager, actionName: String) {
        var existing = Set(trashAssets.map { $0.localIdentifier })
        for item in removed.sorted(by: { $0.index < $1.index })
        where existing.insert(item.asset.localIdentifier).inserted {
            trashAssets.insert(item.asset, at: min(item.index, trashAssets.count))
        }
        saveTrash()
        undo.registerUndo(withTarget: self) { pm in
            pm.restoreFromTrashUndoably(removed.map(\.asset), undo: undo, actionName: actionName)
        }
        undo.setActionName(actionName)
    }

    /// 앨범에 넣기. 되돌리면 **이번에 새로 들어간 사진만** 뺀다 (원래 있던 사진까지 빼면 안 된다).
    /// `onChange`는 넣기·빼기 어느 쪽이든 성공하면 불린다 — 사이드바 장수·앨범 화면 갱신용.
    func addToAlbumUndoably(_ assets: [PHAsset], album: AlbumInfo, undo: UndoManager,
                            completion: @escaping (Bool) -> Void = { _ in },
                            onChange: @escaping () -> Void) {
        var inAlbum = Set<String>()
        PHAsset.fetchAssets(in: album.collection, options: nil)
            .enumerateObjects { asset, _, _ in inAlbum.insert(asset.localIdentifier) }
        let newOnes = assets.filter { !inAlbum.contains($0.localIdentifier) }

        undo.registerUndo(withTarget: self) { pm in
            pm.removeFromAlbumUndoably(newOnes, album: album, undo: undo, onChange: onChange)
        }
        undo.setActionName("‘\(album.title)’ 앨범에 넣기")
        addAssets(assets, toAlbum: album.collection) { success in
            if success { onChange() }
            completion(success)
        }
    }

    func removeFromAlbumUndoably(_ assets: [PHAsset], album: AlbumInfo, undo: UndoManager,
                                 onChange: @escaping () -> Void) {
        undo.registerUndo(withTarget: self) { pm in
            pm.addToAlbumUndoably(assets, album: album, undo: undo, onChange: onChange)
        }
        undo.setActionName("‘\(album.title)’ 앨범에 넣기")
        guard !assets.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest(for: album.collection)?.removeAssets(assets as NSArray)
        }, completionHandler: { success, error in
            if let error { print("ZAKAR Log: 앨범에서 빼기 실패 - \(error.localizedDescription)") }
            Task { @MainActor in if success { onChange() } }
        })
    }
}
