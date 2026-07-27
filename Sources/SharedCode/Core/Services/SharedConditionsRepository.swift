import Foundation

/// Provenance for the payload in `conditions.json`. Keeping this in a
/// companion file avoids changing the long-lived `ViewingConditions` schema.
public struct SharedConditionsMetadata: Codable, Sendable, Equatable {
    public let locationID: UUID?
    public let latitude: Double
    public let longitude: Double
    public let weatherFetchedAt: Date
    public let issFetchedAt: Date?

    public init(
        locationID: UUID?,
        latitude: Double,
        longitude: Double,
        weatherFetchedAt: Date,
        issFetchedAt: Date?
    ) {
        self.locationID = locationID
        self.latitude = latitude
        self.longitude = longitude
        self.weatherFetchedAt = weatherFetchedAt
        self.issFetchedAt = issFetchedAt
    }

    init(conditions: ViewingConditions, issFetchedAt: Date?) {
        self.init(
            locationID: conditions.location.id,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            weatherFetchedAt: conditions.fetchedAt,
            issFetchedAt: issFetchedAt
        )
    }
}

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
            case issEnriched
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
    private let loadMetadata: @Sendable () async -> SharedConditionsMetadata?
    private let fetch: @Sendable (CachedLocation, String?) async throws -> ConditionsFetchResult
    private let fetchISS: @Sendable (CachedLocation, String) async -> ISSFetchResult
    private let persist: @Sendable (ViewingConditions, SharedConditionsMetadata) async -> Bool
    private let now: @Sendable () -> Date

    private init(
        load: @escaping @Sendable () async -> ViewingConditions?,
        loadMetadata: @escaping @Sendable () async -> SharedConditionsMetadata?,
        now: @escaping @Sendable () -> Date,
        fetch: @escaping @Sendable (CachedLocation, String?) async throws -> ConditionsFetchResult,
        fetchISS: @escaping @Sendable (CachedLocation, String) async -> ISSFetchResult,
        persist: @escaping @Sendable (ViewingConditions, SharedConditionsMetadata) async -> Bool
    ) {
        self.load = load
        self.loadMetadata = loadMetadata
        self.now = now
        self.fetch = fetch
        self.fetchISS = fetchISS
        self.persist = persist
    }

    public init() {
        self.init(
            load: { await AppGroupStorage.loadConditionsAsync() },
            loadMetadata: { await AppGroupStorage.loadConditionsMetadataAsync() },
            now: Date.init,
            fetch: { location, apiKey in
                try await ConditionsProvider().fetchConditionsWithDiagnostics(
                    for: location, days: Self.forecastDays, apiKey: apiKey
                )
            },
            fetchISS: { location, apiKey in
                await ConditionsProvider().fetchISSPasses(for: location, apiKey: apiKey)
            },
            persist: { conditions, metadata in
                await AppGroupStorage.saveConditionsAndMetadataAsync(conditions, metadata: metadata)
            }
        )
    }

    /// Dependency injection used by the repository tests and non-App-Group
    /// callers. Conditions are saved before their provenance record.
    public init(
        load: @escaping @Sendable () async -> ViewingConditions?,
        save: @escaping @Sendable (ViewingConditions) async -> Void,
        loadMetadata: @escaping @Sendable () async -> SharedConditionsMetadata? = { nil },
        saveMetadata: @escaping @Sendable (SharedConditionsMetadata) async -> Void = { _ in },
        now: @escaping @Sendable () -> Date = Date.init,
        fetch: @escaping @Sendable (CachedLocation, String?) async throws -> ConditionsFetchResult,
        fetchISS: @escaping @Sendable (CachedLocation, String) async -> ISSFetchResult = { _, _ in
            ISSFetchResult(passes: [], state: .notRequested)
        }
    ) {
        self.init(
            load: load,
            loadMetadata: loadMetadata,
            now: now,
            fetch: fetch,
            fetchISS: fetchISS,
            persist: { conditions, metadata in
                await save(conditions)
                await saveMetadata(metadata)
                return true
            }
        )
    }

    /// Convenience injection for tests and callers that do not need ISS
    /// diagnostics. Normal production fetching uses the initializer above.
    public init(
        load: @escaping @Sendable () async -> ViewingConditions?,
        save: @escaping @Sendable (ViewingConditions) async -> Void,
        loadMetadata: @escaping @Sendable () async -> SharedConditionsMetadata? = { nil },
        saveMetadata: @escaping @Sendable (SharedConditionsMetadata) async -> Void = { _ in },
        now: @escaping @Sendable () -> Date = Date.init,
        fetch: @escaping @Sendable (CachedLocation) async throws -> ViewingConditions
    ) {
        self.init(
            load: load,
            save: save,
            loadMetadata: loadMetadata,
            saveMetadata: saveMetadata,
            now: now,
            fetch: { location, _ in
                ConditionsFetchResult(conditions: try await fetch(location), issError: nil)
            }
        )
    }

    public init(provider: ConditionsProvider, now: @escaping @Sendable () -> Date = Date.init) {
        self.init(
            load: { await AppGroupStorage.loadConditionsAsync() },
            loadMetadata: { await AppGroupStorage.loadConditionsMetadataAsync() },
            now: now,
            fetch: { location, apiKey in
                try await provider.fetchConditionsWithDiagnostics(
                    for: location,
                    days: Self.forecastDays,
                    apiKey: apiKey
                )
            },
            fetchISS: { location, apiKey in
                await provider.fetchISSPasses(for: location, apiKey: apiKey)
            },
            persist: { conditions, metadata in
                await AppGroupStorage.saveConditionsAndMetadataAsync(conditions, metadata: metadata)
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
            guard let apiKey, !apiKey.isEmpty else {
                return Result(conditions: cached, source: .cache, issError: nil)
            }

            let metadata = await loadMetadata()
            if Self.isISSProvenanceFresh(
                metadata,
                for: cached,
                location: location,
                referenceDate: referenceDate
            ) {
                return Result(conditions: cached, source: .cache, issError: nil)
            }

            let issResult = await fetchISS(location, apiKey)
            switch issResult.state {
            case .succeeded:
                let enriched = Self.replacingISSPasses(in: cached, with: issResult.passes)
                let queryTime = now()
                _ = await persist(
                    enriched,
                    SharedConditionsMetadata(conditions: enriched, issFetchedAt: queryTime)
                )
                return Result(conditions: enriched, source: .issEnriched, issError: nil)
            case let .failed(error):
                // Fresh weather remains usable when ISS alone fails. Leaving
                // both files untouched preserves any prior successful record.
                return Result(conditions: cached, source: .cache, issError: error)
            case .notRequested:
                return Result(conditions: cached, source: .cache, issError: nil)
            }
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
        let issFetchedAt: Date?
        if case .succeeded = fetched.issFetchState {
            issFetchedAt = observedAt
        } else {
            issFetchedAt = nil
        }
        _ = await persist(
            conditionsToSave,
            SharedConditionsMetadata(conditions: conditionsToSave, issFetchedAt: issFetchedAt)
        )
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

    private static func isISSProvenanceFresh(
        _ metadata: SharedConditionsMetadata?,
        for conditions: ViewingConditions,
        location: CachedLocation,
        referenceDate: Date
    ) -> Bool {
        guard let metadata,
              let issFetchedAt = metadata.issFetchedAt,
              metadata.weatherFetchedAt == conditions.fetchedAt,
              WidgetLocationIdentity.matches(
                  summarySavedLocationID: metadata.locationID,
                  selectedSavedLocationID: location.id,
                  summaryLatitude: metadata.latitude,
                  summaryLongitude: metadata.longitude,
                  selectedLatitude: location.latitude,
                  selectedLongitude: location.longitude
              ),
              referenceDate.timeIntervalSince(issFetchedAt) >= 0,
              referenceDate.timeIntervalSince(issFetchedAt) < maximumAge
        else { return false }

        return LocationTimeZoneResolver.calendar(for: conditions.timeZone).isDate(
            issFetchedAt,
            inSameDayAs: referenceDate
        )
    }

    private static func replacingISSPasses(
        in conditions: ViewingConditions,
        with issPasses: [ISSPass]
    ) -> ViewingConditions {
        ViewingConditions(
            fetchedAt: conditions.fetchedAt,
            location: conditions.location,
            hourlyForecasts: conditions.hourlyForecasts,
            dailySunEvents: conditions.dailySunEvents,
            dailyMoonInfo: conditions.dailyMoonInfo,
            issPasses: issPasses,
            fogScore: conditions.fogScore,
            timeZoneIdentifier: conditions.timeZoneIdentifier
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
