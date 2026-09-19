import SwiftUI
import SharedCode

struct RectangularComplicationView: View {
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

    static var unavailable: RectangularComplicationView {
        RectangularComplicationView(unavailable: true)
    }

    var body: some View {
        if isUnavailable {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(
                        WatchComplicationUnavailablePresentation.title,
                        systemImage: "sparkles"
                    )
                    .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(WatchComplicationUnavailablePresentation.scoreText)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(WatchComplicationUnavailablePresentation.detail)
                    .font(.system(size: 15))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(WatchComplicationUnavailablePresentation.accessibilityLabel)
            .containerBackground(.clear, for: .widget)
        } else if let assessment {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("Night Conditions", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(headlineScore)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(assessment.scoreColor(for: headlineScore))
                    Text("/100")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 4) {
                    Text(assessment.rating.emoji)
                        .font(.system(size: 14))

                    Text(assessment.summary)
                        .font(.system(size: 15))
                        .fontWeight(.medium)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(assessment.ratingColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
            }
            // Visible layout unchanged; accessibility distinguishes OQ vs weather-only fallback.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(scorePresentationMode.accessibilityLabel(score: headlineScore))
            .containerBackground(.clear, for: .widget)
        }
    }
}
