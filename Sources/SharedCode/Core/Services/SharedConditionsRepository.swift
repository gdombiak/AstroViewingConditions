import Foundation

/// The single owner of normal weather-condition cache and freshness decisions.
///
/// `conditions.json` in the App Group is intentionally the only persistent
/// cache used here. Widget summary files are presentation fallbacks and never
/// determine whether weather conditions are fresh. A cache hit is valid even
/// when it has no ISS passes: ISS availability is not weather freshness.
public struct SharedConditionsRepository: Sendable {
    public static let maximumAge: TimeInterval = 3600
    public static let forecastDays = 4

    public struct Result: Sendable {
        public enum Source: Sendable, Equatable {
            case cache
            case fetched
        }

        public let conditions: ViewingConditions
        public let source: Source
        public let issError: ISSError?

        public init(conditions: ViewingConditions, source: Source, issError: ISSError?) {
            self.conditions = conditions
            self.source = source
            self.issError = issError
        }
    }

    public enum RefreshError: Error {
        case invalidFetchedConditions
    }

    private let load: @Sendable () async -> ViewingConditions?
    private let save: @Sendable (ViewingConditions) async -> Void
    private let fetch: @Sendable (CachedLocation, String?) async throws -> ConditionsFetchResult
    private let now: @Sendable () -> Date

    public init(
        load: @escaping @Sendable () async -> ViewingConditions? = {
            await AppGroupStorage.loadConditionsAsync()
        },
        save: @escaping @Sendable (ViewingConditions) async -> Void = { conditions in
            await AppGroupStorage.saveConditionsAsync(conditions)
        },
        now: @escaping @Sendable () -> Date = Date.init,
        fetch: @escaping @Sendable (CachedLocation, String?) async throws -> ConditionsFetchResult = {
            location, apiKey in
            try await ConditionsProvider().fetchConditionsWithDiagnostics(
                for: location,
                days: Self.forecastDays,
                apiKey: apiKey
            )
        }
    ) {
        self.load = load
        self.save = save
        self.now = now
        self.fetch = fetch
    }

    /// Convenience injection for tests and callers that do not need ISS
    /// diagnostics. Normal production fetching uses the initializer above.
    public init(
        load: @escaping @Sendable () async -> ViewingConditions?,
        save: @escaping @Sendable (ViewingConditions) async -> Void,
        now: @escaping @Sendable () -> Date = Date.init,
        fetch: @escaping @Sendable (CachedLocation) async throws -> ViewingConditions
    ) {
        self.init(
            load: load,
            save: save,
            now: now,
            fetch: { location, _ in
                ConditionsFetchResult(conditions: try await fetch(location), issError: nil)
            }
        )
    }

    public init(provider: ConditionsProvider, now: @escaping @Sendable () -> Date = Date.init) {
        self.init(
            now: now,
            fetch: { location, apiKey in
                try await provider.fetchConditionsWithDiagnostics(
                    for: location,
                    days: Self.forecastDays,
                    apiKey: apiKey
                )
            }
        )
    }

