import SharedCode
import SwiftUI

struct NightQualityCard: View {
    let assessment: NightQualityAssessment
    
    private var unitConverter: AstroUnitConverter {
        AstroUnitConverter(unitSystem: UserDefaults.standard.selectedUnitSystem)
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
                                    color: scoreToColor(firstHalf)
                                )
                                Text(assessment.trend.icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HalfScorePill(
                                    label: "Late",
                                    score: secondHalf,
                                    color: scoreToColor(secondHalf)
                                )
                            }
                        }
                    }
                }
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                FactorPill(label: "Clouds", value: "\(Int(assessment.details.cloudCoverScore))%", color: cloudColor(assessment.details.cloudCoverScore))
                FactorPill(label: "Moon", value: "\(assessment.details.moonIlluminationAvg)%", color: moonColor(assessment.details.moonIlluminationAvg))
                FactorPill(label: "Wind", value: unitConverter.formatWindSpeed(assessment.details.windSpeedAvg), color: windColor(assessment.details.windSpeedAvg))
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func scoreToColor(_ score: Double) -> Color {
        if score < 0.3 { return .green }
        else if score < 0.7 { return .blue }
        else if score < 1.0 { return .orange }
        else { return .red }
    }
    
    private func cloudColor(_ coverage: Double) -> Color {
        switch Int(coverage) {
        case 0..<20: return .green
        case 20..<50: return .blue
        case 50..<80: return .orange
        default: return .red
        }
    }
    
    private func moonColor(_ illumination: Int) -> Color {
        switch illumination {
        case 0..<25: return .green
        case 25..<50: return .blue
        case 50..<75: return .orange
        default: return .red
        }
    }
    
    private func windColor(_ speed: Double) -> Color {
        switch speed {
        case 0..<5: return .green
        case 5..<10: return .blue
        case 10..<15: return .orange
        default: return .red
        }
    }
    
    private var cardBackgroundColor: Color {
        #if os(iOS)
        return Color(uiColor: .systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
    
    private var ratingColor: Color {
        switch assessment.rating {
        case .excellent:
            return .green
        case .good:
            return .blue
        case .fair:
            return .orange
        case .poor:
            return .red
        }
    }
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
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
