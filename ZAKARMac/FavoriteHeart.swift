import SwiftUI

// ============================================================
// FavoriteHeart — 즐겨찾기 표시 배지
// 모든 화면(모든 사진·앨범·리뷰·그룹 비교·즐겨찾기)이 같은 모양을 쓴다.
// action이 있으면 눌러서 해제할 수 있는 버튼이 된다.
// ============================================================

struct FavoriteHeart: View {
    var size: Font = .caption
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { heart }
                    .buttonStyle(.plain)
                    .help("즐겨찾기 해제")
                    .accessibilityLabel("즐겨찾기 해제")
            } else {
                heart.accessibilityHidden(true)
            }
        }
    }

    private var heart: some View {
        Image(systemName: "heart.fill")
            .font(size)
            .foregroundStyle(AppTheme.gracefulGold)
            .padding(5)
            .background(Circle().fill(.black.opacity(0.55)))
    }
}
