import SwiftUI
import SharedCode

struct InlineComplicationView: View {
    var assessment: NightQualityAssessment

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: ratingIcon(for: assessment.rating))
            Text("\(assessment.calculatedScore)")
        }
        .font(.caption)
        .foregroundStyle(assessment.rating.color)
        .containerBackground(.clear, for: .widget)
    }

    private func ratingIcon(for rating: NightQualityAssessment.Rating) -> String {
        switch rating {
        case .excellent: return "moon.stars.fill"
        case .good: return "sparkles"
        case .fair: return "cloud.fill"
        case .poor: return "cloud.sun.fill"
        }
    }
}
