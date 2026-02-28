import SwiftUI

/// 은혜의교회 테마
/// "Scars into Stars" - 은혜의교회 브랜드 아이덴티티를 담은 컬러 시스템
struct AppTheme {
    
    // MARK: - Primary Colors
    
    /// 은혜로운 골드 - 주요 강조색 (텍스트, 중요 요소)
    static let gracefulGold = Color(red: 0.91, green: 0.66, blue: 0.49)  // #E8A87C
    
    /// 퓨어 화이트 - 주요 텍스트
    static let pureWhite = Color.white
    
    // MARK: - Background Colors
    
    /// 메인 퍼플 - 은혜의교회 배경색 (단일 컬러, 그라디언트 없음)
    static let mainPurple = Color(red: 0.38, green: 0.33, blue: 0.49)  // #615380
    
    /// 다크 퍼플 - 카드 배경용 (메인보다 약간 어두움)
    static let darkPurple = Color(red: 0.25, green: 0.22, blue: 0.35)  // #403858
    
    /// 라이트 퍼플 - 강조 요소용 (메인보다 약간 밝음)
    static let lightPurple = Color(red: 0.50, green: 0.45, blue: 0.60)  // #807299
    
    // MARK: - Accent Colors
    
    /// 서브 텍스트 - 흰색 70% 투명도
    static let subText = Color.white.opacity(0.7)
    
    /// 디바이더 - 흰색 20% 투명도
    static let divider = Color.white.opacity(0.2)
    
    // MARK: - Solid Backgrounds (그라디언트 제거)
    
    /// 배경색 - 단일 퍼플
    static var backgroundGradient: some ShapeStyle {
        mainPurple
    }
    
    /// 카드 배경 - 약간 어두운 퍼플
    static var cardFillGradient: some ShapeStyle {
        darkPurple.opacity(0.6)
    }
    
    /// 카드 테두리 - 골드 투명도
    static var cardStrokeGradient: some ShapeStyle {
        gracefulGold.opacity(0.3)
    }
    
    // MARK: - Legacy Compatibility (기존 코드 호환성)
    
    /// 골든 컬러 (그라디언트 제거, 단일 컬러)
    static var goldenGradient: some ShapeStyle {
        gracefulGold
    }
    
    /// 퍼플 컬러 (그라디언트 제거, 단일 컬러)
    static var purpleGradient: some ShapeStyle {
        lightPurple
    }
    
    /// 듀얼 컬러 (그라디언트 제거, 골드 사용)
    static var dualGradient: some ShapeStyle {
        gracefulGold
    }
    
    // MARK: - Shadow Colors
    
    /// 골든 그림자 - 로고, 중요 요소
    static func goldenShadow(opacity: Double = 0.4) -> Color {
        gracefulGold.opacity(opacity)
    }
    
    /// 퍼플 그림자 - 카드, 배경 요소
    static func purpleShadow(opacity: Double = 0.3) -> Color {
        mainPurple.opacity(opacity)
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
    
    /// 은혜의교회 배경 적용 (단일 퍼플)
    func dawnBackground() -> some View {
        self.background(AppTheme.mainPurple.ignoresSafeArea())
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
