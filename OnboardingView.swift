import SwiftUI
import Photos

// MARK: - 온보딩 진입점
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var currentPage = 0
    @State private var permissionStatus: PHAuthorizationStatus = .notDetermined

    private let totalPages = 5

    var body: some View {
        ZStack {
            // 배경 (은혜의교회 퍼플)
            AppTheme.mainPurple
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 페이지 콘텐츠
                TabView(selection: $currentPage) {
                    OnboardingWelcomePage().tag(0)
                    OnboardingAnalysisPage().tag(1)
                    OnboardingGesturePage().tag(2)
                    OnboardingArchivePage().tag(3)
                    OnboardingPermissionPage(
                        permissionStatus: $permissionStatus,
                        onFinish: onFinish
                    ).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.35), value: currentPage)

                // 하단 네비게이션
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            permissionStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
    }

    private var bottomBar: some View {
        HStack {
            // 페이지 인디케이터
            HStack(spacing: 6) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? Color.white : Color.white.opacity(0.25))
                        .frame(width: i == currentPage ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            Spacer()

            // 다음/시작 버튼
            if currentPage < totalPages - 1 {
                Button {
                    withAnimation { currentPage += 1 }
                } label: {
                    HStack(spacing: 6) {
                        Text("다음")
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 20)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                }
            }
            // 마지막 페이지 버튼은 OnboardingPermissionPage 내부에서 처리
        }
        .padding(.top, 16)
    }
}

// MARK: - 페이지 1: 환영
struct OnboardingWelcomePage: View {
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 로고 애니메이션
            ZStack {
                // 외곽 광환
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.04 - Double(i) * 0.01), lineWidth: 1)
                        .frame(width: CGFloat(120 + i * 36), height: CGFloat(120 + i * 36))
                        .scaleEffect(appear ? 1 : 0.7)
                        .animation(.easeOut(duration: 0.8).delay(Double(i) * 0.15), value: appear)
                }

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 110, height: 110)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .white.opacity(0.08), radius: 20)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
            }
            .scaleEffect(appear ? 1 : 0.6)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.7, dampingFraction: 0.7), value: appear)

            Spacer().frame(height: 40)

            // 타이틀
            VStack(spacing: 10) {
                Text("ZAKAR")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(4)

                Text("자카르")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .tracking(8)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 1)
                    .padding(.vertical, 4)

                Text("모든 은혜를 기억합니다")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .offset(y: appear ? 0 : 20)
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: appear)

            Spacer().frame(height: 48)

            // 소개 문구
            VStack(spacing: 14) {
                welcomeFeature(icon: "clock.arrow.circlepath", text: "교회의 소중한 순간들을 체계적으로 기록")
                welcomeFeature(icon: "person.3.fill", text: "동역자들의 삶과 섬김을 영구 보존")
                welcomeFeature(icon: "heart.fill", text: "받은 은혜와 감사를 언제나 기억")
            }
            .offset(y: appear ? 0 : 30)
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.5), value: appear)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear { appear = true }
    }

    private func welcomeFeature(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
            Spacer()
        }
    }
}

// MARK: - 페이지 2: 유사 사진 자동 분석 시뮬레이션
struct OnboardingAnalysisPage: View {
    @State private var phase = 0  // 0: 흩어짐 → 1: 스캔 → 2: 그룹핑 → 3: 완료
    @State private var scanProgress: CGFloat = 0
    @State private var appear = false

    // 더미 사진 타일 데이터
    private let photos: [(color: Color, group: Int)] = [
        (.blue.opacity(0.7), 0), (.blue.opacity(0.55), 0), (.blue.opacity(0.8), 0),
        (.green.opacity(0.7), 1), (.green.opacity(0.55), 1),
        (.orange.opacity(0.7), 2), (.orange.opacity(0.6), 2), (.orange.opacity(0.8), 2),
        (.purple.opacity(0.6), 3), (.purple.opacity(0.75), 3),
        (.red.opacity(0.5), 4), (.teal.opacity(0.6), 5),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            // 헤더
            VStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(appear ? 1 : 0)
                    .animation(.easeOut(duration: 0.5), value: appear)

                Text("유사 사진 자동 분석")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("같은 순간에 찍은 사진들을 AI가\n자동으로 묶어서 보여줍니다")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: appear)

            Spacer().frame(height: 32)

