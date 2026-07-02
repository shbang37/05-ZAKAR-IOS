#!/usr/bin/env swift
// ZAKAR 유사 사진 판별 채점 루틴 (macOS)
//
// PhotoManager의 pHash + Vision FeaturePrint 하이브리드 로직을 미러링해서
// 픽스처 사진 세트에 대한 정확도를 수치로 출력한다.
//
// 사용법:  swift eval.swift [fixtures 경로]   (기본값: 스크립트 옆의 fixtures/)
//
// 픽스처 구조:
//   fixtures/similar/<그룹명>/*.jpg|png|heic   — 같은 폴더 안 모든 쌍은 "유사"로 판정되어야 함
//   fixtures/dissimilar/<그룹명>/*             — 같은 폴더 안 모든 쌍은 "비유사"로 판정되어야 함
//
// ⚠️ 임계값을 바꿀 땐 PhotoManager.SimilarityPreset과 이 파일의 presets를 함께 수정할 것.

import Foundation
import CoreGraphics
import ImageIO
import Vision

// MARK: - 프리셋 (PhotoManager.SimilarityPreset과 동일 값 유지)

struct Preset {
    let name: String
    let phashConfirm: Int   // 이하면 pHash만으로 유사 확정
    let phashMaybe: Int     // 이하면 경계 구간 → FeaturePrint 2차 검증
    let featurePrintMax: Float
}

let presets = [
    Preset(name: "light   ", phashConfirm: 12, phashMaybe: 18, featurePrintMax: 0.65),
    Preset(name: "balanced", phashConfirm: 10, phashMaybe: 16, featurePrintMax: 0.55),
    Preset(name: "strict  ", phashConfirm: 8,  phashMaybe: 12, featurePrintMax: 0.45),
]

// MARK: - 이미지 로드

func loadCGImage(_ url: URL, maxPixel: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

// MARK: - pHash (PhotoManager.calculatePHash와 동일 알고리즘)

func pHash(_ cgImage: CGImage) -> UInt64 {
    let width = 32, height = 32
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: width,
                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
    ctx.interpolationQuality = .medium
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else { return 0 }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

    var f = Array(repeating: Array(repeating: 0.0, count: 32), count: 32)
    for y in 0..<32 {
        for x in 0..<32 {
            f[y][x] = Double(pixels[y * 32 + x])
        }
    }

    let N = 32, K = 8
    var dct = Array(repeating: Array(repeating: 0.0, count: K), count: K)
    let c: (Int) -> Double = { $0 == 0 ? 1.0 / sqrt(2.0) : 1.0 }
    let scale = 2.0 / Double(N)
    for v in 0..<K {
        for u in 0..<K {
            var sum = 0.0
            for y in 0..<N {
                for x in 0..<N {
                    let cos1 = cos(((Double(2 * x) + 1.0) * Double(u) * .pi) / Double(2 * N))
                    let cos2 = cos(((Double(2 * y) + 1.0) * Double(v) * .pi) / Double(2 * N))
                    sum += f[y][x] * cos1 * cos2
                }
            }
            dct[v][u] = scale * c(u) * c(v) * sum
        }
    }

    var total = 0.0, count = 0.0
    for v in 0..<K {
        for u in 0..<K {
            if v == 0 && u == 0 { continue }
            total += dct[v][u]
            count += 1
        }
    }
    let avg = total / max(count, 1.0)

    var hash: UInt64 = 0
    var bitIndex: UInt64 = 0
    for v in 0..<K {
        for u in 0..<K {
            if v == 0 && u == 0 { continue }
            if dct[v][u] > avg { hash |= (1 << bitIndex) }
            bitIndex += 1
        }
    }
    return hash
}

func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

// MARK: - Vision FeaturePrint (리비전1 고정 — 앱과 동일)

func featurePrint(_ cgImage: CGImage) -> VNFeaturePrintObservation? {
    let req = VNGenerateImageFeaturePrintRequest()
    req.revision = VNGenerateImageFeaturePrintRequestRevision1
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([req])
    return req.results?.first
}

func fpDistance(_ a: VNFeaturePrintObservation?, _ b: VNFeaturePrintObservation?) -> Float? {
    guard let a = a, let b = b else { return nil }
    var d: Float = 0
    do { try a.computeDistance(&d, to: b); return d } catch { return nil }
}

// MARK: - 판정 (PhotoManager.clusterByVisualSimilarity의 쌍 판정과 동일)

func isSimilar(phashDist: Int, fpDist: Float?, preset: Preset) -> Bool {
    if phashDist <= preset.phashConfirm { return true }
    if phashDist <= preset.phashMaybe, let d = fpDist { return d <= preset.featurePrintMax }
    return false
}

// MARK: - 픽스처 수집

let imageExts = Set(["jpg", "jpeg", "png", "heic"])

struct Photo {
    let url: URL
    let hash: UInt64
    let fp: VNFeaturePrintObservation?
    var name: String { url.deletingPathExtension().lastPathComponent }
}

func collectGroups(in dir: URL) -> [(group: String, photos: [Photo])] {
    let fm = FileManager.default
    guard let subdirs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        .filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) else { return [] }

    var result: [(String, [Photo])] = []
    for sub in subdirs {
        guard let files = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil) else { continue }
        var photos: [Photo] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where imageExts.contains(file.pathExtension.lowercased()) {
            guard let img = loadCGImage(file, maxPixel: 360) else {
                print("⚠️  이미지 로드 실패: \(file.path)")
                continue
            }
            photos.append(Photo(url: file, hash: pHash(img), fp: featurePrint(img)))
        }
        if photos.count >= 2 {
            result.append((sub.lastPathComponent, photos))
        }
    }
    return result
}

