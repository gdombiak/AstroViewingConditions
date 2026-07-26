import Foundation
import SharedCode

enum TonightTargetsWidgetPublicationDecision {
    case publish(TargetRecommendationContextResolution)
    case preserveExisting
    case unavailable
}

/// Selects the observing night that widget publication should represent.
/// Context assembly remains exclusively in `TargetRecommendationContextBuilder`.
enum TonightTargetsWidgetContextResolver {
    static func publicationDecision(
        conditions: ViewingConditions,
        existingSummary: WidgetTonightTargetsSummary?,
        referenceDate: Date,
        timeZone: TimeZone?
    ) -> TonightTargetsWidgetPublicationDecision {
        let activeResolution = ActiveObservingNightResolver.resolve(
            conditions: conditions, referenceDate: referenceDate, timeZone: timeZone
        )
        if case let .resolved(resolution) = activeResolution { return .publish(resolution) }
        guard case let .requiresActivePreviousPayload(resolvedTimeZone) = activeResolution else {
            return .unavailable
        }

        // Fresh Open-Meteo/ConditionsProvider data starts at the current local
        // calendar day, so the previous Sun/Moon slot is unavailable here.
        // Preserve a still-valid app-resolved payload rather than constructing
        // the active night from the current day's upcoming-evening inputs.
        if let existingSummary,
           isValidActivePreviousNightPayload(
            existingSummary,
            conditions: conditions,
            referenceDate: referenceDate,
            timeZone: resolvedTimeZone
           ) {
            return .preserveExisting
        }

        return .unavailable
    }

    private static func isValidActivePreviousNightPayload(
        _ summary: WidgetTonightTargetsSummary,
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> Bool {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        guard !calendar.isDate(
            summary.observingDate,
            inSameDayAs: referenceDate
        ),
        summary.locationMatches(conditions.location),
        summary.isWithinMaximumAge(
            WidgetTonightTargetsSummary.maximumAge,
            relativeTo: referenceDate
        ),
        let nightStart = summary.astronomicalNightStart,
        let nightEnd = summary.astronomicalNightEnd,
        referenceDate >= nightStart,
        referenceDate <= nightEnd else {
            return false
        }

        switch summary.status {
        case .available:
            return !summary.targets.isEmpty
        case .noTargets:
            return true
        case .unavailable:
            return false
        }
    }
}
