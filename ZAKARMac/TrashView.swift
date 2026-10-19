import SwiftUI
import Photos
import AppKit

// ============================================================
// TrashView — 휴지통 (복원 · 비우기)
// 비우기 = PHPhotoLibrary 일괄 삭제 1회(시스템 확인 다이얼로그). 영구 삭제는 Undo 불가.
// 복원·모두 복원은 ⌘Z로 되돌릴 수 있다. 사진을 클릭해 골라서 일부만 복원·영구 삭제할 수도 있다.
// ============================================================

struct TrashView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @State private var confirmingEmpty = false
    /// 골라 둔 사진 (클릭으로 선택) — 있으면 복원·삭제가 이 사진들에만 적용된다
    @State private var selected: Set<String> = []

    /// 영구 삭제 대상: 고른 사진이 있으면 그것만, 없으면 전부
    private var deleteTargets: [PHAsset] {
        selected.isEmpty ? photoManager.trashAssets
                         : photoManager.trashAssets.filter { selected.contains($0.localIdentifier) }
    }

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
        .confirmationDialog("\(deleteTargets.count)장이 사진 앱에서 영구 삭제됩니다. 되돌릴 수 없습니다.",
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
            if !selected.isEmpty {
                Text("\(selected.count)장 선택")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppTheme.gracefulGold)
                Button { selected.removeAll() } label: {
                    Text("선택 해제")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.subText)
            }
            if !photoManager.trashAssets.isEmpty {
                Button { restoreAll() } label: {
                    Text(selected.isEmpty ? "모두 복원" : "선택 복원")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.gracefulGold)
                Button { confirmingEmpty = true } label: {
                    Text(selected.isEmpty ? "비우기" : "선택 영구 삭제")
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
                    let isSelected = selected.contains(asset.localIdentifier)
                    MacAssetThumbnail(asset: asset, size: cellSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isSelected ? AppTheme.gracefulGold : Color.white.opacity(0.1),
                                              lineWidth: isSelected ? 3 : 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.gracefulGold)
                                    .background(Circle().fill(.black.opacity(0.4)))
                                    .padding(6)
                            }
                        }
                        .onTapGesture {
                            if isSelected { selected.remove(asset.localIdentifier) }
                            else { selected.insert(asset.localIdentifier) }
                        }
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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

    /// 고른 사진이 있으면 그것만, 없으면 전부 복원
    private func restoreAll() {
        let targets = deleteTargets
        photoManager.restoreFromTrashUndoably(targets, undo: appState.undo,
                                              actionName: selected.isEmpty ? "모두 복원" : "선택 복원")
        selected.removeAll()
        appState.showToast("\(targets.count)장 복원 — ⌘Z로 되돌릴 수 있어요")
    }

    private func emptyTrash() {
        let assets = deleteTargets
        guard !assets.isEmpty else { return }
        // 일괄 삭제 1회 — 시스템 확인 다이얼로그가 한 번만 표시됨
        photoManager.deleteAssets(assets) { (outcome: PhotoManager.DeleteOutcome) in
            Task { @MainActor in
                switch outcome {
                case .cancelled:
                    return   // 확인창에서 취소 — 오류 아님
                case .failed:
                    appState.showToast("삭제하지 못했습니다 — 사진 접근 권한을 확인해 주세요")
                    return
                case .deleted:
                    break
                }
                // 지운 사진만 뺀다 — 확인창이 떠 있는 사이 새로 들어온 사진까지 목록에서 지우면
                // 사용자가 버리려던 사진이 라이브러리에 슬그머니 남는다
                let deleted = Set(assets.map(\.localIdentifier))
                photoManager.trashAssets.removeAll { deleted.contains($0.localIdentifier) }
                photoManager.saveTrash()
                selected.subtract(deleted)
                // 영구 삭제는 되돌릴 수 없다. 남은 ⌘Z 기록은 사라진 사진·바뀐 순번을 가리키므로 비운다.
                appState.undo.removeAllActions()
                appState.showToast("\(deleted.count)장을 영구 삭제했습니다 — 되돌릴 수 없습니다", seconds: 3.5)
            }
        }
    }
}
