import Foundation
import SharedCode
import SwiftUI

enum WidgetContentDensity: Sendable, Hashable {
    case regular
    case compact
    case minimal

    static func resolve(for dynamicTypeSize: DynamicTypeSize) -> WidgetContentDensity {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large, .xLarge:
            return .regular
        case .xxLarge, .xxxLarge, .accessibility1, .accessibility2:
            return .compact
        case .accessibility3, .accessibility4, .accessibility5:
            return .minimal
        @unknown default:
            return .minimal
        }
    }
}

struct SmallConditionSummary: Equatable {
    let label: String
    let symbol: String?
}

enum WidgetTonightPresentation {
    static func trendLabel(for trend: NightQualityAssessment.Trend) -> String {
        switch trend {
        case .improving: return "Improving"
        case .stable: return "Steady"
        case .degrading: return "Degrading"
        }
    }

    static func trendSymbol(for trend: NightQualityAssessment.Trend) -> String {
        switch trend {
        case .improving: return "↗"
        case .stable: return "→"
        case .degrading: return "↘"
        }
    }

    static func smallConditionSummary(
        earlyQuality: String,
        lateQuality: String,
        trend: NightQualityAssessment.Trend
    ) -> SmallConditionSummary {
        guard earlyQuality == lateQuality else {
            return SmallConditionSummary(label: "\(earlyQuality) → \(lateQuality)", symbol: nil)
        }
        return SmallConditionSummary(label: trendLabel(for: trend), symbol: trendSymbol(for: trend))
    }

    static func bestWindowText(
        _ window: NightQualityAssessment.TimeWindow?,
        timeZone: TimeZone?
    ) -> String? {
        guard let window else { return nil }
        return DateFormatters.formatTimeRange(from: window.start, to: window.end, in: timeZone)
    }

    static func compactBestWindowText(
        _ window: NightQualityAssessment.TimeWindow?,
        timeZone: TimeZone?
    ) -> String? {
        guard let window else { return nil }
        let start = compactTime(window.start, timeZone: timeZone).replacingOccurrences(of: " ", with: "\u{00A0}")
        let end = compactTime(window.end, timeZone: timeZone).replacingOccurrences(of: " ", with: "\u{00A0}")
        return "\(start)\u{2060}–\u{2060}\(end)"
    }

    static func smallLayoutShowsConditionSummary(for density: WidgetContentDensity) -> Bool {
        density != .minimal
    }

    static func mediumLayoutFactors(
        _ factors: [NightQualityDisplayFactor],
        density: WidgetContentDensity,
        includesFactors: Bool = true
    ) -> [NightQualityDisplayFactor] {
        guard includesFactors else { return [] }
        guard density != .regular, factors.count > 2 else { return factors }
        return [factors[0], factors[factors.count - 1]]
    }

    static func mediumCondensedFactorSummary(
        _ factors: [NightQualityDisplayFactor],
        density: WidgetContentDensity
    ) -> String? {
        let displayFactors = mediumLayoutFactors(factors, density: density)
        guard !displayFactors.isEmpty else { return nil }
        return displayFactors.map { "\($0.label) \($0.value)" }.joined(separator: "  •  ")
    }

    static func mediumLayoutShowsLocation(for density: WidgetContentDensity) -> Bool {
        density == .regular
    }

    private static func compactTime(_ date: Date, timeZone: TimeZone?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? .current

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return formatter.string(from: date)
    }
}