    public func conditions(
        for location: CachedLocation,
        apiKey: String? = nil,
        referenceDate: Date = Date(),
        forceRefresh: Bool = false
    ) async throws -> Result {
        let cached = await load()
        if !forceRefresh,
           let cached,
           Self.isUsable(cached, for: location, referenceDate: referenceDate) {
            return Result(conditions: cached, source: .cache, issError: nil)
        }

        let fetched = try await fetch(location, apiKey)
        let observedAt = now()
        guard Self.isConditionsLevelValid(
            fetched.conditions,
            for: location,
            referenceDate: referenceDate,
            observedAt: observedAt
        ) else {
            throw RefreshError.invalidFetchedConditions
        }

        // A no-key widget refresh may need to replace stale weather. Preserve
        // only still-relevant same-local-day ISS passes so it does not discard
        // app-fetched passes or carry an earlier day's schedule forward.
        let conditionsToSave: ViewingConditions
        if (apiKey?.isEmpty ?? true),
           let cached,
           Self.locationMatches(cached.location, location),
           Self.belongsToSameLocalDay(
               cached,
               as: fetched.conditions,
               timeZone: fetched.conditions.timeZone
           ) {
            let relevantISSPasses = cached.issPasses.filter {
                Self.latestMeaningfulTime(for: $0) >= observedAt
            }
            conditionsToSave = ViewingConditions(
                fetchedAt: fetched.conditions.fetchedAt,
                location: fetched.conditions.location,
                hourlyForecasts: fetched.conditions.hourlyForecasts,
                dailySunEvents: fetched.conditions.dailySunEvents,
                dailyMoonInfo: fetched.conditions.dailyMoonInfo,
                issPasses: relevantISSPasses.isEmpty
                    ? fetched.conditions.issPasses
                    : relevantISSPasses,
                fogScore: fetched.conditions.fogScore,
                timeZoneIdentifier: fetched.conditions.timeZoneIdentifier
            )
        } else {
            conditionsToSave = fetched.conditions
        }
        await save(conditionsToSave)
        return Result(
            conditions: conditionsToSave,
            source: .fetched,
            issError: fetched.issError
        )
    }

    /// Provides an identity-matching shared payload for presentation fallback
    /// only; it deliberately does not apply the normal freshness policy.
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
        isConditionsLevelValid(
            conditions,
            for: location,
            referenceDate: referenceDate,
            observedAt: referenceDate
        ) && isFreshForCurrentLocalDay(
                conditions,
                maximumAge: maximumAge,
                referenceDate: referenceDate
            )
    }

    /// Shared timestamp/local-day freshness rule for already loaded
    /// conditions. This intentionally does not evaluate location identity.
    public static func isFreshForCurrentLocalDay(
        _ conditions: ViewingConditions,
        maximumAge: TimeInterval = maximumAge,
        referenceDate: Date = Date()
    ) -> Bool {
        conditions.isFreshForLocalDay(within: maximumAge, relativeTo: referenceDate)
    }

    /// Conditions acceptance is intentionally transport/domain-level only.
    /// Widget-specific target recommendation and presentation requirements are
    /// evaluated after this method succeeds.
    public static func isConditionsLevelValid(
        _ conditions: ViewingConditions,
        for location: CachedLocation,
        referenceDate: Date = Date(),
        observedAt: Date? = nil
    ) -> Bool {
        let observedAt = observedAt ?? referenceDate
        let timeZone = conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        guard locationMatches(conditions.location, location),
              observedAt.timeIntervalSince(conditions.fetchedAt) >= 0,
              calendar.isDate(conditions.fetchedAt, inSameDayAs: referenceDate),
              !conditions.hourlyForecasts.isEmpty,
              conditions.dailySunEvents.count >= forecastDays,
              conditions.dailyMoonInfo.count >= forecastDays
        else { return false }
        return true
    }

    public static func locationMatches(_ cached: CachedLocation, _ selected: CachedLocation) -> Bool {
        WidgetLocationIdentity.matches(
            summarySavedLocationID: cached.id,
            selectedSavedLocationID: selected.id,
            summaryLatitude: cached.latitude,
            summaryLongitude: cached.longitude,
            selectedLatitude: selected.latitude,
            selectedLongitude: selected.longitude
        )
    }

    private static func belongsToSameLocalDay(
        _ cached: ViewingConditions,
        as fetched: ViewingConditions,
        timeZone: TimeZone
    ) -> Bool {
        LocationTimeZoneResolver.calendar(for: timeZone).isDate(
            cached.fetchedAt,
            inSameDayAs: fetched.fetchedAt
        )
    }

    private static func latestMeaningfulTime(for pass: ISSPass) -> Date {
        // `setTime` uses an API-provided end time when present and otherwise
        // derives the end from the pass duration, so an in-progress pass is
        // retained instead of being discarded solely because its rise elapsed.
        [pass.riseTime, pass.maxTime, pass.setTime]
            .compactMap { $0 }
            .max() ?? pass.riseTime
    }
}

private extension ViewingConditions {
    var timeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: location.longitude)
    }
}
