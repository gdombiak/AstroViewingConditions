import SwiftUI
import SharedCode

struct WatchNightQualityCard: View {
    let assessment: NightQualityAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(assessment.rating.emoji)
                    .font(.title2)
                Text("\(assessment.calculatedScore)/100")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(scoreColor)
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
        assessment.scoreColor
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
