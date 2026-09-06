import SwiftUI
import SharedCode

struct CornerComplicationView: View {
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

    static var unavailable: CornerComplicationView {
        CornerComplicationView(unavailable: true)
    }

    private var score: CGFloat { CGFloat(headlineScore) }
    private var scoreColor: Color {
        assessment?.scoreColor(for: headlineScore) ?? .secondary
    }

    var progress: Double {
        isUnavailable ? 0 : score / 100
    }

    var body: some View {
        if isUnavailable {
            Text(WatchComplicationUnavailablePresentation.scoreText)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(WatchComplicationUnavailablePresentation.accessibilityLabel)
                .widgetLabel {
                    ProgressView(value: progress)
                        .tint(.secondary)
                }
        } else {
            Text("\(headlineScore)")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(scoreColor)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(scorePresentationMode.accessibilityLabel(score: headlineScore))
                .widgetLabel {
                    ProgressView(value: progress)
                        .tint(scoreColor)
                }
        }
    }
}
