import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var photoManager: PhotoManager
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
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
            .tint(AppTheme.gracefulGold)
            .preferredColorScheme(.dark)
            
            // 온보딩 화면이 표시될 때까지 로딩 인디케이터 표시
            if showOnboarding {
                Color.black
                    .ignoresSafeArea()
                    .overlay(
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    )
            }
        }
        .task {
            // task는 비동기로 실행되므로 UI 블로킹 방지
            showOnboarding = !LocalDB.shared.isOnboardingCompleted()
            
            // 온보딩이 완료된 경우에만 사진 로드
            if !showOnboarding {
                print("🟢 ZAKAR Log: Onboarding completed - loading photos")
                await loadPhotosAsync()
            }
        }
        // 앱을 백그라운드에 둔 사이 찍거나 지운 사진을 반영 (돌아올 때 전체 장수가 달라졌으면 다시 읽음)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !showOnboarding { photoManager.refreshIfLibraryChanged() }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                LocalDB.shared.setOnboardingCompleted(true)
                showOnboarding = false
                
                // 온보딩 완료 후 사진 로드
                print("🟢 ZAKAR Log: Onboarding finished - loading photos")
                Task {
                    await loadPhotosAsync()
                }
            }
        }
    }
    
    // 비동기 사진 로딩 함수
    private func loadPhotosAsync() async {
        photoManager.fetchPhotos()
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1초 대기
        photoManager.analyzeSimilaritiesIfNeeded()
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthService())
        .environmentObject(PhotoManager())
}
