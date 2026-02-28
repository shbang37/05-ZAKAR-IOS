import SwiftUI
import Photos

struct AlbumsView: View {
    @State private var albums: [PHAssetCollection] = []
    @State private var smartAlbums: [PHAssetCollection] = []
    @State private var isAuthorized = false

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 18) {
                        // 내 앨범 섹션
                        if !albums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("내 앨범")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 20)
                                    .padding(.top, 8)
                                
                                VStack(spacing: 10) {
                                    ForEach(albums, id: \.localIdentifier) { collection in
                                        NavigationLink(destination: AlbumDetailView(collection: collection)) {
                                            albumCard(
                                                icon: "folder.fill",
                                                title: collection.localizedTitle ?? "앨범",
                                                gradient: AppTheme.goldenGradient,
                                                count: getAssetCount(for: collection)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        
                        // 스마트 앨범 섹션
                        if !smartAlbums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("스마트 앨범")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 20)
                                
                                VStack(spacing: 10) {
                                    ForEach(smartAlbums, id: \.localIdentifier) { collection in
                                        NavigationLink(destination: AlbumDetailView(collection: collection)) {
                                            albumCard(
                                                icon: "folder",
                                                title: collection.localizedTitle ?? "앨범",
                                                gradient: AppTheme.purpleGradient,
                                                count: getAssetCount(for: collection)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("앨범")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear { requestAndFetch() }
    }
    
    private func albumCard(icon: String, title: String, gradient: LinearGradient, count: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(gradient)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(gradient.opacity(0.3), lineWidth: 1))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(count)개 항목")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(16)
        .background(GlassCard(cornerRadius: 16))
        .contentShape(Rectangle())
    }
    
    private func getAssetCount(for collection: PHAssetCollection) -> Int {
        let options = PHFetchOptions()
        let fetch = PHAsset.fetchAssets(in: collection, options: options)
        return fetch.count
    }

    private func requestAndFetch() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                isAuthorized = (status == .authorized || status == .limited)
                guard isAuthorized else { return }
                fetchAlbums()
            }
        }
    }

    private func fetchAlbums() {
        var result: [PHAssetCollection] = []
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in result.append(collection) }
        self.albums = result

        var smart: [PHAssetCollection] = []
        let smartFetch = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartFetch.enumerateObjects { collection, _, _ in
            switch collection.assetCollectionSubtype {
            case .smartAlbumUserLibrary, // Recents
                 .smartAlbumFavorites,
                 .smartAlbumVideos,
                 .smartAlbumLivePhotos:
                smart.append(collection)
            default:
                break
            }
        }
        self.smartAlbums = smart
    }
}

struct AlbumDetailView: View {
    let collection: PHAssetCollection
    @State private var assets: [PHAsset] = []
    @EnvironmentObject var photoManager: PhotoManager
    @State private var isCleanModeActive = false
    @State private var selectedPhotoIndex = 0
    @State private var trashAssets: [PHAsset] = []

    private let grid = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()
            
            ScrollView {
                LazyVGrid(columns: grid, spacing: 2) {
                    ForEach(assets.indices, id: \.self) { index in
                        AssetThumbnail(asset: assets[index], size: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .onTapGesture {
                                selectedPhotoIndex = index
                                isCleanModeActive = true
                            }
                    }
                }
                .padding(8)
            }
        }
        .navigationTitle(collection.localizedTitle ?? "앨범")
        .onAppear { fetchAssets() }
        .fullScreenCover(isPresented: $isCleanModeActive) {
            CleanUpView(
                photos: assets,
                startIndex: selectedPhotoIndex,
                isPresented: $isCleanModeActive,
                trashAlbum: $trashAssets,
                photoManager: photoManager
            )
        }
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(in: collection, options: options)
        var temp: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in temp.append(asset) }
        self.assets = temp
    }
}

#Preview { AlbumsView() }

