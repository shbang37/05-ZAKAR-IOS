import SwiftUI
import Photos
import AppKit

// ============================================================
// TrashView — 휴지통 (복원 · 비우기)
// 비우기 = PHPhotoLibrary 일괄 삭제 1회(시스템 확인 다이얼로그). 영구 삭제는 Undo 불가.
// 복원·모두 복원은 ⌘Z로 되돌릴 수 있다.
// ============================================================

struct TrashView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @State private var confirmingEmpty = false

    private let cellSize: CGFloat = 150
    private let spacing: CGFloat = 8

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cellSize, maximum: cellSize), spacing: spacing)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.divider)
            if photoManager.trashAssets.isEmpty {
                MacPlaceholderView(systemImage: "trash",
                                   title: "휴지통이 비어 있습니다",
                                   subtitle: "정리한 사진이 여기 모입니다. 비우기 전까지 복원할 수 있어요.")
            } else {
                grid
            }
        }
        .confirmationDialog("휴지통을 비우면 \(photoManager.trashAssets.count)장이 사진 앱에서 영구 삭제됩니다. 되돌릴 수 없습니다.",
                            isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button("영구 삭제", role: .destructive) { emptyTrash() }
            Button("취소", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Text("휴지통")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(photoManager.trashAssets.count)장")
                .font(.callout)
                .foregroundStyle(AppTheme.subText)
            Spacer()
            if !photoManager.trashAssets.isEmpty {
                Button { restoreAll() } label: {
                    Text("모두 복원")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.gracefulGold)
                Button { confirmingEmpty = true } label: {
                    Text("비우기")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(photoManager.trashAssets, id: \.localIdentifier) { asset in
                    MacAssetThumbnail(asset: asset, size: cellSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        }
                        .overlay(alignment: .bottom) {
                            // 모양·여백을 **label 안에** 둬야 보이는 캡슐 전체가 눌린다.
                            // Button("복원").padding().background()로 쓰면 글자만 눌린다.
                            Button { restore(asset) } label: {
                                Label("복원", systemImage: "arrow.uturn.backward")
                                    .font(.callout.weight(.semibold))
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                    .background(Capsule().fill(AppTheme.gracefulGold))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.deepPurple)
                            .help("휴지통에서 꺼내기 (⌘Z로 되돌리기)")
                            .padding(8)
                        }
                }
            }
            .padding(16)
        }
    }

    // MARK: - 동작

    private func restore(_ asset: PHAsset) {
        photoManager.restoreFromTrashUndoably([asset], undo: appState.undo)
    }

    private func restoreAll() {
        let count = photoManager.trashAssets.count
        photoManager.restoreFromTrashUndoably(photoManager.trashAssets, undo: appState.undo,
                                              actionName: "모두 복원")
        appState.showToast("\(count)장 복원 — ⌘Z로 되돌릴 수 있어요")
    }

    private func emptyTrash() {
        let assets = photoManager.trashAssets
        guard !assets.isEmpty else { return }
        // 일괄 삭제 1회 — 시스템 확인 다이얼로그가 한 번만 표시됨
        photoManager.deleteAssets(assets) { success in
            Task { @MainActor in
                if success {
                    photoManager.trashAssets.removeAll()
                    photoManager.saveTrash()
                }
            }
        }
    }
}
