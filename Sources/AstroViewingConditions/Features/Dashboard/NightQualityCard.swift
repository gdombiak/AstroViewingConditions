import SwiftUI

struct NightQualityCard: View {
    let assessment: NightQualityAssessment
    
    private var unitConverter: UnitConverter {
        UnitConverter(unitSystem: UserDefaults.standard.selectedUnitSystem)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Night Conditions", systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack(spacing: 12) {
                Text(assessment.rating.emoji)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.summary)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(ratingColor)
                    
                    if showWindow {
                        if let window = assessment.bestWindow {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.caption2)
                                if window.start == assessment.nightStart && window.end == assessment.nightEnd {
                                    Text("All night")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                } else {
                                    Text("\(DateFormatters.formatTime(window.start)) - \(DateFormatters.formatTime(window.end))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Factors breakdown
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
    
    private var showWindow: Bool {
        switch assessment.rating {
        case .excellent, .good:
            return true
        case .fair:
            return assessment.bestWindow != nil
        case .poor:
            return false
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
            summary: "Good night for observing. Expect clear skies.",
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
            nightEnd: Date().addingTimeInterval(-3600 * 2)
        )
    )
    .padding()
}
