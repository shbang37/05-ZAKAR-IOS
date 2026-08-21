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
