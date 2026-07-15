import Foundation
import Photos
import Vision

/// 그룹 내 대표 사진 선정을 위한 품질 점수 계산기
/// - 선명도: 라플라시안 분산 (흔들림·초점 불량 감지)
/// - 얼굴 품질: Vision 얼굴 캡처 품질 — 눈 감음·표정·블러·노출을 종합한 점수로,
///   같은 인물을 연속 촬영한 사진끼리 비교하는 용도로 Apple이 설계함 (우리 유스케이스와 정확히 일치)
/// - 미학 점수: iOS 18+ 기기에서 Apple 이미지 미학 평가 가산
final class PhotoQualityScorer {
    static let shared = PhotoQualityScorer()
    private init() {}

    private let cacheLock = NSLock()
    private var cache: [String: Double] = [:]

    struct QualitySignals {
        var sharpness: Double = 0.5    // 0~1
        var faceQuality: Double?       // 0~1, 얼굴 없으면 nil
        var aesthetics: Double?        // 0~1, iOS 18 미만이면 nil
    }

    /// 종합 품질 점수 (0~1). 같은 그룹 내 상대 비교용.
    func score(for asset: PHAsset) async -> Double {
        let key = asset.localIdentifier
        if let cached = cacheLock.withLock({ cache[key] }) { return cached }

        // 선명도 판별이 목적이므로 반드시 고품질 이미지로 분석
        // (fastFormat 썸네일은 자체 블러 때문에 점수를 오염시킴)
        guard let cgImage = await loadCGImage(for: asset) else { return 0.5 }
        let signals = await analyze(cgImage: cgImage)
        let total = combine(signals)
        print("ZAKAR Log: 품질 점수 - sharp=\(String(format: "%.2f", signals.sharpness)), face=\(signals.faceQuality.map { String(format: "%.2f", $0) } ?? "없음"), aes=\(signals.aesthetics.map { String(format: "%.2f", $0) } ?? "N/A") → total=\(String(format: "%.2f", total))")
        cacheLock.withLock { cache[key] = total }
        return total
    }

    func clearCache() {
        cacheLock.withLock { cache.removeAll() }
    }

    // MARK: - 신호 결합

    private func combine(_ s: QualitySignals) -> Double {
        // 얼굴이 있으면 얼굴 품질(눈 감음/표정/블러 종합)이 가장 중요
        if let face = s.faceQuality {
            if let aes = s.aesthetics {
                return face * 0.5 + s.sharpness * 0.3 + aes * 0.2
            }
            return face * 0.55 + s.sharpness * 0.45
        }
        if let aes = s.aesthetics {
            return s.sharpness * 0.6 + aes * 0.4
        }
        return s.sharpness
    }

    // MARK: - 분석

    private func analyze(cgImage: CGImage) async -> QualitySignals {
        var signals = QualitySignals()
        signals.sharpness = laplacianSharpness(cgImage)

        // 얼굴 캡처 품질 (iOS 13+)
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([faceRequest])
        let faceScores: [Double] = (faceRequest.results ?? []).compactMap { obs in
            obs.faceCaptureQuality.map { Double($0) }
        }
        if !faceScores.isEmpty {
            signals.faceQuality = faceScores.reduce(0, +) / Double(faceScores.count)
        }

        // 미학 점수 (iOS 18+ / macOS 15+ 신규 Vision API)
        if #available(iOS 18.0, macOS 15.0, *) {
            let request = CalculateImageAestheticsScoresRequest()
            if let observation = try? await request.perform(on: cgImage) {
                // overallScore: -1(나쁨) ~ +1(좋음) → 0~1 정규화
                signals.aesthetics = (Double(observation.overallScore) + 1.0) / 2.0
            }
        }
        return signals
    }

    /// 라플라시안 분산 기반 선명도 (0~1)
    /// 128×128 그레이스케일로 축소 후 라플라시안 응답의 분산을 계산 — 분산이 클수록 선명
    private func laplacianSharpness(_ cgImage: CGImage) -> Double {
        let width = 128, height = 128
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0.5 }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return 0.5 }
        let p = data.bindMemory(to: UInt8.self, capacity: width * height)

        var sum = 0.0, sumSq = 0.0
        let n = Double((width - 2) * (height - 2))
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let lap = Double(Int(p[idx - width]) + Int(p[idx + width])
                               + Int(p[idx - 1]) + Int(p[idx + 1])
                               - 4 * Int(p[idx]))
                sum += lap
                sumSq += lap * lap
            }
        }
        let mean = sum / n
        let variance = sumSq / n - mean * mean
        // 경험적 매핑: 흔들린 사진 ~<50, 선명한 사진 >300 수준의 분산
        return min(1.0, variance / 400.0)
    }

    private func loadCGImage(for asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        return await withCheckedContinuation { cont in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { img, _ in
                guard !didResume else { return }
                didResume = true
                cont.resume(returning: img?.zakarCGImage)
            }
        }
    }
}
