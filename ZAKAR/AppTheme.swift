import SwiftUI

/// 은혜의교회 테마
/// "Scars into Stars" - 프리미엄 Liquid Glass 디자인 시스템
struct AppTheme {
    
    // MARK: - Primary Colors
    
    /// 은혜로운 골드 - 주요 강조색
    static let gracefulGold = Color(red: 0.83, green: 0.69, blue: 0.22)  // #D4AF37
    
    /// 골든 로즈 - 따뜻한 골드 변형
    static let goldenRose = Color(red: 0.85, green: 0.65, blue: 0.45)  // #D9A673
    
    /// 라벤더 - 부드러운 퍼플 악센트
    static let lavender = Color(red: 0.70, green: 0.65, blue: 0.85)  // #B3A6D9
    
    /// 퓨어 화이트 - 주요 텍스트
    static let pureWhite = Color(red: 0.99, green: 0.99, blue: 0.95)  // #FDFDF1
    
    // MARK: - Background Colors
    
    /// 딥 퍼플 - 깊은 배경 (그라디언트 시작)
    static let deepPurple = Color(red: 0.16, green: 0.12, blue: 0.24)  // #2A1F3D
    
    /// 미드 퍼플 - 배경 중간톤
    static let midPurple = Color(red: 0.27, green: 0.22, blue: 0.36)  // #46385C
    
    /// 다크 퍼플 - 카드 배경용
    static let darkPurple = Color(red: 0.25, green: 0.22, blue: 0.35)  // #403858
    
    /// 라이트 퍼플 - 강조 요소용
    static let lightPurple = Color(red: 0.50, green: 0.45, blue: 0.60)  // #807299
    
    // MARK: - Accent Colors
    
    /// 서브 텍스트 - 흰색 70% 투명도
    static let subText = Color.white.opacity(0.7)
    
    /// 디바이더 - 흰색 20% 투명도
    static let divider = Color.white.opacity(0.2)
    
    // MARK: - Premium Gradients
    
    /// 메인 배경 그라디언트 (깊이감 있는 퍼플)
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [deepPurple, midPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// 골든 퍼플 그라디언트 (따뜻한 악센트)
    static var goldenPurpleGradient: LinearGradient {
        LinearGradient(
            colors: [gracefulGold, goldenRose],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    /// 퍼플 라벤더 그라디언트 (부드러운 악센트)
    static var purpleLavenderGradient: LinearGradient {
        LinearGradient(
            colors: [lightPurple, lavender],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// 글라스 테두리 그라디언트 (골든-퍼플)
    static var glassBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                gracefulGold.opacity(0.5),
                goldenRose.opacity(0.4),
                lavender.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Legacy Compatibility
    
    /// 골든 컬러
    static var goldenGradient: some ShapeStyle {
        gracefulGold
    }
    
    /// 퍼플 컬러
    static var purpleGradient: some ShapeStyle {
        lightPurple
    }
    
    /// 듀얼 컬러
    static var dualGradient: LinearGradient {
        goldenPurpleGradient
    }
    
    // MARK: - Shadow & Glow Colors
    
    /// 골든 그림자
    static func goldenShadow(opacity: Double = 0.4) -> Color {
        gracefulGold.opacity(opacity)
    }
    
    /// 골든 로즈 그림자
    static func goldenRoseShadow(opacity: Double = 0.3) -> Color {
        goldenRose.opacity(opacity)
    }
    
    /// 퍼플 그림자
    static func purpleShadow(opacity: Double = 0.3) -> Color {
        midPurple.opacity(opacity)
    }
    
    /// 라벤더 그림자
    static func lavenderShadow(opacity: Double = 0.2) -> Color {
        lavender.opacity(opacity)
    }
}

// MARK: - Upload Mode Theme Extension

extension AppTheme {
    
    /// 업로드 모드별 테마
    enum UploadModeTheme {
        case folder   // 폴더 업로드
        case album    // 앨범 선택
        case photos   // 개별 사진
        
        /// 모드별 액센트 컬러 (골드 통일)
        var accentColor: Color {
            return AppTheme.gracefulGold
        }
        
        /// 모드별 그라디언트 (단일 컬러로 변경)
        var gradient: Color {
            return AppTheme.gracefulGold
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
    
    /// 프리미엄 배경 적용
    func premiumBackground(style: PremiumBackground.BackgroundStyle = .deep) -> some View {
        self.background(PremiumBackground(style: style))
    }
    
    /// 골든 전경색 적용
    func goldenForeground() -> some View {
        self.foregroundStyle(AppTheme.gracefulGold)
    }
    
    /// 화이트 전경색 적용
    func whiteForeground() -> some View {
        self.foregroundStyle(AppTheme.pureWhite)
    }
    
    /// 골든 글로우 적용
    func goldenGlow(radius: CGFloat = 15, opacity: Double = 0.4) -> some View {
        self.shadow(color: AppTheme.goldenShadow(opacity: opacity), radius: radius)
    }
    
    /// 퍼플 글로우 적용
    func purpleGlow(radius: CGFloat = 20, opacity: Double = 0.3) -> some View {
        self.shadow(color: AppTheme.purpleShadow(opacity: opacity), radius: radius)
    }
}
