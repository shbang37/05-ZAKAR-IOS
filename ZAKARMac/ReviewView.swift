import SwiftUI
import Photos
import AppKit

// ============================================================
// ReviewView — 리뷰 모드 (키보드 대량 선별)
// 대형 프리뷰(2단계 로드+프리페치) + 필름스트립 + 첫 실행 단축키 안내.
// 키: ⌫ 삭제 · F 즐겨찾기 · ⌘1~9 앨범 · ←→ 이동 · Space 확대.
// ============================================================

struct ReviewView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var appState: MacAppState
    @EnvironmentObject var flyController: FlyToTrashController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 포커스와 무관하게 동작하도록 앱 소유 UndoManager 사용 (MacAppState 주석 참고)
    private var undoManager: UndoManager { appState.undo }
    @StateObject private var session = ReviewSession()

    @FocusState private var focused: Bool
    @State private var showQuickLook = false
    @State private var quickLookIndex = 0
    @AppStorage("reviewGuideShown") private var guideShown = false
    @State private var showGuide = false

    var body: some View {
        Group {
            if photoManager.allPhotos.isEmpty {
                MacPlaceholderView(systemImage: "eye",
                                   title: photoManager.isLoadingList ? "사진 불러오는 중…" : "사진이 없습니다",
                                   subtitle: "리뷰할 사진이 없습니다.")
            } else {
                content
            }
        }
        .onAppear {
            session.configure(photoManager, flyController)
            if !guideShown { showGuide = true }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppTheme.divider)
            preview
            FilmstripView(session: session)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .macKeys(handleKey)   // keyCode 기반 — 한글 입력기·포커스 무관
        .overlay {
            if showQuickLook {
                QuickLookOverlay(assets: photoManager.allPhotos,
                                 index: $quickLookIndex,
                                 onClose: { showQuickLook = false; focused = true })
                    .onChange(of: quickLookIndex) { _, i in session.jump(to: i) }
            }
        }
        .overlay {
            if showGuide {
                KeyGuideOverlay(onClose: { showGuide = false; guideShown = true; focused = true })
            }
        }
    }

    private var header: some View {
        HStack {
            Text("리뷰")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(session.currentIndex + 1) / \(photoManager.allPhotos.count)")
                .font(.callout)
                .foregroundStyle(AppTheme.subText)
            Spacer()
            Text("⌫ 삭제 · F 즐겨찾기 · ⌘1~9 앨범 · ←→ 이동 · Space 확대")
                .font(.caption)
                .foregroundStyle(AppTheme.subText.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var preview: some View {
        if let asset = session.current {
            VStack(spacing: 10) {
                MacLargeImage(asset: asset)
                    .reportCardFrame(id: asset.localIdentifier, to: flyController)   // 흡입 시작 위치
                Text(metadataLine(asset))
                    .font(.callout)
                    .foregroundStyle(AppTheme.subText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .onChange(of: session.currentIndex) { _, _ in prefetchNext() }
            .onAppear { prefetchNext() }
        } else {
            Color.clear
        }
    }

    /// 키 처리 — 오버레이가 떠 있으면 오버레이가 우선.
    /// ⌘1~9는 "현재 사진을 앨범으로 이동"이며, 로컬 모니터가 먼저 잡으므로
    /// 루트의 ⌘1~9(앨범 화면 이동)보다 우선한다.
    private func handleKey(_ key: MacKey, _ mods: NSEvent.ModifierFlags) -> Bool {
        if showGuide {
            showGuide = false
            guideShown = true
            focused = true
            return true
        }
        if showQuickLook {
            switch key {
            case .leftArrow:
                if quickLookIndex > 0 { quickLookIndex -= 1 }
            case .rightArrow:
                if quickLookIndex < photoManager.allPhotos.count - 1 { quickLookIndex += 1 }
            case .space, .escape:
                showQuickLook = false
                focused = true
            default:
                break
            }
            return true   // 확대 중에는 뒤쪽 키 동작을 막는다
        }
        if mods.contains(.command) {
            // ⌘Z/⌘⇧Z도 여기서 처리 — 메뉴 단축키는 KeyEquivalent 문자 기반이라
            // 입력기 상태에 따라 매칭이 흔들릴 수 있다 (메뉴 항목 자체는 그대로 둔다)
            if key == .letterZ {
                mods.contains(.shift) ? undoManager.redo() : undoManager.undo()
                return true
            }
            guard case .digit(let n) = key else { return false }
            guard photoManager.albums.indices.contains(n - 1) else {
                appState.showToast(photoManager.albums.isEmpty
                                   ? "이동할 앨범이 없습니다 — ⌘N으로 새 앨범을 만드세요"
                                   : "⌘\(n)에 지정된 앨범이 없습니다")
                return true
            }
            let title = photoManager.albums[n - 1].title
            session.moveCurrentToAlbum(n - 1, undoManager: undoManager)
            appState.showToast("‘\(title)’ 앨범으로 이동")
            return true
        }
        guard mods.zakarIsPlainKey else { return false }
        switch key {
        case .delete:     session.deleteCurrent(reduceMotion: reduceMotion, undoManager: undoManager)
        case .leftArrow:  session.back()
        case .rightArrow: session.advance()
        case .letterF:    session.toggleFavoriteCurrent(undoManager: undoManager)
        case .space:
            quickLookIndex = session.currentIndex
            showQuickLook = true
        default: return false
        }
        return true
    }

    /// 다음 3장 원본 프리페치
    private func prefetchNext() {
        let assets = photoManager.allPhotos
        let start = session.currentIndex + 1
        let end = min(assets.count, start + 3)
        guard start < end else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let size = CGSize(width: 1200 * scale, height: 1200 * scale)
        ThumbnailCache.manager.startCachingImages(for: Array(assets[start..<end]),
                                                  targetSize: size, contentMode: .aspectFit,
                                                  options: ThumbnailCache.requestOptions())
    }

    private func metadataLine(_ asset: PHAsset) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy.MM.dd"
        let date = asset.creationDate.map { df.string(from: $0) } ?? "—"
        let dims = "\(asset.pixelWidth)×\(asset.pixelHeight)"
        let mb = fileSizeMB(asset)
        return mb.map { "\(date) · \(dims) · \(String(format: "%.1f", $0))MB" } ?? "\(date) · \(dims)"
    }

    private func fileSizeMB(_ asset: PHAsset) -> Double? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let res = resources.first,
              let bytes = res.value(forKey: "fileSize") as? Int64 else { return nil }
        return Double(bytes) / 1_048_576.0
    }
}

// MARK: - 대형 프리뷰 (2단계 로드)

private struct MacLargeImage: View {
    let asset: PHAsset
    @State private var image: NSImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(AppTheme.gracefulGold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { load() }
        .onChange(of: asset.localIdentifier) { _, _ in image = nil; load() }
        .onDisappear { if let rid = requestID { PHImageManager.default().cancelImageRequest(rid) } }
    }

    private func load() {
        if let rid = requestID { PHImageManager.default().cancelImageRequest(rid) }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic   // 저화질 즉시 → 고화질 교체 (2단계)
        options.isNetworkAccessAllowed = true
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let target = CGSize(width: 1400 * scale, height: 1400 * scale)
        let requested = asset.localIdentifier
        requestID = PHImageManager.default().requestImage(
            for: asset, targetSize: target, contentMode: .aspectFit, options: options
        ) { img, _ in
            Task { @MainActor in
                guard self.asset.localIdentifier == requested, let img else { return }
                self.image = img
            }
        }
    }
}

// MARK: - 필름스트립

private struct FilmstripView: View {
    @ObservedObject var session: ReviewSession
    @EnvironmentObject var photoManager: PhotoManager

    private let cell: CGFloat = 68

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(photoManager.allPhotos.enumerated()), id: \.element.localIdentifier) { i, asset in
                        cellView(asset: asset, index: i)
                            .id(i)
                            .onTapGesture { session.jump(to: i) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(height: cell + 20)
            .background(.ultraThinMaterial)
            .onChange(of: session.currentIndex) { _, i in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }

    private func cellView(asset: PHAsset, index: Int) -> some View {
        let isCurrent = index == session.currentIndex
        return MacAssetThumbnail(asset: asset, size: cell)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCurrent ? AppTheme.gracefulGold : Color.white.opacity(0.1),
                                  lineWidth: isCurrent ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) { statusIcon(asset) }
            .opacity(session.history[asset.localIdentifier] == .deleted ? 0.4 : 1)
            .draggable(asset.localIdentifier)   // 앨범/휴지통으로 드래그
    }

    @ViewBuilder
    private func statusIcon(_ asset: PHAsset) -> some View {
        switch session.history[asset.localIdentifier] {
        case .deleted:
            icon("trash.fill", .red)
        case .favorited:
            icon("heart.fill", AppTheme.gracefulGold)
        case .moved:
            icon("folder.fill", AppTheme.lavender)
        case .none:
            EmptyView()
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(3)
            .background(Circle().fill(.black.opacity(0.5)))
            .padding(3)
    }
}

// MARK: - 첫 실행 단축키 안내

private struct KeyGuideOverlay: View {
    let onClose: () -> Void
    @FocusState private var focused: Bool

    private let rows: [(String, String)] = [
        ("⌫", "휴지통으로 이동"),
        ("F", "즐겨찾기 토글"),
        ("⌘1 ~ ⌘9", "지정 앨범으로 이동"),
        ("← →", "이전 / 다음 사진"),
        ("Space", "크게 보기"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 16) {
                Text("리뷰 모드 단축키")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                ForEach(rows, id: \.0) { key, desc in
                    HStack(spacing: 16) {
                        Text(key)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(AppTheme.gracefulGold)
                            .frame(width: 100, alignment: .leading)
                        Text(desc).foregroundStyle(.white.opacity(0.9))
                    }
                }
                Text("아무 키나 눌러 시작하세요")
                    .font(.callout)
                    .foregroundStyle(AppTheme.subText)
                    .padding(.top, 4)
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.midPurple))
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress { _ in onClose(); return .handled }
    }
}
