import SwiftUI
import SharedCode

struct CircularComplicationView: View {
    var assessment: NightQualityAssessment

    var body: some View {
        Gauge(value: Double(assessment.calculatedScore), in: 0...100) {
        } currentValueLabel: {
            VStack(spacing: -5) {
                Text("\(assessment.calculatedScore)")
                    .font(.system(size: 20, weight: .bold))
                Image(systemName: "sparkles")
                    .font(.caption2)
            }
            .padding(.top, 7)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(assessment.scoreColor)
        .containerBackground(.clear, for: .widget)
    }
}
