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
        let previousResolution = TargetRecommendationContextBuilder.resolve(
            conditions: conditions,
            dayOffset: -1,
            referenceDate: referenceDate,
            timeZone: timeZone
        )

        if let previousResolution,
           contains(
            referenceDate,
            in: previousResolution.context
           ) {
            return .publish(previousResolution)
        }

        guard let currentResolution = TargetRecommendationContextBuilder.resolve(
            conditions: conditions,
            dayOffset: 0,
            referenceDate: referenceDate,
            timeZone: timeZone
        ) else {
            return .unavailable
        }

        guard isPreviousNightTail(
            referenceDate,
            currentResolution: currentResolution
        ) else {
            return .publish(currentResolution)
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
            timeZone: currentResolution.timeZone
           ) {
            return .preserveExisting
        }

        return .unavailable
    }

    private static func contains(
        _ referenceDate: Date,
        in context: TargetRecommendationContext
    ) -> Bool {
        referenceDate >= context.astronomicalNightStart
            && referenceDate <= context.astronomicalNightEnd
    }

    private static func isPreviousNightTail(
        _ referenceDate: Date,
        currentResolution: TargetRecommendationContextResolution
    ) -> Bool {
        let calendar = LocationTimeZoneResolver.calendar(
            for: currentResolution.timeZone
        )
        return calendar.isDate(
            currentResolution.observingDate,
            inSameDayAs: referenceDate
        ) && referenceDate <= currentResolution.sunEventsToday.astronomicalTwilightBegin
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
        summary.locationMatches(
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude
        ),
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
