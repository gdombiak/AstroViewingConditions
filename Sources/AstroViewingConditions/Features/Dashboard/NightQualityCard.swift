import SharedCode
import SwiftUI

struct NightQualityCard: View {
    @Environment(\.appPalette) private var palette
    let assessment: NightQualityAssessment
    
    private var unitConverter: AstroUnitConverter {
        AstroUnitConverter(unitSystem: UnitSystemStorage.loadSelectedUnitSystem())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Night Conditions", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(assessment.calculatedScore)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(scoreColor(for: assessment.calculatedScore))
                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .top, spacing: 12) {
                Text(assessment.rating.emoji)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.summary)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(ratingColor)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let firstHalf = assessment.firstHalfScore,
                       let secondHalf = assessment.secondHalfScore {
                        let firstRating = NightQualityAssessment.Rating.from(score: firstHalf)
                        let secondRating = NightQualityAssessment.Rating.from(score: secondHalf)
                        if firstRating != secondRating {
                            HStack(spacing: 8) {
                                HalfScorePill(
                                    label: "Early",
                                    score: firstHalf,
                                    color: assessment.scoreToColor(firstHalf)
                                )
                                Text(assessment.trend.icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HalfScorePill(
                                    label: "Late",
                                    score: secondHalf,
                                    color: assessment.scoreToColor(secondHalf)
                                )
                            }
                        }
                    }
                }
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                FactorPill(label: "Clouds", value: "\(Int(assessment.details.cloudCoverScore))%", color: assessment.cloudColor(assessment.details.cloudCoverScore))
                FactorPill(label: "Moon", value: "\(assessment.details.moonIlluminationAvg)%", color: assessment.moonColor(assessment.details.moonIlluminationAvg))
                FactorPill(label: "Wind", value: unitConverter.formatWindSpeed(assessment.details.windSpeedAvg), color: assessment.windColor(assessment.details.windSpeedAvg))
            }
        }
        .dashboardCardStyle()
    }
    
    private var ratingColor: Color {
        switch assessment.rating {
        case .excellent: return palette.statusColor(.positive)
        case .good: return palette.statusColor(.informational)
        case .fair: return palette.statusColor(.caution)
        case .poor: return palette.statusColor(.negative)
        }
    }
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 80...100: return palette.statusColor(.positive)
        case 60..<80: return palette.statusColor(.informational)
        case 40..<60: return palette.statusColor(.caution)
        default: return palette.statusColor(.negative)
        }
    }
}

struct HalfScorePill: View {
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
                .font(.caption)
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

struct FactorPill: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    NightQualityCard(
        assessment: NightQualityAssessment(
            rating: .good,
            summary: "Good early, conditions degrade after midnight.",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 25,
                fogScoreAvg: 15,
                moonIlluminationAvg: 12,
                windSpeedAvg: 2.5
            ),
            bestWindow: NightQualityAssessment.TimeWindow(
                start: Date().addingTimeInterval(-3600 * 8),
                end: Date().addingTimeInterval(-3600 * 2)
            ),
            hourlyRatings: [],
            nightStart: Date().addingTimeInterval(-3600 * 10),
            nightEnd: Date().addingTimeInterval(-3600 * 2),
            trend: .degrading,
            firstHalfScore: 0.15,
            secondHalfScore: 1.4
        )
    )
    .padding()
}
