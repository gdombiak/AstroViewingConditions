import Foundation

/// Shared score bands used by target presentation in the app and widgets.
public enum TargetScoreCategory: Sendable {
    case excellent
    case good
    case fair
    case poor

    public static func resolve(_ score: Int) -> Self {
        switch score {
        case 80...: return .excellent
        case 65..<80: return .good
        case 45..<65: return .fair
        default: return .poor
        }
    }
}
