import Foundation

public enum ActiveObservingNightResolution {
    case resolved(TargetRecommendationContextResolution)
    case requiresActivePreviousPayload(TimeZone)
    case unavailable
}

/// The single authority for choosing Tonight across local midnight.
public enum ActiveObservingNightResolver {
    public static func resolve(
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone?
    ) -> ActiveObservingNightResolution {
        if let previous = TargetRecommendationContextBuilder.resolve(
            conditions: conditions, dayOffset: -1, referenceDate: referenceDate, timeZone: timeZone
        ), referenceDate >= previous.context.astronomicalNightStart,
           referenceDate <= previous.context.astronomicalNightEnd {
            return .resolved(previous)
        }

        guard let current = TargetRecommendationContextBuilder.resolve(
            conditions: conditions, dayOffset: 0, referenceDate: referenceDate, timeZone: timeZone
        ) else { return .unavailable }

        let calendar = LocationTimeZoneResolver.calendar(for: current.timeZone)
        if calendar.isDate(current.observingDate, inSameDayAs: referenceDate),
           referenceDate <= current.sunEventsToday.astronomicalTwilightBegin {
            return .requiresActivePreviousPayload(current.timeZone)
        }
        return .resolved(current)
    }
}
