import XCTest
import SharedCode
@testable import AstroViewingConditions

final class WatchConditionsRequestAcquirerTests: XCTestCase {
    private actor Store {
        var conditions: ViewingConditions?
        var metadata: SharedConditionsMetadata?
        var weatherFetches = 0
        var issFetches = 0

        init(_ conditions: ViewingConditions? = nil) { self.conditions = conditions }
        func load() -> ViewingConditions? { conditions }
        func save(_ conditions: ViewingConditions) { self.conditions = conditions }
        func loadMetadata() -> SharedConditionsMetadata? { metadata }
        func saveMetadata(_ metadata: SharedConditionsMetadata) { self.metadata = metadata }
        func recordWeatherFetch() { weatherFetches += 1 }
        func recordISSFetch() { issFetches += 1 }
    }

    func testFreshSharedCacheServesWatchRequestWithoutWeatherFetch() async {
        let cached = Self.conditions(fetchedAt: Self.now)
        let store = Store(cached)
        let acquirer = WatchConditionsRequestAcquirer(conditionsRepository: Self.repository(
            store: store,
            fetch: { _, _ in
                XCTFail("Fresh shared cache must not fetch weather")
                throw TestError.failed
            }
        ))

        let result = await acquirer.conditions(for: Self.location, apiKey: "", referenceDate: Self.now)

        XCTAssertEqual(result?.fetchedAt, cached.fetchedAt)
        let weatherFetches = await store.weatherFetches
        XCTAssertEqual(weatherFetches, 0)
    }

    func testStaleWeatherUsesNormalRepositoryRefreshForWatchRequest() async {
        let stale = Self.conditions(fetchedAt: Self.now.addingTimeInterval(-3601))
        let refreshed = Self.conditions(fetchedAt: Self.now)
        let store = Store(stale)
        let acquirer = WatchConditionsRequestAcquirer(conditionsRepository: Self.repository(
            store: store,
            fetch: { _, _ in
                await store.recordWeatherFetch()
                return ConditionsFetchResult(conditions: refreshed, issError: nil)
            }
        ))

        let result = await acquirer.conditions(for: Self.location, apiKey: "", referenceDate: Self.now)

        XCTAssertEqual(result?.fetchedAt, refreshed.fetchedAt)
        let weatherFetches = await store.weatherFetches
        XCTAssertEqual(weatherFetches, 1)
    }

    func testFreshWeatherMissingISSProvenanceCanEnrichForWatchRequest() async {
        let cached = Self.conditions(fetchedAt: Self.now.addingTimeInterval(-60))
        let pass = ISSPass(riseTime: Self.now.addingTimeInterval(600), duration: 120, maxElevation: 45)
        let store = Store(cached)
        let acquirer = WatchConditionsRequestAcquirer(conditionsRepository: Self.repository(
            store: store,
            fetch: { _, _ in
                XCTFail("ISS-only enrichment must not fetch weather")
                throw TestError.failed
            },
            fetchISS: { _, _ in
                await store.recordISSFetch()
                return ISSFetchResult(passes: [pass], state: .succeeded)
            }
        ))

        let result = await acquirer.conditions(for: Self.location, apiKey: "key", referenceDate: Self.now)

        XCTAssertEqual(result?.fetchedAt, cached.fetchedAt)
        XCTAssertEqual(result?.issPasses.map(\.id), [pass.id])
        let issFetches = await store.issFetches
        XCTAssertEqual(issFetches, 1)
    }

    func testISSOnlyFailureStillReturnsFreshWeatherForWatchRequest() async {
        let cached = Self.conditions(fetchedAt: Self.now.addingTimeInterval(-60))
        let store = Store(cached)
        let acquirer = WatchConditionsRequestAcquirer(conditionsRepository: Self.repository(
            store: store,
            fetch: { _, _ in throw TestError.failed },
            fetchISS: { _, _ in ISSFetchResult(passes: [], state: .failed(.timeout)) }
        ))

        let result = await acquirer.conditions(for: Self.location, apiKey: "key", referenceDate: Self.now)

        XCTAssertEqual(result?.fetchedAt, cached.fetchedAt)
    }

