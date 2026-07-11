import SwiftUI

enum TargetScoreColorProvider {
    enum Category: Equatable {
        case excellent
        case good
        case fair
        case poor
    }

    static func category(for score: Int) -> Category {
        switch score {
        case 80...100: return .excellent
        case 60..<80: return .good
        case 40..<60: return .fair
        default: return .poor
        }
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
