import Foundation
import SharedCode
import SwiftUI

enum WidgetDataProvenance: Sendable, Equatable {
    case normal
    case fallback
}

/// Transient conditions metadata carried by a timeline entry. This deliberately
/// stays out of the persisted widget summaries: it describes this provider run.
struct WidgetDataStatus: Sendable, Equatable {
    let dataAsOf: Date
    let timeZone: TimeZone
    let provenance: WidgetDataProvenance

    init(
        dataAsOf: Date,
        timeZoneIdentifier: String?,
        longitude: Double,
        provenance: WidgetDataProvenance
    ) {
        self.dataAsOf = dataAsOf
        self.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: longitude)
        self.provenance = provenance
    }

    static func normal(conditions: ViewingConditions) -> Self {
        from(conditions: conditions, provenance: .normal)
    }

    static func fallback(conditions: ViewingConditions) -> Self {
        from(conditions: conditions, provenance: .fallback)
    }

    static func normal(summary: WidgetTonightTargetsSummary) -> Self {
        Self(
            dataAsOf: summary.generatedAt,
            timeZoneIdentifier: summary.timeZoneIdentifier,
            longitude: summary.longitude,
            provenance: .normal
        )
    }

    static func normal(summary: WidgetThreeNightOutlookSummary) -> Self {
        Self(
            dataAsOf: summary.generatedAt,
            timeZoneIdentifier: summary.timeZoneIdentifier,
            longitude: summary.longitude,
            provenance: .normal
        )
    }

    static func fallback(summary: WidgetNightSummary) -> Self {
        Self(
            dataAsOf: summary.generatedAt,
            timeZoneIdentifier: summary.timeZoneIdentifier,
            longitude: summary.longitude,
            provenance: .fallback
        )
    }

    static func fallback(summary: WidgetTonightTargetsSummary) -> Self {
        Self(
            dataAsOf: summary.generatedAt,
            timeZoneIdentifier: summary.timeZoneIdentifier,
            longitude: summary.longitude,
            provenance: .fallback
        )
    }

    static func fallback(summary: WidgetThreeNightOutlookSummary) -> Self {
        Self(
            dataAsOf: summary.generatedAt,
            timeZoneIdentifier: summary.timeZoneIdentifier,
            longitude: summary.longitude,
            provenance: .fallback
        )
    }

    private static func from(
        conditions: ViewingConditions,
        provenance: WidgetDataProvenance
    ) -> Self {
        Self(
            dataAsOf: conditions.fetchedAt,
            timeZoneIdentifier: conditions.timeZoneIdentifier,
            longitude: conditions.location.longitude,
            provenance: provenance
        )
    }
}

enum WidgetDataAsOfPresentation {
    static func dataAsOfText(
        dataDate: Date,
        referenceDate: Date,
        timeZone: TimeZone,
        locale: Locale = .current,
        calendar: Calendar? = nil
    ) -> String {
        var comparisonCalendar = calendar ?? Calendar(identifier: .gregorian)
        comparisonCalendar.timeZone = timeZone

        let formatted: String
        if comparisonCalendar.isDate(dataDate, inSameDayAs: referenceDate) {
            formatted = formatterCache.string(
                from: dataDate,
                template: "jm",
                locale: locale,
                timeZone: timeZone
            )
        } else if comparisonCalendar.component(.year, from: dataDate)
                    == comparisonCalendar.component(.year, from: referenceDate) {
            formatted = formatterCache.string(
                from: dataDate,
                template: "MMMd",
                locale: locale,
                timeZone: timeZone
            ) + ", " + formatterCache.string(
                from: dataDate,
                template: "jm",
                locale: locale,
                timeZone: timeZone
            )
        } else {
            formatted = formatterCache.string(
                from: dataDate,
                template: "yMMMd",
                locale: locale,
                timeZone: timeZone
            ) + ", " + formatterCache.string(
                from: dataDate,
                template: "jm",
                locale: locale,
                timeZone: timeZone
            )
        }
        return "Data as of " + formatted
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func isVisible(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return true
        case .xLarge, .xxLarge, .xxxLarge,
             .accessibility1, .accessibility2, .accessibility3,
             .accessibility4, .accessibility5:
            return false
        @unknown default:
            return false
        }
    }

    private static let formatterCache = FormatterCache()

}

private final class FormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func string(from date: Date, template: String, locale: Locale, timeZone: TimeZone) -> String {
        let key = [template, locale.identifier, timeZone.identifier].joined(separator: "|")
        lock.lock()
        defer { lock.unlock() }

        if let formatter = formatters[key] { return formatter.string(from: date) }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter.string(from: date)
    }
}

struct WidgetDataAsOfStatusView: View {
    let status: WidgetDataStatus
    let referenceDate: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if WidgetDataAsOfPresentation.isVisible(for: dynamicTypeSize) {
            Text(WidgetDataAsOfPresentation.dataAsOfText(
                dataDate: status.dataAsOf,
                referenceDate: referenceDate,
                timeZone: status.timeZone
            ))
            .font(.caption2)
            .foregroundStyle(status.provenance == .fallback ? .red : .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
