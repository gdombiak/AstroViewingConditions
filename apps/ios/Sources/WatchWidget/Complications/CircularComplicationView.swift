import SwiftUI
import SharedCode

struct CircularComplicationView: View {
    private let isUnavailable: Bool
    private let assessment: NightQualityAssessment?
    private let headlineScore: Int
    private let scorePresentationMode: WatchHeadlineScorePresentationMode

    init(
        assessment: NightQualityAssessment,
        headlineScore: Int? = nil,
        scorePresentationMode: WatchHeadlineScorePresentationMode = .nightConditionsFallback
    ) {
        self.isUnavailable = false
        self.assessment = assessment
        self.headlineScore = headlineScore ?? assessment.calculatedScore
        self.scorePresentationMode = scorePresentationMode
    }

    private init(unavailable: Bool) {
        self.isUnavailable = unavailable
        self.assessment = nil
        self.headlineScore = 0
        self.scorePresentationMode = .nightConditionsFallback
    }

    static var unavailable: CircularComplicationView {
        CircularComplicationView(unavailable: true)
    }

    var body: some View {
        if isUnavailable {
            VStack(spacing: -2) {
                Text(WatchComplicationUnavailablePresentation.scoreText)
                    .font(.system(size: 20, weight: .bold))
                Image(systemName: "sparkles")
                    .font(.caption2)
            }
            .padding(.top, 7)
            .accessibilityLabel(WatchComplicationUnavailablePresentation.accessibilityLabel)
            .containerBackground(.clear, for: .widget)
        } else if let assessment {
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
            .accessibilityLabel(scorePresentationMode.accessibilityLabel(score: headlineScore))
            .containerBackground(.clear, for: .widget)
        }
    }
}
