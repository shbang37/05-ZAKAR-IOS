import SwiftUI

// MARK: - 홈 요약 카드
struct HomeSummaryCard: View {
    var groupsCount: Int
    var lastCleanupDate: Date?
    var estimatedSavedMB: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 헤더
            HStack {
                Label("요약", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.dualGradient)
                Spacer()
            }

            Divider()
                .background(AppTheme.gracefulGold.opacity(0.2))

            // 통계 3개
            HStack(spacing: 0) {
                summaryItem(
                    icon: "square.on.square",
                    title: "정리 대상",
                    value: "\(groupsCount)그룹",
                    color: groupsCount > 0 ? AppTheme.gracefulGold : .white
                )

                summaryDivider

                summaryItem(
                    icon: "calendar",
                    title: "최근 정리",
                    value: lastCleanupText,
                    color: AppTheme.lightPurple
                )

                summaryDivider

                summaryItem(
                    icon: "internaldrive",
                    title: "절감(추정)",
                    value: savedText,
                    color: AppTheme.gracefulGold
                )
            }
        }
        .padding(18)
        .background(GlassCard(cornerRadius: 22))
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5)
            .padding(.vertical, 4)
    }

    private var lastCleanupText: String {
        guard let date = lastCleanupDate else { return "없음" }
        let daysAgo = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysAgo == 0 { return "오늘" }
        if daysAgo <= 7 { return "\(daysAgo)일 전" }
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f.string(from: date)
    }

    private var savedText: String {
        guard let mb = estimatedSavedMB, mb > 0 else { return "—" }
        return mb >= 1024
            ? String(format: "%.1fGB", mb / 1024)
            : String(format: "%.0fMB", mb)
    }

    private func summaryItem(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color.opacity(0.85))

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.black, Color(red: 0.08, green: 0.09, blue: 0.12)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        HomeSummaryCard(groupsCount: 12, lastCleanupDate: .now, estimatedSavedMB: 320)
            .padding()
    }
}
