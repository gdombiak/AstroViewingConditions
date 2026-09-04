import Foundation

public struct TransparencyCalculator {
    public static func penalty(
        totalCloudCover: Int,
        lowCloudCover: Int?,
        midCloudCover: Int?,
        highCloudCover: Int?,
        visibilityMeters: Double?
    ) -> Double? {
        let totalCloudCover = Double(
            min(max(totalCloudCover, 0), 100)
        )

        let effectiveCloudCover: Double
        if let lowCloudCover, let midCloudCover, let highCloudCover {
            let layeredCloudCover =
                Double(min(max(lowCloudCover, 0), 100)) * 0.50 +
                Double(min(max(midCloudCover, 0), 100)) * 0.30 +
                Double(min(max(highCloudCover, 0), 100)) * 0.20

            effectiveCloudCover = max(totalCloudCover, layeredCloudCover)
        } else {
            effectiveCloudCover = totalCloudCover
        }

        let cloudComponent = component(forCloudCover: effectiveCloudCover)
        guard let visibilityMeters else { return cloudComponent }

        let visibilityComponent = component(forVisibility: max(visibilityMeters, 0))
        let combinedPenalty =
            cloudComponent * 0.75 +
            visibilityComponent * 0.25

        return min(max(cloudComponent, combinedPenalty), 2)
    }

    private static func component(forCloudCover cloudCover: Double) -> Double {
        switch cloudCover {
        case ...10: return 0
        case ...30: return 0.5
        case ...60: return 1
        case ...80: return 1.5
        default: return 2
        }
    }

    private static func component(forVisibility visibility: Double) -> Double {
        switch visibility {
        case 20_000...: return 0
        case 10_000...: return 0.5
        case 5_000...: return 1
        case 2_000...: return 1.5
        default: return 2
        }
    }
}
