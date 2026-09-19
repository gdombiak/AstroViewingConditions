import SharedCode
import SwiftUI

struct TargetIntentBadge: View {
    let intent: TargetObservingIntent

    var body: some View {
        if let text = TargetIntentPresentation.badgeText(for: intent) {
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.12), in: Capsule())
                .accessibilityLabel("Challenge target")
        }
    }
}
