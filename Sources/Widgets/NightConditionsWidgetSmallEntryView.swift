import SharedCode
import SwiftUI
import WidgetKit

struct NightConditionsWidgetSmallEntryView: View {
    var assessment: NightQualityAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                Spacer()
                Text("\(assessment.calculatedScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(for: assessment.calculatedScore))
                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(assessment.summary)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(ratingColor)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                MiniPill(label: "Clouds", value: "\(Int(assessment.details.cloudCoverScore))%", color: cloudColor(assessment.details.cloudCoverScore))
                MiniPill(label: "Moon", value: "\(assessment.details.moonIlluminationAvg)%", color: moonColor(assessment.details.moonIlluminationAvg))
            }
        }
        .containerBackground(.background.tertiary, for: .widget)
    }

    private var ratingColor: Color {
        switch assessment.rating {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
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
}