            // 시뮬레이션 영역
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.8))

                if phase < 2 {
                    // 사진 그리드 (스캔 전/중)
                    VStack(spacing: 6) {
                        if phase == 1 {
                            // 스캔 바
                            HStack(spacing: 6) {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                Text("유사도 분석 중...")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                                Spacer()
                                Text("\(Int(scanProgress * 100))%")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 12)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 3)
                                    Capsule().fill(Color.blue)
                                        .frame(width: geo.size.width * scanProgress, height: 3)
                                }
                            }
                            .frame(height: 3)
                            .padding(.horizontal, 12)
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                            ForEach(photos.indices, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(photos[i].color)
                                    .frame(height: 52)
                                    .overlay(
                                        phase == 1
                                        ? RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                                            .opacity(Double.random(in: 0.3...1.0))
                                        : nil
                                    )
                                    .scaleEffect(phase == 1 && Int.random(in: 0...3) == 0 ? 0.95 : 1.0)
                                    .animation(.easeInOut(duration: 0.3).repeatForever(), value: phase)
                            }
                        }
                        .padding(12)
                    }
                } else {
                    // 그룹핑 결과
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(groupedData, id: \.0) { groupID, groupPhotos in
                                HStack(spacing: 6) {
                                    Text("\(groupPhotos.count)장 유사")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(width: 58, alignment: .leading)

                                    HStack(spacing: 4) {
                                        ForEach(groupPhotos.indices, id: \.self) { i in
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(groupPhotos[i])
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                                )
                                                .scaleEffect(phase == 3 ? 1 : 0.5)
                                                .opacity(phase == 3 ? 1 : 0)
                                                .animation(.spring(response: 0.4, dampingFraction: 0.7)
                                                    .delay(Double(i) * 0.06 + Double(groupID) * 0.1), value: phase)
                                        }
                                        Spacer()

                                        if phase == 3 {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.3))
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal, 10)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .frame(height: 240)
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // 재시작 버튼
            Button {
                restartAnimation()
            } label: {
                Label("다시 보기", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .onAppear {
            appear = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                startAnimation()
            }
        }
    }

    private var groupedData: [(Int, [Color])] {
        var result: [(Int, [Color])] = []
        let grouped = Dictionary(grouping: photos.filter { $0.group < 4 }, by: { $0.group })
        for key in grouped.keys.sorted() {
            result.append((key, grouped[key]!.map { $0.color }))
        }
        return result
    }

    private func startAnimation() {
        // 1단계: 스캔 시작
        withAnimation { phase = 1 }
        withAnimation(.linear(duration: 1.8)) { scanProgress = 1.0 }

        // 2단계: 그룹핑
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { phase = 2 }
        }
        // 3단계: 등장 애니메이션
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { phase = 3 }
        }
    }

    private func restartAnimation() {
        phase = 0
        scanProgress = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            startAnimation()
        }
    }
}

// MARK: - 페이지 3: 제스처 인터랙티브 시뮬레이션
struct OnboardingGesturePage: View {
    @State private var offset: CGSize = .zero
    @State private var currentAction: GestureAction = .idle
    @State private var cardScale: CGFloat = 1.0
    @State private var feedbackText = "사진을 직접 스와이프해보세요"
    @State private var feedbackColor = Color.white.opacity(0.5)
    @State private var demoPhotoIndex = 0
    @State private var showSuccess = false
    @State private var appear = false

    enum GestureAction { case idle, trashing, favoriting, nextPhoto, prevPhoto }

    // 데모용 그라디언트 카드 색상
    private let demoColors: [LinearGradient] = [
        LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.green.opacity(0.5), .teal.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.orange.opacity(0.6), .red.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.pink.opacity(0.5), .purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            // 헤더
            VStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                Text("스와이프로 빠르게 정리")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("직접 스와이프해보세요")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: appear)

            Spacer().frame(height: 24)

            // 제스처 가이드 4개
            HStack(spacing: 0) {
                gestureGuide(icon: "arrow.up", label: "삭제", color: .red)
                gestureGuide(icon: "arrow.down", label: "즐겨찾기", color: .yellow)
                gestureGuide(icon: "arrow.left", label: "다음", color: .blue)
                gestureGuide(icon: "arrow.right", label: "이전", color: .green)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 20)

