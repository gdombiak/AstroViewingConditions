import Foundation

/// Domain owner of the public 0–100 night-conditions score.
///
/// Preserves the production formula previously hosted on `BestSpotSearcher`,
/// including Swift `Int(Double)` truncation of the hourly adjustment
/// (`Int((1.0 - avgScore) * 10)`), not rounding.
public enum NightConditionsScoring: Sendable {
    /// Converts a night-quality assessment to the public 0–100 score.
    /// Higher is better.
    public static func publicScore(_ assessment: NightQualityAssessment) -> Int {
        publicScore(assessment, calibration: EngineCalibration.current.nightQuality.publicScore)
    }

    public static func publicScore(
        _ assessment: NightQualityAssessment,
        calibration: NightQualityCalibration.PublicScore
    ) -> Int {
        let baseScore: Int
        switch assessment.rating {
        case .excellent:
            baseScore = calibration.excellentBase
        case .good:
            baseScore = calibration.goodBase
        case .fair:
            baseScore = calibration.fairBase
        case .poor:
            baseScore = calibration.poorBase
        }

        let hourlyScores = assessment.hourlyRatings.map { $0.score }
        var adjustment = 0
        if !hourlyScores.isEmpty {
            let avgScore = hourlyScores.reduce(0, +) / Double(hourlyScores.count)
            // Convert avgScore (0-2, lower is better) to adjustment (-10 to +10)
            adjustment = Int((1.0 - avgScore) * calibration.adjustmentScale)
        }

        let finalScore = baseScore + adjustment
        return min(calibration.scoreMax, max(calibration.scoreMin, finalScore))
    }
}
