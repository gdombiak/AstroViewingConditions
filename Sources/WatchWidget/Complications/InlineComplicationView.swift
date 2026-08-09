import SwiftUI
import SharedCode

struct InlineComplicationView: View {
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

    static var unavailable: InlineComplicationView {
        InlineComplicationView(unavailable: true)
    }

    var body: some View {
        if isUnavailable {
            HStack(spacing: 2) {
                Image(systemName: "sparkles")
                Text(WatchComplicationUnavailablePresentation.scoreText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(WatchComplicationUnavailablePresentation.accessibilityLabel)
            .containerBackground(.clear, for: .widget)
        } else if let assessment {
            HStack(spacing: 2) {
                Image(systemName: ratingIcon(for: ObservingQualityScoreBand.from(score: headlineScore)))
                Text("\(headlineScore)")
            }
            .font(.caption)
            .foregroundStyle(assessment.scoreColor(for: headlineScore))
            .accessibilityLabel(scorePresentationMode.accessibilityLabel(score: headlineScore))
            .containerBackground(.clear, for: .widget)
        }
    }

    private func ratingIcon(for band: ObservingQualityScoreBand) -> String {
        switch band {
        case .excellent: return "moon.stars.fill"
        case .good: return "sparkles"
        case .fair: return "cloud.fill"
        case .poor: return "cloud.sun.fill"
        }
    }
}