            // 인터랙티브 카드
            ZStack {
                // 배경 카드 (다음 사진 암시)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(demoColors[(demoPhotoIndex + 1) % demoColors.count])
                    .frame(width: 240, height: 300)
                    .scaleEffect(0.95)
                    .opacity(0.5)

                // 메인 카드
                ZStack {
                    demoColors[demoPhotoIndex % demoColors.count]
                    
                    // 사진 번호
                    VStack {
                        Spacer()
                        Text("사진 \(demoPhotoIndex + 1)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.bottom, 16)
                    }

                    // 액션 오버레이 아이콘
                    if currentAction == .trashing {
                        actionOverlay(icon: "trash.fill", color: .red)
                    } else if currentAction == .favoriting {
                        actionOverlay(icon: "star.fill", color: .yellow)
                    } else if currentAction == .nextPhoto {
                        actionOverlay(icon: "arrow.right.circle.fill", color: .blue)
                    } else if currentAction == .prevPhoto {
                        actionOverlay(icon: "arrow.left.circle.fill", color: .green)
                    }
                }
                .frame(width: 240, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                .scaleEffect(cardScale)
                .offset(offset)
                .rotationEffect(.degrees(Double(offset.width) / 20))
                .gesture(
                    DragGesture()
                        .onChanged { g in
                            offset = g.translation
                            updateAction(from: g.translation)
                        }
                        .onEnded { g in
                            handleGestureEnd(g.translation)
                        }
                )
            }
            .frame(height: 320)

            Spacer().frame(height: 16)

            // 피드백 텍스트
            Text(feedbackText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(feedbackColor)
                .animation(.easeInOut(duration: 0.2), value: feedbackText)
                .multilineTextAlignment(.center)
                .frame(height: 20)

            Spacer()
        }
        .onAppear { appear = true }
    }

    private func gestureGuide(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .clipShape(Circle())
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func actionOverlay(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 52, weight: .semibold))
            .foregroundColor(color)
            .shadow(color: color.opacity(0.5), radius: 12)
            .transition(.scale.combined(with: .opacity))
    }

    private func updateAction(from translation: CGSize) {
        let v = translation.height
        let h = translation.width
        if abs(v) > abs(h) {
            currentAction = v < -40 ? .trashing : (v > 40 ? .favoriting : .idle)
        } else {
            currentAction = h < -40 ? .nextPhoto : (h > 40 ? .prevPhoto : .idle)
        }
        withAnimation(.spring(response: 0.3)) {
            cardScale = 0.97
        }
    }

    private func handleGestureEnd(_ translation: CGSize) {
        let v = translation.height
        let h = translation.width

        if v < -100 {
            // 삭제
            triggerFeedback("휴지통에 임시 보관됩니다", color: .red)
            flyOut(direction: CGSize(width: 0, height: -600))
        } else if v > 80 {
            // 즐겨찾기
            triggerFeedback("⭐ 즐겨찾기에 추가됩니다", color: .yellow)
            resetCard()
        } else if h < -60 {
            // 다음
            triggerFeedback("다음 사진", color: .blue)
            flyOut(direction: CGSize(width: -500, height: 0))
        } else if h > 60 {
            // 이전
            triggerFeedback("이전 사진", color: .green)
            flyOut(direction: CGSize(width: 500, height: 0))
        } else {
            resetCard()
            feedbackText = "사진을 직접 스와이프해보세요"
            feedbackColor = .white.opacity(0.5)
        }
    }

    private func flyOut(direction: CGSize) {
        withAnimation(.easeIn(duration: 0.22)) {
            offset = direction
            cardScale = 0.85
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            demoPhotoIndex = (demoPhotoIndex + 1) % demoColors.count
            offset = .zero
            cardScale = 0.85
            currentAction = .idle
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                cardScale = 1.0
            }
        }
    }

    private func resetCard() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            offset = .zero
            cardScale = 1.0
            currentAction = .idle
        }
    }

    private func triggerFeedback(_ text: String, color: Color) {
        feedbackText = text
        feedbackColor = color
    }
}

// MARK: - 페이지 4: 아카이브 소개
struct OnboardingArchivePage: View {
    @State private var uploadPhase = 0   // 0: 대기 → 1: 업로드 중 → 2: 완료
    @State private var progress: CGFloat = 0
    @State private var appear = false

