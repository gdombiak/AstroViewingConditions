import Foundation
import XCTest
@testable import SharedCode

// MARK: - Fixtures

private enum BrightnessCacheFixtures {
    static let latitude = 45.45
    static let longitude = -122.75
    static let timeZoneID = "America/Los_Angeles"

    static func dataset(revision: Int = 1) -> LightPollutionDatasetIdentity {
        LightPollutionDatasetIdentity(
            datasetID: "lpatlas1",
            datasetRevision: revision,
            formatVersion: 1
        )
    }

    static func sample(
        id: UUID?,
        lat: Double = latitude,
        lon: Double = longitude,
        brightness: Double = 18.5,
        revision: Int = 1,
        sampledAt: Date = Date()
    ) -> ModeledZenithBrightnessSample {
        ModeledZenithBrightnessSample(
            latitude: lat,
            longitude: lon,
            modeledZenithSkyBrightness: brightness,
            dataset: dataset(revision: revision),
            sampledAt: sampledAt,
            savedLocationID: id
        )
    }

    static func selectedSaved(
        id: UUID,
        lat: Double = latitude,
        lon: Double = longitude
    ) -> SelectedLocation {
        SelectedLocation(
            source: .saved,
            id: id,
            name: "Home",
            latitude: lat,
            longitude: lon
        )
    }

    static func selectedCurrent(
        lat: Double = latitude,
        lon: Double = longitude
    ) -> SelectedLocation {
        SelectedLocation(
            source: .currentGPS,
            id: nil,
            name: "Current Location",
            latitude: lat,
            longitude: lon
        )
    }

    static func analyzableConditions(
        locationID: UUID?,
        lat: Double = latitude,
        lon: Double = longitude,
        referenceDate: Date = Date(),
        cloudCover: Int = 10
    ) -> ViewingConditions {
        Phase4BFixtures.analyzableConditions(
            locationID: locationID,
            lat: lat,
            lon: lon,
            referenceDate: referenceDate,
            cloudCover: cloudCover
        )
    }

    static func nightScore(for conditions: ViewingConditions) -> Int {
        NightQualityAnalyzer.analyzeConditions(conditions)!.calculatedScore
    }

    /// Prefer clear skies; returns (conditions, nightScore).
    static func clearNightConditions(locationID: UUID?) -> (ViewingConditions, Int) {
        let conditions = analyzableConditions(locationID: locationID, cloudCover: 0)
        return (conditions, nightScore(for: conditions))
    }

    static func cloudyNightConditions(locationID: UUID?) -> (ViewingConditions, Int) {
        let conditions = analyzableConditions(locationID: locationID, cloudCover: 70)
        return (conditions, nightScore(for: conditions))
    }

    static func expectedOQ(night: Int, brightness: Double = 18.5) -> Int {
        ObservingQualityCalculator.assess(
            nightConditionsScore: night,
            modeledZenithSkyBrightness: brightness
        ).score
    }
}

// MARK: - Cache product rules

final class WatchModeledBrightnessCacheTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchBrightness-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    func testUpsertAndLookupSavedLocation() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        let id = UUID()
        let sample = BrightnessCacheFixtures.sample(id: id, sampledAt: Date().addingTimeInterval(-60))
        cache.upsert(sample)

        let found = cache.sample(
            forSavedLocationID: id,
            latitude: BrightnessCacheFixtures.latitude,
            longitude: BrightnessCacheFixtures.longitude
        )
        XCTAssertEqual(found?.modeledZenithSkyBrightness, 18.5)
        XCTAssertEqual(found?.savedLocationID, id)
    }

    func testWrongSavedLocationIDRejected() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        let id = UUID()
        cache.upsert(BrightnessCacheFixtures.sample(id: id))
        XCTAssertNil(
            cache.sample(
                forSavedLocationID: UUID(),
                latitude: BrightnessCacheFixtures.latitude,
                longitude: BrightnessCacheFixtures.longitude
            )
        )
    }

    func testMovedSavedLocationCoordinatesRejectSample() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        let id = UUID()
        cache.upsert(BrightnessCacheFixtures.sample(id: id))
        // ~0.02° latitude ≈ 2+ km — beyond 1000 m validity.
        let movedLat = BrightnessCacheFixtures.latitude + 0.02
        XCTAssertNil(
            cache.sample(
                forSavedLocationID: id,
                latitude: movedLat,
                longitude: BrightnessCacheFixtures.longitude
            )
        )
    }

    func testIncompatibleDatasetRevisionRejected() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        let id = UUID()
        // Store old revision; product current is revision 1.
        cache.upsert(BrightnessCacheFixtures.sample(id: id, revision: 99))
        XCTAssertNil(
            cache.sample(
                forSavedLocationID: id,
                latitude: BrightnessCacheFixtures.latitude,
                longitude: BrightnessCacheFixtures.longitude
            ),
            "stale datasetRevision must not be usable"
        )
        // Physical retention for replacement is fine.
        let doc = cache.documentSnapshotForTesting()
        XCTAssertNotNil(doc.samplesBySavedLocationID[id.uuidString])
    }

    func testCurrentDatasetSampleReplacesStale() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        let id = UUID()
        cache.upsert(BrightnessCacheFixtures.sample(id: id, brightness: 16.0, revision: 99))
        cache.upsert(BrightnessCacheFixtures.sample(id: id, brightness: 18.5, revision: 1))
        let found = cache.sample(
            forSavedLocationID: id,
            latitude: BrightnessCacheFixtures.latitude,
            longitude: BrightnessCacheFixtures.longitude
        )
        XCTAssertEqual(found?.modeledZenithSkyBrightness, 18.5)
        XCTAssertEqual(found?.dataset.datasetRevision, 1)
    }

    func testNightOnlyDoesNotClearIndependentBrightnessCache() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        let id = UUID()
        cache.upsert(BrightnessCacheFixtures.sample(id: id))
        // Simulate night-only path: no upsert/clear of brightness cache.
        XCTAssertNotNil(
            cache.sample(
                forSavedLocationID: id,
                latitude: BrightnessCacheFixtures.latitude,
                longitude: BrightnessCacheFixtures.longitude
            )
        )
    }

    func testCurrentLocationNearbyReusesSample() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        let sample = BrightnessCacheFixtures.sample(id: nil, brightness: 18.5)
        cache.upsert(sample)
        // ~50 m offset
        let nearLat = BrightnessCacheFixtures.latitude + 0.0004
        let found = cache.sample(
            forCurrentLocationLatitude: nearLat,
            longitude: BrightnessCacheFixtures.longitude
        )
        XCTAssertEqual(found?.modeledZenithSkyBrightness, 18.5)
    }

    func testCurrentLocationFarRejectsSample() {
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: tempDir)
        cache.upsert(BrightnessCacheFixtures.sample(id: nil))
        let farLat = BrightnessCacheFixtures.latitude + 0.02
        XCTAssertNil(
            cache.sample(
                forCurrentLocationLatitude: farLat,
                longitude: BrightnessCacheFixtures.longitude
            )
        )
    }
}

// MARK: - Local refresh OQ via cached brightness

final class WatchLocalBrightnessOQRefreshTests: XCTestCase {
    /// Regression: local weather + cached home LP must stay OQ-backed (not demote to night-only).
    /// Home LP at 18.5 mag/arcsec² applies a 7-point base penalty on clear nights (e.g. 98→91).
    func testSavedLocationLocalWeatherWithCachedBrightnessYieldsOQNotNightOnly() {
        let id = UUID()
        let (conditions, night) = BrightnessCacheFixtures.clearNightConditions(locationID: id)
        let expectedOQ = BrightnessCacheFixtures.expectedOQ(night: night)
        XCTAssertNotEqual(expectedOQ, night, "fixture requires nonzero LP penalty")

        let sample = BrightnessCacheFixtures.sample(
            id: id,
            brightness: 18.5,
            sampledAt: conditions.fetchedAt
        )
        let selected = BrightnessCacheFixtures.selectedSaved(id: id)

        let outcome = WatchObservingQualityCanonicalizer.resolveFromCachedBrightness(
            conditions: conditions,
            selectedLocation: selected,
            sample: sample,
            nightConditionsScore: night
        )
        guard case let .enhanced(snapshot, _) = outcome else {
            return XCTFail("expected enhanced OQ, got \(outcome)")
        }
        XCTAssertEqual(snapshot.nightConditionsScore, night)
        XCTAssertEqual(snapshot.observingQualityScore, expectedOQ)
        XCTAssertEqual(snapshot.brightnessAvailability, .available)

        let document = WatchObservingQualityCanonicalizer.document(
            from: outcome,
            conditions: conditions
        )
        XCTAssertNotNil(document)

        let headline = WatchComplicationHeadlineResolver.resolve(
            conditions: conditions,
            document: document,
            selectedLocation: selected,
            nightScore: night
        )
        XCTAssertEqual(headline.presentationMode, .observingQuality)
        XCTAssertEqual(headline.score, expectedOQ)
        XCTAssertNotEqual(headline.score, night)
    }

