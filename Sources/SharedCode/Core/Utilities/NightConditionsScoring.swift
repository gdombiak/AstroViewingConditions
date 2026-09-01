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
        let baseScore: Int
        switch assessment.rating {
        case .excellent:
            baseScore = 90
        case .good:
            baseScore = 70
        case .fair:
            baseScore = 45
        case .poor:
            baseScore = 20
        }

        let hourlyScores = assessment.hourlyRatings.map { $0.score }
        var adjustment = 0
        if !hourlyScores.isEmpty {
            let avgScore = hourlyScores.reduce(0, +) / Double(hourlyScores.count)
            // Convert avgScore (0-2, lower is better) to adjustment (-10 to +10)
            adjustment = Int((1.0 - avgScore) * 10)
        }

        let finalScore = baseScore + adjustment
        return min(100, max(0, finalScore))
    }
}
