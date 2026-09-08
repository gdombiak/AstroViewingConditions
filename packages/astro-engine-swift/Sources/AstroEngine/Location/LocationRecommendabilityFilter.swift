import Foundation

/// Stable suitability-only filtering for Best Nearby recommendation candidates.
public enum LocationRecommendabilityFilter {
    public static let capabilityID = "location.filter_recommendable"

    public static func isRecommendable(_ suitability: LocationCompareSuitability) -> Bool {
        switch suitability {
        case .suitable, .unknown:
            return true
        case .unchecked, .unsuitable:
            return false
        }
    }

    public static func isRecommendable(_ suitability: LocationSuitabilityStatus) -> Bool {
        switch suitability {
        case .suitable:
            return isRecommendable(LocationCompareSuitability.suitable)
        case .unknown:
            return isRecommendable(LocationCompareSuitability.unknown)
        case .unchecked:
            return isRecommendable(LocationCompareSuitability.unchecked)
        case .unsuitable:
            return isRecommendable(LocationCompareSuitability.unsuitable)
        }
    }

    public static func recommendableInputIndices(
        for suitability: [LocationCompareSuitability]
    ) -> [Int] {
        suitability.enumerated().compactMap { index, status in
            isRecommendable(status) ? index : nil
        }
    }

    public static func recommendableInputIndices(
        for suitability: [LocationSuitabilityStatus]
    ) -> [Int] {
        suitability.enumerated().compactMap { index, status in
            isRecommendable(status) ? index : nil
        }
    }
}
