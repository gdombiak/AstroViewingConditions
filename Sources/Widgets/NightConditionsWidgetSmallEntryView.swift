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
                    .foregroundStyle(assessment.scoreColor(for: assessment.calculatedScore))
                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(assessment.summary)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(assessment.ratingColor)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                MiniPill(label: "Clouds", value: "\(Int(assessment.details.cloudCoverScore))%", color: assessment.cloudColor(assessment.details.cloudCoverScore))
                MiniPill(label: "Moon", value: "\(assessment.details.moonIlluminationAvg)%", color: assessment.moonColor(assessment.details.moonIlluminationAvg))
            }
        }
        .containerBackground(.background.tertiary, for: .widget)
    }
}
