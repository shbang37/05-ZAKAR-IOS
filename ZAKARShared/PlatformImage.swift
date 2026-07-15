import Foundation
import CoreGraphics

// ============================================================
// PlatformImage — iOS(UIImage) / macOS(NSImage) 통일 레이어
// 공유 코어(PhotoManager·PhotoQualityScorer)가 플랫폼 이미지 타입에
// 직접 의존하지 않고 CGImage만 다루도록 하는 얇은 어댑터.
// ============================================================

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    /// 플랫폼 무관 CGImage 추출 (유사판별 pHash·FeaturePrint·품질 점수 공용)
    var zakarCGImage: CGImage? {
        #if canImport(UIKit)
        return cgImage
        #elseif canImport(AppKit)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}
