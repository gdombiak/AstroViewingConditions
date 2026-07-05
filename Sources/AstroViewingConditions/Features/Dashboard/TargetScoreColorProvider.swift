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

    static func color(for score: Int) -> Color {
        switch category(for: score) {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}
