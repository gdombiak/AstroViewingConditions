import XCTest
@testable import SharedCode

final class SharedConditionsRepositoryTests: XCTestCase {
    private actor Store {
        var value: ViewingConditions?
        var metadata: SharedConditionsMetadata?
        var saves = 0
        var fetches = 0
        var issFetches = 0

        init(_ value: ViewingConditions? = nil) { self.value = value }
        func load() -> ViewingConditions? { value }
        func save(_ conditions: ViewingConditions) { value = conditions; saves += 1 }
        func loadMetadata() -> SharedConditionsMetadata? { metadata }
        func saveMetadata(_ metadata: SharedConditionsMetadata) { self.metadata = metadata }
        func recordFetch() { fetches += 1 }
        func recordISSFetch() { issFetches += 1 }
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

    func testFreshWeatherWithMatchingISSProvenanceUsesCacheWithoutAnyFetch() async throws {
        let now = Self.referenceDate
        let cached = Self.conditions(location: Self.location, fetchedAt: now.addingTimeInterval(-60))
        let store = Store(cached)
        await store.saveMetadata(Self.metadata(for: cached, issFetchedAt: now.addingTimeInterval(-30)))
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
            now: { now },
            fetch: { _, _ in XCTFail("Fresh weather with fresh ISS must not refetch weather"); throw TestError.failed },
            fetchISS: { _, _ in XCTFail("Fresh ISS provenance must not query ISS"); return ISSFetchResult(passes: [], state: .notRequested) }
        )

        let result = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: now)

