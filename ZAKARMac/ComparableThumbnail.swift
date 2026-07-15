import SwiftUI
import Photos

// ============================================================
// ComparableThumbnail — 그룹 비교 모드의 사진 카드
// 상태: 대표(골드 보더+글로우+★) / 유지 / 삭제(desaturate+dim+✕)
// 상호작용: hover 확대(1.04/120ms), 클릭=유지·삭제 토글, ★=대표 교체
// 핸드오프 값: radius14, bg #403858, border 2px, saturate0.4·brightness0.72
// ============================================================

struct ComparableThumbnail: View {
    let asset: PHAsset
    let size: CGFloat
    let isRepresentative: Bool
    let isKept: Bool
    let onToggle: () -> Void
    let onMakeRepresentative: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDelete: Bool { !isKept }

    private var a11yLabel: String {
        let state = isRepresentative ? "대표" : (isDelete ? "삭제 예정" : "유지")
        return "사진, \(state)"
    }

    var body: some View {
        VStack(spacing: 8) {
            thumbnail
            caption
        }
        .scaleEffect(hovering && !reduceMotion ? 1.04 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(isRepresentative ? "이미 대표입니다" : "클릭하면 유지·삭제 전환")
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.darkPurple)   // #403858

            MacAssetThumbnail(asset: asset, size: size)
                .saturation(isDelete ? 0.4 : 1.0)
                .overlay {
                    // brightness 0.72 근사 — 삭제 상태 어둡게
                    Color.black.opacity(isDelete ? 0.28 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(2)

            // 상태 오버레이
            if isRepresentative {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(AppTheme.gracefulGold, lineWidth: 3)
                badge(text: "★ 대표", bg: AppTheme.gracefulGold, fg: AppTheme.deepPurple, alignment: .topLeading)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 2)
                if isDelete {
                    deleteOverlay
                } else {
                    badge(text: "유지", bg: .white.opacity(0.85), fg: AppTheme.deepPurple, alignment: .topLeading)
                }
            }

            // hover 시 대표 지정 버튼 (비대표 카드만)
            if hovering && !isRepresentative {
                VStack {
                    Spacer()
                    Button(action: onMakeRepresentative) {
                        Label("대표로", systemImage: "star")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.gracefulGold))
                            .foregroundStyle(AppTheme.deepPurple)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: isRepresentative ? AppTheme.gracefulGold.opacity(0.5) : .clear,
                radius: isRepresentative ? 16 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onToggle() }
    }

    private var deleteOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .red.opacity(0.85))
                    .padding(8)
            }
            Spacer()
        }
    }

    private func badge(text: String, bg: Color, fg: Color, alignment: Alignment) -> some View {
        VStack {
            HStack {
                Text(text)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(bg))
                    .foregroundStyle(fg)
                Spacer()
            }
            Spacer()
        }
        .padding(8)
    }

    private var caption: some View {
        Text(isDelete ? "삭제 예정" : (isRepresentative ? "대표" : "유지"))
            .font(.caption2)
            .foregroundStyle(isDelete ? Color.red.opacity(0.9) : AppTheme.subText)
    }
}
