import SharedCode
import SwiftUI
import WidgetKit

struct NightConditionsWidgetMediumEntryView: View {
    var assessment: NightQualityAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Night Conditions", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(assessment.calculatedScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(assessment.scoreColor(for: assessment.calculatedScore))
                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Text(assessment.rating.emoji)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.summary)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(assessment.ratingColor)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let window = assessment.bestWindow {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text("Best: \(formatTime(window.start)) – \(formatTime(window.end))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
            }

            Spacer()

            HStack(spacing: 8) {
                MiniPill(label: "Clouds", value: "\(Int(assessment.details.cloudCoverScore))%", color: assessment.cloudColor(assessment.details.cloudCoverScore))
                MiniPill(label: "Moon", value: "\(assessment.details.moonIlluminationAvg)%", color: assessment.moonColor(assessment.details.moonIlluminationAvg))
                MiniPill(label: "Wind", value: "\(Int(assessment.details.windSpeedAvg)) m/s", color: assessment.windColor(assessment.details.windSpeedAvg))
            }
        }
        .containerBackground(.background.tertiary, for: .widget)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    }

struct MiniPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
