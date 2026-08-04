import SwiftUI
import SharedCode

struct CircularComplicationView: View {
    var assessment: NightQualityAssessment
    var headlineScore: Int

    init(assessment: NightQualityAssessment, headlineScore: Int? = nil) {
        self.assessment = assessment
        self.headlineScore = headlineScore ?? assessment.calculatedScore
    }

    var body: some View {
        Gauge(value: Double(headlineScore), in: 0...100) {
        } currentValueLabel: {
            VStack(spacing: -5) {
                Text("\(headlineScore)")
                    .font(.system(size: 20, weight: .bold))
                Image(systemName: "sparkles")
                    .font(.caption2)
            }
            .padding(.top, 7)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(assessment.scoreColor(for: headlineScore))
        .containerBackground(.clear, for: .widget)
    }
}
