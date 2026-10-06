import SwiftUI

// ============================================================
// Mac 사이드바 네비게이션 모델
// ============================================================

enum MacDestination: Hashable {
    case allPhotos
    case similarGroups
    /// 사이드바 항목이 아니라 "모든 사진" 안의 리뷰 보기 — 키 처리 범위 구분용으로만 쓴다
    case review
    case favorites
    case album(id: String)
    case trash
}

/// 아직 구현되지 않은 화면의 자리표시 (후속 Phase에서 교체)
struct MacPlaceholderView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppTheme.gracefulGold.opacity(0.85))
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(AppTheme.subText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
