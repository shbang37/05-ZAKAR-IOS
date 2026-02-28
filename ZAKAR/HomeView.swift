import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var metadata: AppMetadata = LocalDB.shared.loadMetadata()

    // 은혜의 새벽 테마 배경
    private var backgroundGradient: LinearGradient {
        AppTheme.backgroundGradient
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        headerSection

                        summarySection
                            .padding(.horizontal)

                        navigationSections
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("홈")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            photoManager.analyzeSimilaritiesIfNeeded()
            // 정리 통계 최신화 (삭제 후 돌아왔을 때 반영)
            metadata = LocalDB.shared.loadMetadata()
        }
    }

    // MARK: - Sub Views
    
    // 1. 상단 로고 및 타이틀 분리 (은혜의 새벽 테마)
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.gracefulGold, AppTheme.dawnPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                )
                .shadow(color: AppTheme.gracefulGold.opacity(0.25), radius: 10, x: 0, y: 0)
                .shadow(color: AppTheme.dawnPurple.opacity(0.20), radius: 15, x: 0, y: 4)
                .accessibilityLabel("ZAKAR 로고")

            Text("ZAKAR")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.dualGradient)

            Text("모든 은혜를 기억합니다")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppTheme.gracefulGold.opacity(0.9), AppTheme.dawnPurple.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .padding(.top, 12)
    }

    // 2. 요약 카드 섹션 분리
    private var summarySection: some View {
        HomeSummaryCard(
            groupsCount: photoManager.groupedPhotos.count,
            lastCleanupDate: metadata.lastCleanupDate,
            estimatedSavedMB: metadata.estimatedSavedMB
        )
    }

    // 3. 주요 네비게이션 링크 섹션 분리
    private var navigationSections: some View {
        Group {
            NavigationLink(destination: ContentView(initialTab: 1)) {
                GlassSectionCard(
                    title: "모든 사진",
                    subtitle: "필요 없는 사진을 손쉽게 정리",
                    icon: "photo.stack",
                    count: photoManager.allPhotos.count,
                    isLoading: photoManager.isLoadingList
                )
            }

            NavigationLink(destination: ContentView(initialTab: 0).id(UUID())) {
                GlassSectionCard(
                    title: "유사 사진",
                    subtitle: "비슷한 사진들을 모아서 빠르게 확인",
                    icon: "square.on.square.dashed",
                    count: photoManager.groupedPhotos.reduce(0) { $0 + $1.count },
                    isLoading: photoManager.isAnalyzing
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

private struct GlassSectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let count: Int
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.goldenGradient)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.dawnPurple.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.7))
            }

            Spacer()

            // 개수 표시
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(AppTheme.dawnPurple.opacity(0.6))
                        .scaleEffect(0.7)
                } else if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.dualGradient)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.gracefulGold.opacity(0.5))
            }
        }
        .padding(16)
        .background(GlassCard(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

