import XCTest
@testable import SharedCode

final class SharedConditionsRepositoryTests: XCTestCase {
    private actor Store {
        var value: ViewingConditions?
        var saves = 0
        var fetches = 0

        init(_ value: ViewingConditions? = nil) { self.value = value }
        func load() -> ViewingConditions? { value }
        func save(_ conditions: ViewingConditions) { value = conditions; saves += 1 }
        func recordFetch() { fetches += 1 }
    }

    func testFreshMatchingConditionsAreReusedWithoutFetch() async throws {
        let now = Self.referenceDate
        let location = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let store = Store(Self.conditions(location: location, fetchedAt: now))
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            fetch: { _ in XCTFail("Fresh shared conditions must not fetch"); throw TestError.failed }
        )

        let result = try await service.conditions(for: location, referenceDate: now)
        XCTAssertEqual(result.conditions.fetchedAt, now)
        XCTAssertEqual(result.source, .cache)
        let saves = await store.saves
        XCTAssertEqual(saves, 0)
    }

    func testFreshMatchingIncompleteCacheFetchesAndSavesCompleteReplacement() async throws {
        let now = Self.referenceDate
        let location = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let incomplete = ViewingConditions(
            fetchedAt: now, location: location, hourlyForecasts: [], dailySunEvents: [],
            dailyMoonInfo: [], issPasses: [], fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: Self.timeZone.identifier
        )
        let complete = Self.conditions(location: location, fetchedAt: now)
        let store = Store(incomplete)
        let service = SharedConditionsRepository(
            load: { await store.load() },
            save: { await store.save($0) },
            now: { now },
            fetch: { _ in
                await store.recordFetch()
                return complete
            }
        )

        let result = try await service.conditions(for: location, referenceDate: now)
        let saved = await store.load()
        let fetches = await store.fetches
        let saves = await store.saves
        XCTAssertEqual(result.conditions.hourlyForecasts.count, Self.forecastDays)
        XCTAssertEqual(saved?.hourlyForecasts.count, Self.forecastDays)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(saves, 1)
    }

    func testValidConditionsAreCachedWithoutEveryWidgetPresentationInput() async throws {
        let now = Self.referenceDate
        let location = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let complete = Self.conditions(location: location, fetchedAt: now)
        let minimallyValid = ViewingConditions(
            fetchedAt: complete.fetchedAt,
            location: complete.location,
            hourlyForecasts: Array(complete.hourlyForecasts.prefix(1)),
            dailySunEvents: complete.dailySunEvents,
            dailyMoonInfo: complete.dailyMoonInfo,
            issPasses: [],
            fogScore: complete.fogScore,
            timeZoneIdentifier: complete.timeZoneIdentifier
        )
        let store = Store()
        let service = SharedConditionsRepository(
            load: { await store.load() },
            save: { await store.save($0) },
            now: { now },
            fetch: { _ in minimallyValid }
        )

        let result = try await service.conditions(for: location, referenceDate: now)
        let saved = await store.load()

        XCTAssertEqual(result.source, .fetched)
        XCTAssertEqual(result.conditions.hourlyForecasts.count, 1)
        XCTAssertEqual(saved?.hourlyForecasts.count, 1)
    }

    func testNoKeyRefreshPreservesSameDayFutureCachedISSPasses() async throws {
        let now = Self.referenceDate
        let location = Self.location
        let futurePass = ISSPass(
            riseTime: now.addingTimeInterval(900), duration: 300, maxElevation: 45
        )
        let cached = Self.conditions(
            location: location,
            fetchedAt: now.addingTimeInterval(-300),
            issPasses: [futurePass]
        )
        let fetched = Self.conditions(location: location, fetchedAt: now)
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) }, now: { now },
            fetch: { _, _ in ConditionsFetchResult(conditions: fetched, issError: nil) }
        )

        let result = try await service.conditions(
            for: location, referenceDate: now, forceRefresh: true
        )

        XCTAssertEqual(result.conditions.issPasses.map(\.id), [futurePass.id])
    }

    func testNoKeyRefreshRemovesExpiredCachedISSPasses() async throws {
        let now = Self.referenceDate
        let location = Self.location
        let expiredPass = ISSPass(
            riseTime: now.addingTimeInterval(-900), duration: 60, maxElevation: 45,
            maxTime: now.addingTimeInterval(-870), endTime: now.addingTimeInterval(-840)
        )
        let cached = Self.conditions(
            location: location,
            fetchedAt: now.addingTimeInterval(-300),
            issPasses: [expiredPass]
        )
        let fetched = Self.conditions(location: location, fetchedAt: now)
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) }, now: { now },
            fetch: { _, _ in ConditionsFetchResult(conditions: fetched, issError: nil) }
        )

        let result = try await service.conditions(
            for: location, referenceDate: now, forceRefresh: true
        )

        XCTAssertTrue(result.conditions.issPasses.isEmpty)
    }

    func testNoKeyRefreshDoesNotPreservePreviousLocalDayISSPasses() async throws {
        let now = Self.referenceDate
        let location = Self.location
        let previousDay = Self.timeZoneCalendar.date(byAdding: .day, value: -1, to: now)!
        let cached = Self.conditions(
            location: location,
            fetchedAt: previousDay,
            issPasses: [ISSPass(
                riseTime: now.addingTimeInterval(900), duration: 300, maxElevation: 45
            )]
        )
        let fetched = Self.conditions(location: location, fetchedAt: now)
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) }, now: { now },
            fetch: { _, _ in ConditionsFetchResult(conditions: fetched, issError: nil) }
        )

        let result = try await service.conditions(
            for: location, referenceDate: now, forceRefresh: true
        )

        XCTAssertTrue(result.conditions.issPasses.isEmpty)
    }

    func testNoKeyRefreshDoesNotPreserveMismatchedLocationISSPasses() async throws {
        let now = Self.referenceDate
        let location = Self.location
        let otherLocation = CachedLocation(id: UUID(), name: "Elsewhere", latitude: 10, longitude: 20)
        let cached = Self.conditions(
            location: otherLocation,
            fetchedAt: now.addingTimeInterval(-300),
            issPasses: [ISSPass(
                riseTime: now.addingTimeInterval(900), duration: 300, maxElevation: 45
            )]
        )
        let fetched = Self.conditions(location: location, fetchedAt: now)
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) }, now: { now },
            fetch: { _, _ in ConditionsFetchResult(conditions: fetched, issError: nil) }
        )

        let result = try await service.conditions(
            for: location, referenceDate: now, forceRefresh: true
        )

        XCTAssertTrue(result.conditions.issPasses.isEmpty)
    }

    func testAPIKeyRefreshUsesFetchedISSPassesAndDiagnosticsUnchanged() async throws {
        let now = Self.referenceDate
        let location = Self.location
        let cached = Self.conditions(
            location: location,
            fetchedAt: now.addingTimeInterval(-300),
            issPasses: [ISSPass(
                riseTime: now.addingTimeInterval(900), duration: 300, maxElevation: 45
            )]
        )
        let fetchedPass = ISSPass(
            riseTime: now.addingTimeInterval(1_800), duration: 300, maxElevation: 60
        )
        let fetched = Self.conditions(location: location, fetchedAt: now, issPasses: [fetchedPass])
        let diagnostic = ISSError.apiError(statusCode: 429, message: "Rate limited")
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) }, now: { now },
            fetch: { _, _ in ConditionsFetchResult(conditions: fetched, issError: diagnostic) }
        )

        let result = try await service.conditions(
            for: location, apiKey: "key", referenceDate: now, forceRefresh: true
        )

        XCTAssertEqual(result.conditions.issPasses.map(\.id), [fetchedPass.id])
        XCTAssertEqual(result.issError, diagnostic)
    }

    func testExactlyExpiredConditionsFetchOnceAndReplaceSharedCache() async throws {
        let now = Self.referenceDate
        let selected = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let stale = Self.conditions(
            location: selected,
            fetchedAt: now.addingTimeInterval(-SharedConditionsRepository.maximumAge)
        )
        let refreshed = Self.conditions(location: selected, fetchedAt: now)
        let store = Store(stale)
        let service = SharedConditionsRepository(
            load: { await store.load() },
            save: { await store.save($0) },
            now: { now },
            fetch: { _ in
                await store.recordFetch()
                return refreshed
            }
        )

        let result = try await service.conditions(for: selected, referenceDate: now)
        let saved = await store.load()
        let fetches = await store.fetches
        let saves = await store.saves
        XCTAssertEqual(result.conditions.fetchedAt, now)
        XCTAssertEqual(saved?.fetchedAt, now)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(saves, 1)

        let secondProvider = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            fetch: { _ in XCTFail("A second widget should reuse the shared refresh"); throw TestError.failed }
        )
        _ = try await secondProvider.conditions(for: selected, referenceDate: now)
        let secondSaves = await store.saves
        XCTAssertEqual(secondSaves, 1)
    }

    func testWrongLocationConditionsFetchAndReplaceSharedCache() async throws {
        let now = Self.referenceDate
        let selected = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let different = CachedLocation(id: UUID(), name: "Elsewhere", latitude: 45.500001, longitude: -122.7)
        let mismatched = Store(Self.conditions(location: selected, fetchedAt: now))
        let mismatchService = SharedConditionsRepository(
            load: { await mismatched.load() }, save: { await mismatched.save($0) },
            fetch: { location in Self.conditions(location: location, fetchedAt: now) }
        )
        _ = try await mismatchService.conditions(for: different, referenceDate: now)
        let mismatchSaves = await mismatched.saves
        XCTAssertEqual(mismatchSaves, 1)
    }

    func testFutureDatedConditionsAreRejectedAndReplaced() async throws {
        let now = Self.referenceDate
        let location = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let future = Self.conditions(location: location, fetchedAt: now.addingTimeInterval(1))
        let refreshed = Self.conditions(location: location, fetchedAt: now)
        let store = Store(future)
        let service = SharedConditionsRepository(
            load: { await store.load() },
            save: { await store.save($0) },
            now: { now },
            fetch: { _ in
                await store.recordFetch()
                return refreshed
            }
        )

        let result = try await service.conditions(for: location, referenceDate: now)
        let saved = await store.load()
        let fetches = await store.fetches
        let saves = await store.saves
        XCTAssertEqual(result.conditions.fetchedAt, now)
        XCTAssertEqual(saved?.fetchedAt, now)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(saves, 1)
    }

    func testFailedFetchPreservesMatchingStaleConditionsForFallback() async {
        let now = Self.referenceDate
        let location = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let stale = Self.conditions(location: location, fetchedAt: now.addingTimeInterval(-3601))
        let store = Store(stale)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            fetch: { _ in throw TestError.failed }
        )

        do {
            _ = try await service.conditions(for: location, referenceDate: now)
            XCTFail("Expected the failed refresh to surface")
        } catch {}
        let preserved = await store.load()
        let saves = await store.saves
        let fallback = await service.matchingCachedConditions(for: location)
        XCTAssertEqual(preserved?.fetchedAt, stale.fetchedAt)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(fallback?.fetchedAt, stale.fetchedAt)
    }

    func testIncompleteFetchedPayloadIsRejectedWithoutReplacingFreshIncompleteCache() async {
        let now = Self.referenceDate
        let location = CachedLocation(id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7)
        let cached = ViewingConditions(
            fetchedAt: now, location: location, hourlyForecasts: [], dailySunEvents: [],
            dailyMoonInfo: [], issPasses: [], fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: Self.timeZone.identifier
        )
        let fetched = ViewingConditions(
            fetchedAt: now.addingTimeInterval(-1), location: location, hourlyForecasts: [],
            dailySunEvents: [], dailyMoonInfo: [], issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: Self.timeZone.identifier
        )
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() },
            save: { await store.save($0) },
            fetch: { _ in
                await store.recordFetch()
                return fetched
            }
        )

        do {
            _ = try await service.conditions(for: location, referenceDate: now)
            XCTFail("Expected incomplete fetched conditions to be rejected")
        } catch let error as SharedConditionsRepository.RefreshError {
            guard case .invalidFetchedConditions = error else {
                return XCTFail("Unexpected refresh validation error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let preserved = await store.load()
        let fetches = await store.fetches
        let saves = await store.saves
        XCTAssertEqual(preserved?.fetchedAt, cached.fetchedAt)
        XCTAssertEqual(preserved?.hourlyForecasts.count, 0)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(saves, 0)
    }

    private static func conditions(
        location: CachedLocation,
        fetchedAt: Date,
        issPasses: [ISSPass] = []
    ) -> ViewingConditions {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let start = calendar.startOfDay(for: fetchedAt)
        let hourlyForecasts = (0..<forecastDays).compactMap { dayOffset -> HourlyForecast? in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start),
                  let time = calendar.date(byAdding: .hour, value: 22, to: day) else { return nil }
            return HourlyForecast(
                time: time, cloudCover: 25, humidity: 50, windSpeed: 3,
                windDirection: 180, temperature: 12, dewPoint: 6, visibility: 20_000
            )
        }
        let dailySunEvents = (0..<forecastDays).compactMap { dayOffset -> SunEvents? in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start),
                  let sunrise = calendar.date(byAdding: .hour, value: 6, to: day),
                  let sunset = calendar.date(byAdding: .hour, value: 18, to: day),
                  let civilBegin = calendar.date(byAdding: .hour, value: 5, to: day),
                  let civilEnd = calendar.date(byAdding: .hour, value: 19, to: day),
                  let nauticalBegin = calendar.date(byAdding: .hour, value: 4, to: day),
                  let nauticalEnd = calendar.date(byAdding: .hour, value: 20, to: day),
                  let astronomicalBegin = calendar.date(byAdding: .hour, value: 3, to: day),
                  let astronomicalEnd = calendar.date(byAdding: .hour, value: 21, to: day) else { return nil }
            return SunEvents(
                sunrise: sunrise, sunset: sunset, civilTwilightBegin: civilBegin,
                civilTwilightEnd: civilEnd, nauticalTwilightBegin: nauticalBegin,
                nauticalTwilightEnd: nauticalEnd, astronomicalTwilightBegin: astronomicalBegin,
                astronomicalTwilightEnd: astronomicalEnd
            )
        }
        return ViewingConditions(
            fetchedAt: fetchedAt, location: location, hourlyForecasts: hourlyForecasts,
            dailySunEvents: dailySunEvents,
            dailyMoonInfo: Array(repeating: MoonInfo(
                phase: 0.5, phaseName: "Full", altitude: 45, illumination: 50, emoji: "🌕"
            ), count: forecastDays),
            issPasses: issPasses, fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private static let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    private static var timeZoneCalendar: Calendar {
        LocationTimeZoneResolver.calendar(for: timeZone)
    }
    private static let location = CachedLocation(
        id: UUID(), name: "Home", latitude: 45.5, longitude: -122.7
    )
    private static let forecastDays = SharedConditionsRepository.forecastDays
    private static let referenceDate: Date = {
        var calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 12))!
    }()

    private enum TestError: Error { case failed }
}
