import SwiftUI
import SharedCode

struct WatchNightQualityCard: View {
    let assessment: NightQualityAssessment
    /// Overall headline score (OQ when Phase 4B enhancement is valid).
    var headlineScore: Int
    var headlineVerdict: String
    /// Category emoji from the same score band as `headlineScore` (not night `assessment.rating`).
    var headlineEmoji: String

    init(
        assessment: NightQualityAssessment,
        headlineScore: Int? = nil,
        headlineVerdict: String? = nil,
        headlineEmoji: String? = nil
    ) {
        self.assessment = assessment
        let score = headlineScore ?? assessment.calculatedScore
        self.headlineScore = score
        self.headlineVerdict = headlineVerdict
            ?? CrossSurfaceHeadlineScorePresentation.verdict(for: score)
        self.headlineEmoji = headlineEmoji
            ?? CrossSurfaceHeadlineScorePresentation.emoji(for: score)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(headlineEmoji)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text("\(headlineScore)/100")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(scoreColor)
                    .accessibilityLabel(
                        "Observing quality score \(headlineScore) out of 100, \(headlineVerdict)"
                    )
            }

            Text(assessment.summary)
                .font(.caption)
                .foregroundStyle(assessment.rating.color)

            if let firstHalf = assessment.firstHalfScore,
               let secondHalf = assessment.secondHalfScore {
                let firstRating = NightQualityAssessment.Rating.from(score: firstHalf)
                let secondRating = NightQualityAssessment.Rating.from(score: secondHalf)
                if firstRating != secondRating {
                    VStack(spacing: 2) {
                        WatchHalfScorePill(
                            label: "Early",
                            score: firstHalf,
                            color: assessment.scoreToColor(firstHalf)
                        )
                        Text(assessment.trend.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        WatchHalfScorePill(
                            label: "Late",
                            score: secondHalf,
                            color: assessment.scoreToColor(secondHalf)
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var scoreColor: Color {
        // Same 0…100 bands as ObservingQualityScoreBand / Night Conditions widgets.
        assessment.scoreColor(for: headlineScore)
    }
}

struct WatchHalfScorePill: View {
    let label: String
    let score: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(scoreLabel(score))
                .font(.caption2)
                .fontWeight(.medium)
        }
    }
    
    private func scoreLabel(_ score: Double) -> String {
        if score < 0.3 { return "Excellent" }
        else if score < 0.7 { return "Good" }
        else if score < 1.0 { return "Fair" }
        else { return "Poor" }
    }
}
