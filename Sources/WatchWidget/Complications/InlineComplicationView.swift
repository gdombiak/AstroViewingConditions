import SwiftUI
import SharedCode

struct InlineComplicationView: View {
    var assessment: NightQualityAssessment
    var headlineScore: Int

    init(assessment: NightQualityAssessment, headlineScore: Int? = nil) {
        self.assessment = assessment
        self.headlineScore = headlineScore ?? assessment.calculatedScore
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: ratingIcon(for: ObservingQualityScoreBand.from(score: headlineScore)))
            Text("\(headlineScore)")
        }
        .font(.caption)
        .foregroundStyle(assessment.scoreColor(for: headlineScore))
        .containerBackground(.clear, for: .widget)
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
