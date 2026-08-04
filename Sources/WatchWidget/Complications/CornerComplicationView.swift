import SwiftUI
import SharedCode

struct CornerComplicationView: View {
    var assessment: NightQualityAssessment
    var headlineScore: Int

    init(assessment: NightQualityAssessment, headlineScore: Int? = nil) {
        self.assessment = assessment
        self.headlineScore = headlineScore ?? assessment.calculatedScore
    }
    
    private var score: CGFloat { CGFloat(headlineScore) }
    private var scoreColor: Color { assessment.scoreColor(for: headlineScore) }
    
    var progress: Double {
        score / 100
    }
    
    var body: some View {
        Text("\(headlineScore)")
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(scoreColor)
            .minimumScaleFactor(0.8)
            .widgetLabel {
                ProgressView(value: progress)
                    .tint(scoreColor)
            }
    }
}