    func testLocalWeatherNightChangeRecomputesOQFromNewNightScore() {
        let id = UUID()
        let (clear, nightA) = BrightnessCacheFixtures.clearNightConditions(locationID: id)
        let (cloudy, nightB) = BrightnessCacheFixtures.cloudyNightConditions(locationID: id)
        XCTAssertNotEqual(nightA, nightB, "fixture requires distinct night scores")

        let sample = BrightnessCacheFixtures.sample(
            id: id,
            brightness: 18.5,
            sampledAt: clear.fetchedAt
        )
        let selected = BrightnessCacheFixtures.selectedSaved(id: id)

        let outcomeA = WatchObservingQualityCanonicalizer.resolveFromCachedBrightness(
            conditions: clear,
            selectedLocation: selected,
            sample: sample,
            nightConditionsScore: nightA
        )
        let outcomeB = WatchObservingQualityCanonicalizer.resolveFromCachedBrightness(
            conditions: cloudy,
            selectedLocation: selected,
            sample: sample,
            nightConditionsScore: nightB
        )
        guard case let .enhanced(snapA, _) = outcomeA,
              case let .enhanced(snapB, _) = outcomeB else {
            return XCTFail("both must enhance")
        }
        XCTAssertEqual(snapA.nightConditionsScore, nightA)
        XCTAssertEqual(snapB.nightConditionsScore, nightB)
        XCTAssertNotEqual(
            snapA.observingQualityScore,
            snapB.observingQualityScore,
            "OQ must recompute from new night score, not retain old OQ number"
        )
        XCTAssertEqual(
            snapB.observingQualityScore,
            BrightnessCacheFixtures.expectedOQ(night: nightB)
        )
    }

