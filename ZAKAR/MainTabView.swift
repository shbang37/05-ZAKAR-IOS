import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var selectedTab = 0
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("홈")
                }
                .tag(0)

            AlbumsView()
                .tabItem {
                    Image(systemName: "folder")
                    Text("앨범")
                }
                .tag(1)

            ArchiveView()
                .tabItem {
                    Image(systemName: "externaldrive.connected.to.line.below")
                    Text("아카이브")
                }
                .tag(2)

            // 내 정보 / 로그아웃 탭
            ProfileView()
                .tabItem {
                    Image(systemName: "person.crop.circle")
                    Text("내 정보")
                }
                .tag(3)
        }
        .onAppear { showOnboarding = !LocalDB.shared.isOnboardingCompleted() }
        .tint(AppTheme.dawnPurple)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                LocalDB.shared.setOnboardingCompleted(true)
                showOnboarding = false
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
}