    private let fileList = [
        ("예배_20250101_001.heic", "3.2 MB"),
        ("수련회_20250215_042.heic", "4.1 MB"),
        ("성탄절_20241224_089.heic", "2.8 MB"),
        ("부활절_20240331_017.heic", "3.7 MB"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            VStack(spacing: 8) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
                Text("안전한 아카이브")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Synology NAS 또는 Google Drive에\n자동으로 백업·보관합니다")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: appear)

            Spacer().frame(height: 28)

            // 업로드 시뮬레이션 카드
            VStack(alignment: .leading, spacing: 14) {
                // 연결 상태
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(uploadPhase > 0 ? .green : .white.opacity(0.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Synology NAS")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text(uploadPhase == 0 ? "연결 대기 중..." : "192.168.1.100 · 연결됨")
                            .font(.system(size: 11))
                            .foregroundColor(uploadPhase > 0 ? .green.opacity(0.9) : .white.opacity(0.4))
                    }
                    Spacer()
                    Circle()
                        .fill(uploadPhase > 0 ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .shadow(color: uploadPhase > 0 ? .green.opacity(0.6) : .clear, radius: 4)
                }

                Divider().background(Color.white.opacity(0.1))

                // 파일 목록
                VStack(spacing: 8) {
                    ForEach(fileList.indices, id: \.self) { i in
                        HStack(spacing: 10) {
                            Image(systemName: uploadIcon(for: i))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(uploadColor(for: i))
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(fileList[i].0)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)
                                Text(fileList[i].1)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            Spacer()

                            if uploadPhase == 1 && i == currentUploadIndex {
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue.opacity(0.8))
                            } else if uploadPhase == 2 || (uploadPhase == 1 && i < currentUploadIndex) {
                                Text("완료")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.green.opacity(0.8))
                            }
                        }

                        // 진행 바
                        if uploadPhase >= 1 && i <= currentUploadIndex {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 2)
                                    Capsule()
                                        .fill(i < currentUploadIndex || uploadPhase == 2 ? Color.green : Color.blue)
                                        .frame(width: geo.size.width * (i < currentUploadIndex || uploadPhase == 2 ? 1.0 : progress), height: 2)
                                        .animation(.easeInOut(duration: 0.1), value: progress)
                                }
                            }
                            .frame(height: 2)
                            .padding(.leading, 28)
                        }
                    }
                }

                // 전체 완료 메시지
                if uploadPhase == 2 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text("4장이 NAS에 안전하게 보관되었습니다")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green.opacity(0.9))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.8))
            )
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)

            // 재시작 버튼
            Button { restartUpload() } label: {
                Label("다시 보기", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .onAppear {
            appear = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { startUpload() }
        }
    }

    private var currentUploadIndex: Int {
        // progress와 phase로 현재 업로드 중인 파일 인덱스 추정
        guard uploadPhase == 1 else { return uploadPhase == 2 ? fileList.count : -1 }
        return min(Int(progress * Double(fileList.count) / 0.9), fileList.count - 1)
    }

    private func uploadIcon(for index: Int) -> String {
        if uploadPhase == 0 { return "clock" }
        if uploadPhase == 2 || index < currentUploadIndex { return "checkmark.circle.fill" }
        if index == currentUploadIndex { return "arrow.up.circle" }
        return "clock"
    }

    private func uploadColor(for index: Int) -> Color {
        if uploadPhase == 0 { return .white.opacity(0.3) }
        if uploadPhase == 2 || index < currentUploadIndex { return .green }
        if index == currentUploadIndex { return .blue }
        return .white.opacity(0.3)
    }

    private func startUpload() {
        withAnimation { uploadPhase = 1 }
        withAnimation(.linear(duration: 3.5)) { progress = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) {
            withAnimation { uploadPhase = 2 }
        }
    }

    private func restartUpload() {
        uploadPhase = 0
        progress = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { startUpload() }
    }
}

// MARK: - 페이지 5: 권한 요청 + 시작
struct OnboardingPermissionPage: View {
    @Binding var permissionStatus: PHAuthorizationStatus
    var onFinish: () -> Void
    @State private var isRequesting = false
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 아이콘
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                Image(systemName: permissionGranted ? "checkmark.shield.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(permissionGranted ? .green : .white)
            }
            .scaleEffect(appear ? 1 : 0.7)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appear)

            Spacer().frame(height: 28)

            VStack(spacing: 10) {
                Text(permissionGranted ? "준비 완료!" : "사진 접근 권한")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(permissionMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: appear)

            Spacer().frame(height: 36)

            // 권한 요청 / 시작 버튼
            VStack(spacing: 12) {
                if !permissionGranted {
                    Button(action: requestPermission) {
                        HStack(spacing: 8) {
                            if isRequesting {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Text(isRequesting ? "요청 중..." : "사진 접근 허용하기")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(isRequesting)
                    .padding(.horizontal, 24)
                }

                Button(action: onFinish) {
                    Text(permissionGranted ? "ZAKAR 시작하기" : "나중에 설정하기")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(permissionGranted ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(permissionGranted
                            ? Color.white
                            : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            permissionGranted ? nil :
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .padding(.horizontal, 24)
            }
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.35), value: appear)

            Spacer()

            // 하단 안내
            Text("사진 권한은 유사 사진 분석과 정리에만 사용됩니다.\n언제든 설정에서 변경할 수 있습니다.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.5), value: appear)
        }
        .onAppear { appear = true }
    }

    private var permissionGranted: Bool {
        permissionStatus == .authorized || permissionStatus == .limited
    }

    private var permissionMessage: String {
        switch permissionStatus {
        case .authorized, .limited:
            return "사진 접근 권한이 허용되었어요.\n이제 ZAKAR를 바로 시작할 수 있습니다."
        case .denied, .restricted:
            return "설정 > 개인정보 보호 > 사진에서\n접근을 허용해주세요."
        default:
            return "유사 사진 분석과 앨범 정리를 위해\n사진 접근 권한이 필요합니다."
        }
    }

    private func requestPermission() {
        guard !isRequesting else { return }
        isRequesting = true
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                permissionStatus = status
                isRequesting = false
            }
        }
    }
}

#Preview {
    OnboardingView { }
}
