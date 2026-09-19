import Foundation
import AstroEngine

public enum ActiveObservingNightResolution {
    case resolved(TargetRecommendationContextResolution)
    case requiresActivePreviousPayload(TimeZone)
    case unavailable
}

/// The single authority for choosing Tonight across local midnight.
///
/// The date/night identity decision itself is portable and lives in
/// ``AstroEngine/ObservingNightSelector``
/// (`observing_night.resolve_active`, contracts/procedures/observing-night.md).
/// This type resolves the zone with the host precedence, delegates the decision,
/// and maps the result back onto the existing host states — including
/// ``ActiveObservingNightResolution/requiresActivePreviousPayload(_:)``, which
/// widget and Watch callers use to preserve an already-published previous-night
/// payload. Recommendation context assembly stays in
/// ``TargetRecommendationContextBuilder``.
public enum ActiveObservingNightResolver {
    public static func resolve(
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone?
    ) -> ActiveObservingNightResolution {
        let resolvedTimeZone = LocationTimeZoneResolver.authoritative(
            preferred: timeZone,
            timeZoneIdentifier: conditions.timeZoneIdentifier,
            longitude: conditions.location.longitude
        )
        let selection = ObservingNightSelector.select(
            referenceDate: referenceDate,
            timeZone: resolvedTimeZone,
            forecastStartTime: conditions.hourlyForecasts.first?.time,
            dailySunEvents: conditions.dailySunEvents.map(
                ObservingNightSelector.DailySunEvents.init
            ),
            dailyMoonCount: conditions.dailyMoonInfo.count
        )

        switch selection {
        case let .selected(night):
            // The engine applies exactly the guards the builder applies to the
            // same arrays, so the builder cannot fail for a selected offset.
            // The defensive branch keeps the pre-migration "no context, no
            // night" outcome.
            guard let resolution = TargetRecommendationContextBuilder.resolve(
                conditions: conditions,
                dayOffset: night.dayOffset,
                referenceDate: referenceDate,
                timeZone: timeZone
            ) else { return .unavailable }
            return .resolved(resolution)
        case .requiresActivePreviousPayload:
            return .requiresActivePreviousPayload(resolvedTimeZone)
        case .unavailable:
            return .unavailable
        }
    }
}
