import Foundation

public struct TransparencyCalculator {
    public static func penalty(
        totalCloudCover: Int,
        lowCloudCover: Int?,
        midCloudCover: Int?,
        highCloudCover: Int?,
        visibilityMeters: Double?
    ) -> Double? {
        let cloudCover: Double
        if let lowCloudCover, let midCloudCover, let highCloudCover {
            cloudCover = Double(lowCloudCover) * 0.50 + Double(midCloudCover) * 0.30 + Double(highCloudCover) * 0.20
        } else {
            cloudCover = Double(totalCloudCover)
        }

        let cloudComponent = component(forCloudCover: min(max(cloudCover, 0), 100))
        guard let visibilityMeters else { return cloudComponent }

        let visibilityComponent = component(forVisibility: max(visibilityMeters, 0))
        return min(max(cloudComponent * 0.75 + visibilityComponent * 0.25, 0), 2)
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
