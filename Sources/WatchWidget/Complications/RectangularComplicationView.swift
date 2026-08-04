import SwiftUI
import SharedCode

struct RectangularComplicationView: View {
    var assessment: NightQualityAssessment
    var headlineScore: Int

    init(assessment: NightQualityAssessment, headlineScore: Int? = nil) {
        self.assessment = assessment
        self.headlineScore = headlineScore ?? assessment.calculatedScore
    }

    var body: some View {
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
        .containerBackground(.clear, for: .widget)
    }
}