        XCTAssertEqual(result.source, .cache)
        XCTAssertNil(result.issError)
        let fetches = await store.fetches
        let issFetches = await store.issFetches
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(issFetches, 0)
    }

    func testFreshWeatherWithoutISSProvenanceEnrichesOnlyISSAndPreservesWeatherTimestamp() async throws {
        let now = Self.referenceDate
        let cached = Self.conditions(location: Self.location, fetchedAt: now.addingTimeInterval(-60))
        let pass = ISSPass(riseTime: now.addingTimeInterval(600), duration: 120, maxElevation: 50)
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
            now: { now },
            fetch: { _, _ in XCTFail("ISS enrichment must not refetch weather"); throw TestError.failed },
            fetchISS: { _, _ in
                await store.recordISSFetch()
                return ISSFetchResult(passes: [pass], state: .succeeded)
            }
        )

        let result = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: now)
        let saved = await store.load()
        let metadata = await store.loadMetadata()

        XCTAssertEqual(result.source, .issEnriched)
        XCTAssertEqual(result.conditions.fetchedAt, cached.fetchedAt)
        XCTAssertEqual(result.conditions.hourlyForecasts.count, cached.hourlyForecasts.count)
        XCTAssertEqual(result.conditions.issPasses.map(\.id), [pass.id])
        XCTAssertEqual(saved?.fetchedAt, cached.fetchedAt)
        XCTAssertEqual(metadata?.weatherFetchedAt, cached.fetchedAt)
        XCTAssertEqual(metadata?.issFetchedAt, now)
        let fetches = await store.fetches
        let issFetches = await store.issFetches
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(issFetches, 1)
    }

    func testSuccessfulEmptyISSResultIsReusableProvenance() async throws {
        let now = Self.referenceDate
        let cached = Self.conditions(location: Self.location, fetchedAt: now.addingTimeInterval(-60))
        let store = Store(cached)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
            now: { now },
            fetch: { _, _ in XCTFail("Fresh weather must not fetch"); throw TestError.failed },
            fetchISS: { _, _ in
                await store.recordISSFetch()
                return ISSFetchResult(passes: [], state: .succeeded)
            }
        )

        let first = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: now)
        let second = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: now)

        XCTAssertEqual(first.source, .issEnriched)
        XCTAssertEqual(second.source, .cache)
        let issFetches = await store.issFetches
        let metadata = await store.loadMetadata()
        XCTAssertEqual(issFetches, 1)
        XCTAssertEqual(metadata?.issFetchedAt, now)
    }

    func testExpiredOrMismatchedISSProvenanceTriggersISSOnlyRefresh() async throws {
        let now = Self.referenceDate
        let cached = Self.conditions(location: Self.location, fetchedAt: now.addingTimeInterval(-60))
        let cases: [SharedConditionsMetadata] = [
            Self.metadata(for: cached, issFetchedAt: now.addingTimeInterval(-SharedConditionsRepository.maximumAge)),
            SharedConditionsMetadata(
                locationID: UUID(), latitude: 1, longitude: 2,
                weatherFetchedAt: cached.fetchedAt, issFetchedAt: now.addingTimeInterval(-30)
            ),
            SharedConditionsMetadata(
                locationID: cached.location.id, latitude: cached.location.latitude, longitude: cached.location.longitude,
                weatherFetchedAt: cached.fetchedAt.addingTimeInterval(-1), issFetchedAt: now.addingTimeInterval(-30)
            )
        ]

        for metadata in cases {
            let store = Store(cached)
            await store.saveMetadata(metadata)
            let service = SharedConditionsRepository(
                load: { await store.load() }, save: { await store.save($0) },
                loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
                now: { now },
                fetch: { _, _ in XCTFail("ISS provenance refresh must not fetch weather"); throw TestError.failed },
                fetchISS: { _, _ in
                    await store.recordISSFetch()
                    return ISSFetchResult(passes: [], state: .succeeded)
                }
            )

            let result = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: now)
            let issFetches = await store.issFetches
            XCTAssertEqual(result.source, .issEnriched)
            XCTAssertEqual(issFetches, 1)
        }
    }

    func testPreviousLocalDayISSProvenanceIsNotReusableEvenWithinOneHour() async throws {
        let calendar = Self.timeZoneCalendar
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26, hour: 0, minute: 30))!
        let cached = Self.conditions(location: Self.location, fetchedAt: reference.addingTimeInterval(-60))
        let previousDayISSFetch = calendar.date(
            byAdding: .minute,
            value: -45,
            to: reference
        )!
        let store = Store(cached)
        await store.saveMetadata(Self.metadata(for: cached, issFetchedAt: previousDayISSFetch))
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
            now: { reference },
            fetch: { _, _ in XCTFail("Local-day provenance refresh must not fetch weather"); throw TestError.failed },
            fetchISS: { _, _ in
                await store.recordISSFetch()
                return ISSFetchResult(passes: [], state: .succeeded)
            }
        )

        let result = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: reference)
        let issFetches = await store.issFetches

        XCTAssertEqual(result.source, .issEnriched)
        XCTAssertEqual(issFetches, 1)
    }

    func testISSOnlyFailureKeepsFreshWeatherAndSuccessfulMetadataUntouched() async throws {
        let now = Self.referenceDate
        let cached = Self.conditions(location: Self.location, fetchedAt: now.addingTimeInterval(-60))
        let staleMetadata = Self.metadata(for: cached, issFetchedAt: now.addingTimeInterval(-SharedConditionsRepository.maximumAge))
        let store = Store(cached)
        await store.saveMetadata(staleMetadata)
        let error = ISSError.timeout
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
            now: { now },
            fetch: { _, _ in XCTFail("ISS-only failure must not fetch weather"); throw TestError.failed },
            fetchISS: { _, _ in
                await store.recordISSFetch()
                return ISSFetchResult(passes: [], state: .failed(error))
            }
        )

        let result = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: now)

        XCTAssertEqual(result.source, .cache)
        XCTAssertEqual(result.conditions.fetchedAt, cached.fetchedAt)
        XCTAssertEqual(result.issError, error)
        let saves = await store.saves
        let metadata = await store.loadMetadata()
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(metadata, staleMetadata)
    }

    func testStaleWeatherWithSuccessfulISSFetchRecordsProvenance() async throws {
        let now = Self.referenceDate
        let stale = Self.conditions(location: Self.location, fetchedAt: now.addingTimeInterval(-3601))
        let refreshed = Self.conditions(location: Self.location, fetchedAt: now)
        let store = Store(stale)
        let service = SharedConditionsRepository(
            load: { await store.load() }, save: { await store.save($0) },
            loadMetadata: { await store.loadMetadata() }, saveMetadata: { await store.saveMetadata($0) },
            now: { now },
            fetch: { _, _ in ConditionsFetchResult(conditions: refreshed, issError: nil, issFetchState: .succeeded) }
        )

        let result = try await service.conditions(for: Self.location, apiKey: "key", referenceDate: now)

        XCTAssertEqual(result.source, .fetched)
        let metadata = await store.loadMetadata()
        XCTAssertEqual(metadata, Self.metadata(for: refreshed, issFetchedAt: now))
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

    private static func metadata(
        for conditions: ViewingConditions,
        issFetchedAt: Date?
    ) -> SharedConditionsMetadata {
        SharedConditionsMetadata(
            locationID: conditions.location.id,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            weatherFetchedAt: conditions.fetchedAt,
            issFetchedAt: issFetchedAt
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
