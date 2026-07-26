import Foundation
import SharedCode
import SwiftUI

enum WidgetThreeNightOutlookPresentation {
    static func windowText(
        for night: WidgetThreeNightOutlookNight,
        timeZone: TimeZone?,
        compact: Bool
    ) -> String {
        guard let window = night.bestWindow else { return night.statusText }
        let text = DateFormatters.formatTimeRange(from: window.start, to: window.end, in: timeZone)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
        return compact ? "Best \(text)" : "Best window \(text)"
    }
}

enum ThreeNightOutlookLayoutMode: Sendable, Hashable {
    case standardWithLocationPreference
    case largestStandard
    case accessibility
}

enum ThreeNightOutlookLayoutPolicy {
    static func mode(for dynamicTypeSize: DynamicTypeSize) -> ThreeNightOutlookLayoutMode {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large, .xLarge, .xxLarge:
            return .standardWithLocationPreference
        case .xxxLarge:
            return .largestStandard
        case .accessibility1, .accessibility2, .accessibility3,
             .accessibility4, .accessibility5:
            return .accessibility
        @unknown default:
            return .accessibility
        }
    }
}