    func testRepositoryFailureFallsBackToStaleLastKnownConditions() async {
        let stale = Self.conditions(fetchedAt: Self.now.addingTimeInterval(-7200))
        let store = Store(stale)
        let acquirer = WatchConditionsRequestAcquirer(conditionsRepository: Self.repository(
            store: store,
            fetch: { _, _ in throw TestError.failed }
        ))

        let result = await acquirer.conditions(for: Self.location, apiKey: "", referenceDate: Self.now)

        XCTAssertEqual(result?.fetchedAt, stale.fetchedAt)
    }

    func testNoConditionsProducesNoWatchPayload() async {
        let store = Store()
        let acquirer = WatchConditionsRequestAcquirer(conditionsRepository: Self.repository(
            store: store,
            fetch: { _, _ in throw TestError.failed }
        ))

        let result = await acquirer.conditions(for: Self.location, apiKey: "", referenceDate: Self.now)

        XCTAssertNil(result)
    }

    func testLocationResolverPreservesSavedCurrentAndCachedFallbacks() {
        let saved = CachedLocation(id: UUID(), name: "Saved", latitude: 10, longitude: 20)
        let selectedSaved = SelectedLocation(source: .saved, id: saved.id, name: "Old", latitude: 0, longitude: 0)
        XCTAssertEqual(
            WatchConditionsRequestLocationResolver.resolve(
                selectedLocation: selectedSaved, savedLocations: [saved], cachedConditions: nil
            )?.id,
            saved.id
        )

        let current = SelectedLocation(source: .currentGPS, name: "Current", latitude: 30, longitude: 40)
        let resolvedCurrent = WatchConditionsRequestLocationResolver.resolve(
            selectedLocation: current, savedLocations: [], cachedConditions: nil
        )
        XCTAssertEqual(resolvedCurrent?.latitude, 30)
        XCTAssertNil(resolvedCurrent?.id)

        let cached = Self.conditions(fetchedAt: Self.now)
        XCTAssertEqual(
            WatchConditionsRequestLocationResolver.resolve(
                selectedLocation: nil, savedLocations: [], cachedConditions: cached
            )?.id,
            cached.location.id
        )
    }

    func testWatchPayloadRemainsTonightLimitedAndCodable() throws {
        let conditions = Self.conditions(fetchedAt: Self.now)
        let data = try JSONEncoder().encode(conditions.limitedToTonightCache())
        let decoded = try JSONDecoder().decode(ViewingConditions.self, from: data)

        XCTAssertLessThanOrEqual(decoded.hourlyForecasts.count, conditions.hourlyForecasts.count)
        XCTAssertEqual(decoded.location.id, conditions.location.id)
    }

    private static func repository(
        store: Store,
        fetch: @escaping @Sendable (CachedLocation, String?) async throws -> ConditionsFetchResult,
        fetchISS: @escaping @Sendable (CachedLocation, String) async -> ISSFetchResult = { _, _ in
            ISSFetchResult(passes: [], state: .notRequested)
        }
    ) -> SharedConditionsRepository {
        SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
            now: { Self.now }, fetch: fetch, fetchISS: fetchISS
        )
    }

    private static func conditions(fetchedAt: Date) -> ViewingConditions {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let start = calendar.startOfDay(for: fetchedAt)
        let sun = SunEvents(
            sunrise: start, sunset: start, civilTwilightBegin: start, civilTwilightEnd: start,
            nauticalTwilightBegin: start, nauticalTwilightEnd: start,
            astronomicalTwilightBegin: start, astronomicalTwilightEnd: start
        )
        return ViewingConditions(
            fetchedAt: fetchedAt, location: location,
            hourlyForecasts: [HourlyForecast(
                time: fetchedAt, cloudCover: 10, humidity: 30, windSpeed: 2,
                windDirection: 180, temperature: 10, dewPoint: 2, visibility: 20_000
            )],
            dailySunEvents: Array(repeating: sun, count: SharedConditionsRepository.forecastDays),
            dailyMoonInfo: Array(repeating: MoonInfo(
                phase: 0.5, phaseName: "Full", altitude: 40, illumination: 50, emoji: "🌕"
            ), count: SharedConditionsRepository.forecastDays),
            issPasses: [], fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private static let location = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
    private static let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    private static let now: Date = {
        var calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 12))!
    }()

    private enum TestError: Error { case failed }
}
