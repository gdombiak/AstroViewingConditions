import Foundation

public struct TransparencyCalculator {
    public static func penalty(
        totalCloudCover: Int,
        lowCloudCover: Int?,
        midCloudCover: Int?,
        highCloudCover: Int?,
        visibilityMeters: Double?
    ) -> Double? {
        penalty(
            totalCloudCover: totalCloudCover,
            lowCloudCover: lowCloudCover,
            midCloudCover: midCloudCover,
            highCloudCover: highCloudCover,
            visibilityMeters: visibilityMeters,
            calibration: EngineCalibration.current.transparency
        )
    }

    public static func penalty(
        totalCloudCover: Int,
        lowCloudCover: Int?,
        midCloudCover: Int?,
        highCloudCover: Int?,
        visibilityMeters: Double?,
        calibration: TransparencyCalibration
    ) -> Double? {
        let totalCloudCover = Double(
            min(max(totalCloudCover, 0), 100)
        )

        let effectiveCloudCover: Double
        if let lowCloudCover, let midCloudCover, let highCloudCover {
            let layeredCloudCover =
                Double(min(max(lowCloudCover, 0), 100)) * calibration.layerWeights.low +
                Double(min(max(midCloudCover, 0), 100)) * calibration.layerWeights.mid +
                Double(min(max(highCloudCover, 0), 100)) * calibration.layerWeights.high

            effectiveCloudCover = max(totalCloudCover, layeredCloudCover)
        } else {
            effectiveCloudCover = totalCloudCover
        }

        let cloudComponent = CalibrationTables.score(
            for: effectiveCloudCover,
            in: calibration.cloudCover
        )
        guard let visibilityMeters else { return cloudComponent }

        let visibilityComponent = CalibrationTables.score(
            for: max(visibilityMeters, 0),
            in: calibration.visibilityMeters
        )
        let combinedPenalty =
            cloudComponent * calibration.combineWeights.cloud +
            visibilityComponent * calibration.combineWeights.visibility

        return min(
            max(cloudComponent, combinedPenalty),
            calibration.penaltyMax
        )
    }
}
