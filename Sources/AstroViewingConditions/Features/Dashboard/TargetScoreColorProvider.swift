import SwiftUI
import SharedCode

enum TargetScoreColorProvider {
    typealias Category = TargetScoreCategory

    static func category(for score: Int) -> Category {
        TargetScoreCategory.resolve(score)
    }

    static func color(for score: Int, palette: AppPalette = .normal) -> Color {
        switch category(for: score) {
        case .excellent: return palette.statusColor(.positive)
        case .good: return palette.statusColor(.informational)
        case .fair: return palette.statusColor(.caution)
        case .poor: return palette.statusColor(.negative)
        }
    }
}
