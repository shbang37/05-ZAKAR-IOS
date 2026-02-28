import SwiftUI
import Photos

// MARK: - 1. 유사 사진 그룹 카드 (글래스모피즘)
struct SimilarityGroupRow: View {
    let group: [PHAsset]
    var onImageTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                Text("\(group.count)장의 유사 사진")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if group.count >= 3 {
                    Text("중복 주의")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.red.opacity(0.75))
                        )
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<group.count, id: \.self) { index in
                        AssetThumbnail(asset: group[index], size: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .onTapGesture { onImageTap(index) }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .background(GlassCard())
    }
}

// MARK: - 2. 애니메이션 휴지통 버튼
struct TrashBucketButton: View {
    let count: Int
    var action: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: count > 0 ? "trash.fill" : "trash")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(count > 0 ? .red : .white.opacity(0.5))
            .padding(.vertical, 8)
            .padding(.horizontal, 13)
            .background(
                Capsule()
                    .fill(count > 0 ? Color.red.opacity(0.18) : Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(count > 0 ? Color.red.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .scaleEffect(scale)
        }
        .onChange(of: count) { _, _ in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { scale = 1.22 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { scale = 1.0 }
            }
        }
    }
}

// MARK: - 3. 개별 사진 썸네일
struct AssetThumbnail: View {
    let asset: PHAsset
    let size: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) var displayScale

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                ProgressView()
                    .tint(.white.opacity(0.4))
                    .scaleEffect(0.6)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear { requestThumbnail() }
    }

    private func requestThumbnail() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: size * displayScale, height: size * displayScale)
        manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { img, _ in
            DispatchQueue.main.async { self.image = img }
        }
    }
}

// MARK: - 4. 임시 휴지통 뷰
struct TrashView: View {
    @Binding var trashAssets: [PHAsset]
    @ObservedObject var photoManager: PhotoManager
    var onDeleteSuccess: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var selectedAssets: Set<PHAsset> = []

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if trashAssets.isEmpty {
                        emptyState
                    } else {
                        photoGrid
                    }
                    actionBar
                }
            }
            .navigationTitle("임시 휴지통")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }
                        .foregroundColor(.white)
                }
                if !trashAssets.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(selectedAssets.count == trashAssets.count ? "전체 해제" : "전체 선택") {
                            if selectedAssets.count == trashAssets.count {
                                selectedAssets.removeAll()
                            } else {
                                selectedAssets = Set(trashAssets)
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text("휴지통이 비어 있습니다")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                ForEach(trashAssets, id: \.localIdentifier) { asset in
                    let isSelected = selectedAssets.contains(asset)
                    ZStack(alignment: .topTrailing) {
                        AssetThumbnail(asset: asset, size: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .opacity(isSelected ? 0.75 : 1.0)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isSelected { selectedAssets.remove(asset) }
                                    else { selectedAssets.insert(asset) }
                                }
                            }

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .blue : .white.opacity(0.6))
                            .shadow(color: .black.opacity(0.5), radius: 3)
                            .padding(6)
                    }
                }
            }
            .padding(8)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            let targets = selectedAssets.isEmpty ? trashAssets : Array(selectedAssets)
            let label = selectedAssets.isEmpty ? "전체 복구" : "선택 복구 (\(selectedAssets.count))"

            Button(label) {
                trashAssets.removeAll { targets.contains($0) }
                selectedAssets.removeAll()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.1))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            .disabled(trashAssets.isEmpty)

            let deleteLabel = selectedAssets.isEmpty ? "전체 삭제" : "선택 삭제 (\(selectedAssets.count))"
            Button(deleteLabel) {
                photoManager.deleteAssets(targets) { success in
                    if success {
                        trashAssets.removeAll { targets.contains($0) }
                        selectedAssets.removeAll()
                        onDeleteSuccess()
                        if trashAssets.isEmpty { dismiss() }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(trashAssets.isEmpty ? Color.white.opacity(0.05) : Color.red.opacity(0.75))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .disabled(trashAssets.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 5. 공용 글래스 카드 배경 (은혜의 새벽 테마)
struct GlassCard: View {
    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AppTheme.dawnPurple.opacity(0.08),
                        AppTheme.dawnPurple.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.gracefulGold.opacity(0.35),
                                AppTheme.dawnPurple.opacity(0.30),
                                AppTheme.gracefulGold.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: AppTheme.dawnPurple.opacity(0.15), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 6)
    }
}