    func testStaleDatasetLocalSampleYieldsNightOnly() {
        let id = UUID()
        let (conditions, night) = BrightnessCacheFixtures.clearNightConditions(locationID: id)
        let stale = BrightnessCacheFixtures.sample(
            id: id,
            brightness: 18.5,
            revision: 99,
            sampledAt: conditions.fetchedAt
        )
        let outcome = WatchObservingQualityCanonicalizer.resolveFromCachedBrightness(
            conditions: conditions,
            selectedLocation: BrightnessCacheFixtures.selectedSaved(id: id),
            sample: stale,
            nightConditionsScore: night
        )
        guard case let .nightOnly(score, _) = outcome else {
            return XCTFail("stale dataset must be night-only, got \(outcome)")
        }
        XCTAssertEqual(score, night)
        XCTAssertNil(
            WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditions)
        )
    }

    func testCoordinatorLocalBrightnessAcceptPersistsEnhancedPair() async {
        let id = UUID()
        let (conditions, night) = BrightnessCacheFixtures.clearNightConditions(locationID: id)
        let expectedOQ = BrightnessCacheFixtures.expectedOQ(night: night)
        let sample = BrightnessCacheFixtures.sample(
            id: id,
            brightness: 18.5,
            sampledAt: conditions.fetchedAt
        )
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let token = await coordinator.beginLiveUpdate()
        let result = await coordinator.accept(
            conditions: conditions,
            transported: nil,
            selectedLocation: BrightnessCacheFixtures.selectedSaved(id: id),
            locationTimeZone: TimeZone(identifier: BrightnessCacheFixtures.timeZoneID),
            reloadComplications: true,
            token: token,
            localBrightnessSample: sample
        )
        guard case let .applied(state) = result else {
            return XCTFail("must apply, got \(result)")
        }
        XCTAssertEqual(state.observingQualityHeadline?.scorePresentationMode, .observingQuality)
        XCTAssertEqual(state.observingQualityHeadline?.observingQualityScore, expectedOQ)
        XCTAssertEqual(state.observingQualityHeadline?.nightConditionsScore, night)
        XCTAssertNotNil(store.observingQuality)
        XCTAssertEqual(store.observingQuality?.snapshot.observingQualityScore, expectedOQ)
        XCTAssertEqual(reloader.count, 1)
    }

    func testPhoneOQSampleUpsertsViaProductionSyncSeam() throws {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        // Production manager seam after enhanced accept.
        let sample = WatchModeledBrightnessPhoneSync.sampleToUpsert(
            transported: payload,
            scorePresentationMode: .observingQuality
        )
        XCTAssertNotNil(sample)
        XCTAssertNil(
            WatchModeledBrightnessPhoneSync.sampleToUpsert(
                transported: payload,
                scorePresentationMode: .nightConditionsFallback
            ),
            "night-only accept must not upsert brightness"
        )
        XCTAssertNil(
            WatchModeledBrightnessPhoneSync.sampleToUpsert(
                transported: nil,
                scorePresentationMode: .observingQuality
            )
        )

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("upsert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let raw = try XCTUnwrap(sample)
        let durable = ModeledZenithBrightnessSample(
            latitude: raw.latitude,
            longitude: raw.longitude,
            modeledZenithSkyBrightness: raw.modeledZenithSkyBrightness,
            dataset: raw.dataset,
            sampledAt: conditions.fetchedAt,
            savedLocationID: raw.savedLocationID
        )
        let cache = AppGroupWatchModeledBrightnessCache(baseURL: temp)
        cache.upsert(durable)
        let found = cache.sample(
            forSavedLocationID: id,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude
        )
        XCTAssertEqual(found?.modeledZenithSkyBrightness, durable.modeledZenithSkyBrightness)
    }

    func testSavedLocationLocalCoordinateSelectionUsesPinNotWatchGPS() {
        let selected = BrightnessCacheFixtures.selectedSaved(
            id: UUID(),
            lat: 45.0,
            lon: -122.0
        )
        let gps = (latitude: 47.6, longitude: -122.3)
        let weather = WatchLocalWeatherCoordinateSelection.coordinate(
            selectedLocation: selected,
            currentLocationRequest: nil,
            watchGPS: gps
        )
        XCTAssertEqual(weather?.latitude, 45.0)
        XCTAssertEqual(weather?.longitude, -122.0)

        let cl = BrightnessCacheFixtures.selectedCurrent(lat: 0, lon: 0)
        let clWeather = WatchLocalWeatherCoordinateSelection.coordinate(
            selectedLocation: cl,
            currentLocationRequest: nil,
            watchGPS: gps
        )
        XCTAssertEqual(clWeather?.latitude, gps.latitude)
        XCTAssertEqual(clWeather?.longitude, gps.longitude)
    }

    /// Local accept after midnight must score the active astronomical night (not calendar day).
    func testLocalBrightnessAcceptAfterMidnightKeepsActiveNightOQ() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: BrightnessCacheFixtures.timeZoneID)!

        let evening = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 1, hour: 21
        ))!
        let afterMidnight = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 6, day: 2, hour: 1
        ))!

        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: evening,
            cloudCover: 0
        )
        let selected = BrightnessCacheFixtures.selectedSaved(id: id)
        let tz = TimeZone(identifier: BrightnessCacheFixtures.timeZoneID)

        // Active night at evening and after midnight must be the same observing identity.
        guard case let .resolved(eveningResolution) = ActiveObservingNightResolver.resolve(
            conditions: conditions,
            referenceDate: evening,
            timeZone: tz
        ),
        case let .resolved(midnightResolution) = ActiveObservingNightResolver.resolve(
            conditions: conditions,
            referenceDate: afterMidnight,
            timeZone: tz
        ) else {
            return XCTFail("ActiveObservingNight must resolve both evening and post-midnight")
        }
        XCTAssertTrue(
            calendar.isDate(
                eveningResolution.observingDate,
                inSameDayAs: midnightResolution.observingDate
            ),
            "same astronomical night across midnight"
        )
        XCTAssertFalse(
            calendar.isDate(midnightResolution.observingDate, inSameDayAs: afterMidnight),
            "active observing date is the evening's local day, not post-midnight calendar day"
        )
        let activeScore = eveningResolution.context.nightQuality.calculatedScore
        XCTAssertEqual(
            midnightResolution.context.nightQuality.calculatedScore,
            activeScore
        )
        XCTAssertEqual(
            WatchActiveObservingNightScoring.nightScore(
                conditions: conditions,
                referenceDate: afterMidnight,
                timeZone: tz
            ),
            activeScore
        )

        let expectedOQ = BrightnessCacheFixtures.expectedOQ(night: activeScore)
        XCTAssertNotEqual(expectedOQ, activeScore, "LP penalty must reduce score")

        let sample = BrightnessCacheFixtures.sample(
            id: id,
            brightness: 18.5,
            sampledAt: conditions.fetchedAt
        )

        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let token = await coordinator.beginLiveUpdate()
        let result = await coordinator.accept(
            conditions: conditions,
            transported: nil,
            selectedLocation: selected,
            locationTimeZone: tz,
            reloadComplications: true,
            token: token,
            localBrightnessSample: sample,
            referenceDate: afterMidnight
        )
        guard case let .applied(state) = result else {
            return XCTFail("must apply, got \(result)")
        }

        XCTAssertEqual(state.nightQuality?.calculatedScore, activeScore)
        XCTAssertEqual(state.observingQualityHeadline?.nightConditionsScore, activeScore)
        XCTAssertEqual(state.observingQualityHeadline?.observingQualityScore, expectedOQ)
        XCTAssertEqual(
            state.observingQualityHeadline?.scorePresentationMode,
            .observingQuality
        )
        XCTAssertEqual(store.observingQuality?.associatedNightConditionsScore, activeScore)
        XCTAssertEqual(store.observingQuality?.snapshot.nightConditionsScore, activeScore)
        XCTAssertEqual(store.observingQuality?.snapshot.observingQualityScore, expectedOQ)

        // Complication path at post-midnight reference must stay OQ-backed.
        let headline = WatchComplicationHeadlineResolver.resolve(
            conditions: conditions,
            document: store.observingQuality,
            selectedLocation: selected,
            nightScore: activeScore
        )
        XCTAssertEqual(headline.presentationMode, .observingQuality)
        XCTAssertEqual(headline.score, expectedOQ)
        XCTAssertNotEqual(headline.score, activeScore)
    }

    func testCurrentLocationCachedBrightnessEnhances() throws {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: nil)
        // Conditions need CL-style nil id and matching coords.
        let lat = conditions.location.latitude
        let lon = conditions.location.longitude
        let selected = BrightnessCacheFixtures.selectedCurrent(lat: lat, lon: lon)
        let night = BrightnessCacheFixtures.nightScore(for: conditions)
        let sample = BrightnessCacheFixtures.sample(
            id: nil,
            lat: lat,
            lon: lon,
            brightness: 18.5,
            sampledAt: conditions.fetchedAt
        )
        let outcome = WatchObservingQualityCanonicalizer.resolveFromCachedBrightness(
            conditions: conditions,
            selectedLocation: selected,
            sample: sample,
            nightConditionsScore: night
        )
        guard case let .enhanced(snapshot, _) = outcome else {
            return XCTFail("CL nearby cache must enhance, got \(outcome)")
        }
        XCTAssertEqual(snapshot.brightnessAvailability, .available)
        let expected = ObservingQualityCalculator.assess(
            nightConditionsScore: night,
            modeledZenithSkyBrightness: 18.5
        ).score
        XCTAssertEqual(snapshot.observingQualityScore, expected)
    }

    func testCurrentLocationFarCachedBrightnessIsNightOnly() {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: nil)
        let lat = conditions.location.latitude
        let lon = conditions.location.longitude
        let selected = BrightnessCacheFixtures.selectedCurrent(lat: lat, lon: lon)
        let night = BrightnessCacheFixtures.nightScore(for: conditions)
        let farSample = BrightnessCacheFixtures.sample(
            id: nil,
            lat: lat + 0.02,
            lon: lon,
            brightness: 18.5,
            sampledAt: conditions.fetchedAt
        )
        let outcome = WatchObservingQualityCanonicalizer.resolveFromCachedBrightness(
            conditions: conditions,
            selectedLocation: selected,
            sample: farSample,
            nightConditionsScore: night
        )
        guard case .nightOnly = outcome else {
            return XCTFail("far CL sample must night-only, got \(outcome)")
        }
    }
}
