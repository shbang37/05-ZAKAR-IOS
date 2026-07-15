import Foundation
import Photos

// ============================================================
// PhotoManager iOS 전용 확장
// 공유 코어(ZAKARShared/PhotoManager.swift)에서 iOS UI 전용 타입(MonthData 등)에
// 의존하는 메서드를 분리해 이 파일(iOS 타깃 전용)에 둔다.
// ============================================================

extension PhotoManager {
    // MARK: - 월별 사진 데이터 생성 (홈 화면 전용)
    func getMonthlyPhotoData() -> [MonthData] {
        var monthDictionary: [String: Int] = [:]
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        // 모든 사진을 년월별로 그룹화
        for asset in allPhotos {
            guard let date = asset.creationDate else { continue }

            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = "\(year)-\(month)"

            monthDictionary[key, default: 0] += 1
        }

        // MonthData 배열 생성
        var result: [MonthData] = []

        for (key, count) in monthDictionary {
            let components = key.split(separator: "-")
            guard components.count == 2,
                  let year = Int(components[0]),
                  let month = Int(components[1]) else {
                continue
            }

            let isCurrentMonth = (year == currentYear && month == currentMonth)

            result.append(MonthData(
                year: year,
                month: month,
                photoCount: count,
                isCurrentMonth: isCurrentMonth
            ))
        }

        // 최신 순으로 정렬 (2026년 4월 → 2026년 3월 → ...)
        result.sort { lhs, rhs in
            if lhs.year != rhs.year {
                return lhs.year > rhs.year
            }
            return lhs.month > rhs.month
        }

        return result
    }
}