struct PairResult {
    let group: String
    let a: String
    let b: String
    let phashDist: Int
    let fpDist: Float?
}

func evaluatePairs(_ groups: [(group: String, photos: [Photo])]) -> [PairResult] {
    var results: [PairResult] = []
    for (group, photos) in groups {
        for i in 0..<photos.count {
            for j in (i + 1)..<photos.count {
                results.append(PairResult(
                    group: group,
                    a: photos[i].name, b: photos[j].name,
                    phashDist: hamming(photos[i].hash, photos[j].hash),
                    fpDist: fpDistance(photos[i].fp, photos[j].fp)
                ))
            }
        }
    }
    return results
}

// MARK: - 메인

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let fixturesDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : scriptDir.appendingPathComponent("fixtures")

let similarDir = fixturesDir.appendingPathComponent("similar")
let dissimilarDir = fixturesDir.appendingPathComponent("dissimilar")

print("📂 픽스처: \(fixturesDir.path)")
let similarPairs = evaluatePairs(collectGroups(in: similarDir))
let dissimilarPairs = evaluatePairs(collectGroups(in: dissimilarDir))
print("   유사여야 하는 쌍: \(similarPairs.count) / 비유사여야 하는 쌍: \(dissimilarPairs.count)")

guard !similarPairs.isEmpty || !dissimilarPairs.isEmpty else {
    print("""

    ❌ 평가할 쌍이 없습니다. 픽스처를 채워주세요:
       \(similarDir.path)/<그룹명>/  에 유사한 사진 2장 이상
       \(dissimilarDir.path)/<그룹명>/  에 헷갈리지만 달라야 하는 사진 2장 이상
    """)
    exit(1)
}

func fmt(_ d: Float?) -> String { d.map { String(format: "%.3f", $0) } ?? "  -  " }

print("\n═══ 프리셋별 정확도 ═══")
for preset in presets {
    let recallHits = similarPairs.filter { isSimilar(phashDist: $0.phashDist, fpDist: $0.fpDist, preset: preset) }
    let falsePositives = dissimilarPairs.filter { isSimilar(phashDist: $0.phashDist, fpDist: $0.fpDist, preset: preset) }
    let recallStr = similarPairs.isEmpty ? "N/A" : "\(recallHits.count)/\(similarPairs.count)"
    let fpStr = dissimilarPairs.isEmpty ? "N/A" : "\(falsePositives.count)/\(dissimilarPairs.count)"
    print("\(preset.name)  유사 재현: \(recallStr)   비유사 오탐: \(fpStr)")

    for miss in similarPairs where !isSimilar(phashDist: miss.phashDist, fpDist: miss.fpDist, preset: preset) {
        print("    ↳ 미탐 [\(miss.group)] \(miss.a)↔\(miss.b)  pHash=\(miss.phashDist)  FP=\(fmt(miss.fpDist))")
    }
    for fp in falsePositives {
        print("    ↳ 오탐 [\(fp.group)] \(fp.a)↔\(fp.b)  pHash=\(fp.phashDist)  FP=\(fmt(fp.fpDist))")
    }
}

print("\n═══ 전체 쌍 거리 분포 (임계값 튜닝용) ═══")
print("--- 유사여야 하는 쌍 ---")
for p in similarPairs.sorted(by: { $0.phashDist < $1.phashDist }) {
    print("  [\(p.group)] \(p.a)↔\(p.b)  pHash=\(p.phashDist)  FP=\(fmt(p.fpDist))")
}
print("--- 비유사여야 하는 쌍 ---")
for p in dissimilarPairs.sorted(by: { $0.phashDist < $1.phashDist }) {
    print("  [\(p.group)] \(p.a)↔\(p.b)  pHash=\(p.phashDist)  FP=\(fmt(p.fpDist))")
}
