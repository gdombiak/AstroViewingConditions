import Foundation

/// Shared display adaptation of an already analyzed night. It contains no
/// scoring, forecasting, or condition-analysis rules.
public struct NightQualityPresentation: Sendable {
    public let primaryMessage: String
    public let factors: [NightQualityDisplayFactor]

    public init(assessment: NightQualityAssessment) {
        self.primaryMessage = assessment.summary
        self.factors = Self.factors(for: assessment)
    }

    private static func factors(
        for assessment: NightQualityAssessment
    ) -> [NightQualityDisplayFactor] {
        guard !assessment.hourlyRatings.isEmpty else { return [] }

        let details = assessment.details
        var factors = [
            NightQualityDisplayFactor(
                kind: .clouds,
                label: "Clouds",
                value: "\(Int(details.cloudCoverScore.rounded()))%",
                tone: cloudTone(details.cloudCoverScore)
            )
        ]

        if let seeingScore = details.seeingScoreAvg {
            factors.append(
                NightQualityDisplayFactor(
                    kind: .seeing,
                    label: "Seeing",
                    value: NightQualityAssessment.Rating.from(score: seeingScore).shortLabel,
                    tone: tone(for: seeingScore)
                )
            )
        }
        if let transparencyScore = details.transparencyScoreAvg {
            factors.append(
                NightQualityDisplayFactor(
                    kind: .transparency,
                    label: "Transparency",
                    value: NightQualityAssessment.Rating.from(score: transparencyScore).shortLabel,
                    tone: tone(for: transparencyScore)
                )
            )
        }

        return factors
    }

    private static func cloudTone(_ cloudCover: Double) -> NightQualityDisplayFactor.Tone {
        switch cloudCover {
        case ..<50: return .favorable
        case 50..<80: return .neutral
        default: return .limiting
        }
    }

    private static func tone(for penalty: Double) -> NightQualityDisplayFactor.Tone {
        switch NightQualityAssessment.Rating.from(score: penalty) {
        case .excellent, .good: return .favorable
        case .fair: return .neutral
        case .poor: return .limiting
        }
    }
}

public extension NightQualityAssessment.Rating {
    var shortLabel: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}
