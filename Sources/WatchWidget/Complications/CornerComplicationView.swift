import SwiftUI
import SharedCode

struct CornerComplicationView: View {
    var assessment: NightQualityAssessment
    
    private var score: CGFloat { CGFloat(assessment.calculatedScore) }
    private var scoreColor: Color { assessment.scoreColor }
    
    var progress: Double {
        score / 100
    }
    
    var body: some View {
        Text("\(assessment.calculatedScore)")
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
