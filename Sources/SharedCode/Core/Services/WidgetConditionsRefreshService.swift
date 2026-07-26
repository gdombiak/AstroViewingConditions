import Foundation

/// Supplies Home Screen widgets with weather conditions from the shared App
/// Group cache, refreshing it only when its location or local-day freshness is
/// no longer valid. Processes intentionally do not coordinate refreshes: each
/// successful complete write atomically replaces the previous payload.
public struct WidgetConditionsRefreshService: Sendable {
    public static let maximumAge: TimeInterval = 3600
    public static let forecastDays = 4

    public enum RefreshError: Error {
        case invalidFetchedConditions
    }

    private let load: @Sendable () async -> ViewingConditions?
    private let save: @Sendable (ViewingConditions) async -> Void
    private let fetch: @Sendable (CachedLocation) async throws -> ViewingConditions

    public init(
        load: @escaping @Sendable () async -> ViewingConditions? = {
            await AppGroupStorage.loadConditionsAsync()
        },
        save: @escaping @Sendable (ViewingConditions) async -> Void = { conditions in
            await AppGroupStorage.saveConditionsAsync(conditions)
        },
        fetch: @escaping @Sendable (CachedLocation) async throws -> ViewingConditions = {
            location in
            try await ConditionsProvider().fetchConditions(
                for: location,
                days: Self.forecastDays
            )
        }
    ) {
        self.load = load
        self.save = save
        self.fetch = fetch
    }

    public func conditions(
        for location: CachedLocation,
        maximumAge: TimeInterval = Self.maximumAge,
        referenceDate: Date = Date()
    ) async throws -> ViewingConditions {
        if let cached = await load(),
           Self.isUsable(
               cached,
               for: location,
               maximumAge: maximumAge,
               referenceDate: referenceDate
           ),
           Self.hasCompleteWidgetPayload(
               cached,
               referenceDate: referenceDate
           ) {
            return cached
        }

        let fetched = try await fetch(location)
        guard Self.isUsable(
            fetched,
            for: location,
            maximumAge: maximumAge,
            referenceDate: referenceDate
        ), Self.hasCompleteWidgetPayload(
            fetched,
            referenceDate: referenceDate
        ) else {
            throw RefreshError.invalidFetchedConditions
        }
        await save(fetched)
        return fetched
    }

    public func matchingCachedConditions(for location: CachedLocation) async -> ViewingConditions? {
        guard let cached = await load(), Self.locationMatches(cached.location, location) else {
            return nil
        }
        return cached
    }

    public static func isUsable(
        _ conditions: ViewingConditions,
        for location: CachedLocation,
        maximumAge: TimeInterval = maximumAge,
        referenceDate: Date = Date()
    ) -> Bool {
        referenceDate.timeIntervalSince(conditions.fetchedAt) >= 0
            && locationMatches(conditions.location, location)
            && conditions.isFreshForLocalDay(within: maximumAge, relativeTo: referenceDate)
    }

    /// Validates that a payload can serve every widget. Cache freshness and
    /// identity are intentionally handled by `isUsable` so an older or
    /// incomplete payload can still be considered by provider-specific fallback.
    public static func hasCompleteWidgetPayload(
        _ conditions: ViewingConditions,
        referenceDate: Date = Date()
    ) -> Bool {
        guard conditions.dailySunEvents.count >= forecastDays,
              conditions.dailyMoonInfo.count >= forecastDays,
              let firstForecast = conditions.hourlyForecasts.min(by: { $0.time < $1.time })
        else { return false }

        let timeZone = conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let firstForecastDay = calendar.startOfDay(for: firstForecast.time)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        guard calendar.isDate(firstForecastDay, inSameDayAs: referenceDay) else { return false }

        // ConditionsProvider requests four local days. Require hourly weather
        // coverage for every requested day so the Tonight and three-night
        // pipelines have usable weather rather than merely astronomy metadata.
        for dayOffset in 0..<forecastDays {
            guard let dayStart = calendar.date(
                byAdding: .day, value: dayOffset, to: firstForecastDay
            ), let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
            conditions.hourlyForecasts.contains(where: { forecast in
                forecast.time >= dayStart && forecast.time < dayEnd
            }) else { return false }
        }

        // These are the canonical context inputs for Tonight and the three
        // outlook nights. Resolving each proves the arrays and forecast origin
        // can actually drive the existing builders without hand-rolled logic.
        return (0..<3).allSatisfy { dayOffset in
            TargetRecommendationContextBuilder.resolve(
                conditions: conditions,
                dayOffset: dayOffset,
                referenceDate: referenceDate,
                timeZone: timeZone
            ) != nil
        }
    }

    private static func locationMatches(_ cached: CachedLocation, _ selected: CachedLocation) -> Bool {
        WidgetLocationIdentity.matches(
            summarySavedLocationID: cached.id,
            selectedSavedLocationID: selected.id,
            summaryLatitude: cached.latitude,
            summaryLongitude: cached.longitude,
            selectedLatitude: selected.latitude,
            selectedLongitude: selected.longitude
        )
    }
}
