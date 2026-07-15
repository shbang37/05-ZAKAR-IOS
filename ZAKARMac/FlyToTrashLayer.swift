import SwiftUI
import Photos
import AppKit
import Combine

// ============================================================
// 흡입 애니메이션 (fly-to-trash)
// iOS CleanUpView.flyToTrash 계승: spring stiffness 240 / damping 26,
// 도착 340ms → 배지 펄스. 표시 전용 스냅샷을 루트 단일 좌표계에서 비행시켜
// 데이터 커밋(즉시)과 애니메이션을 분리 — 연타가 애니메이션을 기다리지 않는다.
// ============================================================

extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }

// MARK: - 비행 아이템

struct FlyingItem: Identifiable {
    let id = UUID()
    let assetLocalID: String
    let startFrame: CGRect
}

@MainActor
final class FlyToTrashController: ObservableObject {
    // 프레임은 비발행(fly 시점에만 읽음) — 레이아웃 보고가 리렌더를 유발하지 않게
    var trashIconFrame: CGRect = .zero
    var cardFrames: [String: CGRect] = [:]
    @Published var flying: [FlyingItem] = []
    @Published var badgePulse: Int = 0     // 도착 시 증가 → 사이드바 배지 펄스

    func setTrashFrame(_ f: CGRect) { if f != .zero { trashIconFrame = f } }
    func setCardFrame(_ id: String, _ f: CGRect) { cardFrames[id] = f }

    /// 삭제 대상들을 60ms stagger로 흡입 발사 (Reduce Motion이면 즉시 배지 펄스만)
    func fly(assets: [PHAsset], reduceMotion: Bool) {
        guard !reduceMotion, trashIconFrame != .zero else {
            badgePulse += 1
            return
        }
        for (i, asset) in assets.enumerated() {
            let id = asset.localIdentifier
            guard let frame = cardFrames[id], frame != .zero else { continue }
            let item = FlyingItem(assetLocalID: id, startFrame: frame)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) { [weak self] in
                self?.flying.append(item)
            }
        }
    }

    func remove(_ item: FlyingItem) {
        flying.removeAll { $0.id == item.id }
        badgePulse += 1
    }
}

// MARK: - 루트 오버레이 레이어

struct FlyToTrashLayer: View {
    @ObservedObject var controller: FlyToTrashController

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(controller.flying) { item in
                FlyingItemView(item: item,
                               target: controller.trashIconFrame.center,
                               onArrived: { controller.remove(item) })
            }
        }
        // 윈도우 전체를 채워 로컬 좌표계 원점 = root 원점으로 정렬
        // (내용 크기로 축소되면 .position이 중앙 기준이 되어 어긋남)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

private struct FlyingItemView: View {
    let item: FlyingItem
    let target: CGPoint
    let onArrived: () -> Void

    @State private var pos: CGPoint
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    @State private var image: NSImage?

    init(item: FlyingItem, target: CGPoint, onArrived: @escaping () -> Void) {
        self.item = item
        self.target = target
        self.onArrived = onArrived
        _pos = State(initialValue: item.startFrame.center)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10).fill(AppTheme.darkPurple)
            }
        }
        .frame(width: item.startFrame.width, height: item.startFrame.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .scaleEffect(scale)
        .opacity(opacity)
        .position(pos)
        .onAppear { start() }
    }

    private func start() {
        loadThumbnail()
        // 흡입 비행 — iOS CleanUpView.flyToTrash 계승 (stiffness 240 / damping 26)
        withAnimation(.interpolatingSpring(stiffness: 240, damping: 26)) {
            pos = target
            scale = 0.12
        }
        // 180ms 후부터 150ms 페이드아웃
        withAnimation(.easeOut(duration: 0.15).delay(0.18)) {
            opacity = 0
        }
        // 도착 340ms → 제거 + 배지 펄스
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            onArrived()
        }
    }

    private func loadThumbnail() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let target = CGSize(width: item.startFrame.width * scale, height: item.startFrame.height * scale)
        // 방금 카드가 표시하던 썸네일 → 공유 캐시 적중(즉시)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [item.assetLocalID], options: nil)
        guard let asset = fetch.firstObject else { return }
        ThumbnailCache.manager.requestImage(for: asset, targetSize: target,
                                            contentMode: .aspectFill,
                                            options: ThumbnailCache.requestOptions()) { img, _ in
            Task { @MainActor in self.image = img }
        }
    }
}

// MARK: - 프레임 리포트 modifier

extension View {
    /// 카드 프레임을 root 좌표계로 컨트롤러에 보고 (흡입 시작 위치)
    /// preference는 NavigationSplitView 경계를 넘어 전파가 불안정 → onChange 직접 보고.
    func reportCardFrame(id: String, to controller: FlyToTrashController) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { controller.setCardFrame(id, geo.frame(in: .named("root"))) }
                    .onChange(of: geo.frame(in: .named("root"))) { _, f in controller.setCardFrame(id, f) }
            }
        )
    }

    /// 휴지통 아이콘 프레임을 root 좌표계로 컨트롤러에 보고 (흡입 도착 위치)
    func reportTrashIconFrame(to controller: FlyToTrashController) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { controller.setTrashFrame(geo.frame(in: .named("root"))) }
                    .onChange(of: geo.frame(in: .named("root"))) { _, f in controller.setTrashFrame(f) }
            }
        )
    }
}
