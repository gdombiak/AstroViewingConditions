import SwiftUI

extension LocationScore {
    public var color: Color {
        switch LocationScoreCategory.resolve(score) {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}
