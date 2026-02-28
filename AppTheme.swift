import SwiftUI

/// 은혜의 새벽 테마
/// "Scars into Stars" - 은혜의교회 브랜드 아이덴티티를 담은 컬러 시스템
struct AppTheme {
    
    // MARK: - Primary Colors (골든 - 은혜의 빛)
    
    /// 은혜로운 골드 - 주요 액션, 중요한 요소
    static let gracefulGold = Color(red: 0.91, green: 0.66, blue: 0.49)  // #E8A87C
    
    /// 깊은 골드 - 그라디언트 보조
    static let deepGold = Color(red: 0.83, green: 0.69, blue: 0.22)  // #D4AF37
    
    // MARK: - Secondary Colors (퍼플 - 새벽 예배)
    
    /// 새벽 퍼플 - 보조 액션, 앨범 선택
    static let dawnPurple = Color(red: 0.62, green: 0.48, blue: 0.92)  // #9F7AEA
    
    /// 미드나잇 퍼플 - 그라디언트 보조
    static let midnightPurple = Color(red: 0.49, green: 0.23, blue: 0.93)  // #7C3AED
    
    // MARK: - Background Colors (새벽 하늘)
    
    /// 배경 시작 - 딥 퍼플
    static let bgDeepPurple = Color(red: 0.10, green: 0.09, blue: 0.15)  // #1A1625
    
    /// 배경 중간 - 퍼플 네이비
    static let bgPurpleNavy = Color(red: 0.12, green: 0.11, blue: 0.18)  // #1E1B2E
    
    /// 배경 끝 - 미드나잇 퍼플
    static let bgMidnightPurple = Color(red: 0.15, green: 0.13, blue: 0.21)  // #252035
    
    // MARK: - Accent Colors
    
    /// 딥 인디고 - 중립적 강조
    static let deepIndigo = Color(red: 0.29, green: 0.33, blue: 0.41)  // #4A5568
    
    /// 웜 그레이 - 서브 텍스트
    static let warmGray = Color(red: 0.42, green: 0.45, blue: 0.50)  // #6B7280
    
    /// 민트 그린 - 개별 사진 선택 모드
    static let softMint = Color(red: 0.51, green: 0.90, blue: 0.85)  // #81E6D9
    
    // MARK: - Gradients
    
    /// 배경 그라디언트 - 새벽 하늘
    static let backgroundGradient = LinearGradient(
        colors: [bgDeepPurple, bgPurpleNavy, bgMidnightPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// 골든 그라디언트 - 주요 버튼, 진행 바
    static let goldenGradient = LinearGradient(
        colors: [gracefulGold, deepGold],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    /// 퍼플 그라디언트 - 보조 버튼, 앨범 모드
    static let purpleGradient = LinearGradient(
        colors: [dawnPurple, midnightPurple],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    /// 듀얼 그라디언트 - 골든 → 퍼플 (특별한 요소)
    static let dualGradient = LinearGradient(
        colors: [gracefulGold, dawnPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// 카드 배경 그라디언트 - 퍼플 틴트
    static let cardFillGradient = LinearGradient(
        colors: [
            dawnPurple.opacity(0.06),
            Color.white.opacity(0.04)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// 카드 테두리 그라디언트 - 골든 → 퍼플 → 흰색
    static let cardStrokeGradient = LinearGradient(
        colors: [
            gracefulGold.opacity(0.40),
            dawnPurple.opacity(0.25),
            Color.white.opacity(0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// 민트 그라디언트 - 개별 사진 모드
    static let mintGradient = LinearGradient(
        colors: [
            softMint,
            Color(red: 0.56, green: 0.83, blue: 0.78)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // MARK: - Shadow Colors
    
    /// 골든 그림자 - 로고, 중요 요소
    static func goldenShadow(opacity: Double = 0.4) -> Color {
        gracefulGold.opacity(opacity)
    }
    
    /// 퍼플 그림자 - 카드, 배경 요소
    static func purpleShadow(opacity: Double = 0.3) -> Color {
        dawnPurple.opacity(opacity)
    }
}

// MARK: - Upload Mode Theme Extension

extension AppTheme {
    
    /// 업로드 모드별 테마
    enum UploadModeTheme {
        case folder   // 폴더 업로드
        case album    // 앨범 선택
        case photos   // 개별 사진
        
        /// 모드별 액센트 컬러
        var accentColor: Color {
            switch self {
            case .folder:
                return AppTheme.gracefulGold  // 골든 - 소중한 기억 저장
            case .album:
                return AppTheme.dawnPurple    // 퍼플 - 영적 선택
            case .photos:
                return AppTheme.gracefulGold  // 골든 - 통일된 디자인
            }
        }
        
        /// 모드별 그라디언트
        var gradient: LinearGradient {
            switch self {
            case .folder:
                return AppTheme.goldenGradient
            case .album:
                return AppTheme.purpleGradient
            case .photos:
                return AppTheme.goldenGradient  // 골든으로 통일
            }
        }
        
        /// 모드별 글로우 색상
        var glowColor: Color {
            accentColor.opacity(0.3)
        }
        
        /// ArchiveView.UploadMode에서 변환하는 헬퍼 메서드
        static func from<T>(_ mode: T) -> UploadModeTheme {
            let modeString = String(describing: mode)
            switch modeString {
            case "folder":
                return .folder
            case "album":
                return .album
            case "photos":
                return .photos
            default:
                return .folder
            }
        }
    }
}

// MARK: - View Extensions for Easy Access

extension View {
    
    /// 은혜의 새벽 배경 적용
    func dawnBackground() -> some View {
        self.background(AppTheme.backgroundGradient.ignoresSafeArea())
    }
    
    /// 골든 그라디언트 전경색 적용
    func goldenForeground() -> some View {
        self.foregroundStyle(AppTheme.goldenGradient)
    }
    
    /// 듀얼 그라디언트 전경색 적용 (골든 → 퍼플)
    func dualForeground() -> some View {
        self.foregroundStyle(AppTheme.dualGradient)
    }
    
    /// 골든 글로우 적용
    func goldenGlow(radius: CGFloat = 15, opacity: Double = 0.4) -> some View {
        self.shadow(color: AppTheme.goldenShadow(opacity: opacity), radius: radius)
    }
    
    /// 퍼플 글로우 적용
    func purpleGlow(radius: CGFloat = 20, opacity: Double = 0.3) -> some View {
        self.shadow(color: AppTheme.purpleShadow(opacity: opacity), radius: radius)
    }
    
    /// 듀얼 글로우 적용 (골든 + 퍼플)
    func dualGlow() -> some View {
        self
            .goldenGlow()
            .purpleGlow()
    }
}
