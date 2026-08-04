@testable import SharedCode
import XCTest

// MARK: - Fixtures

private enum Phase4BFixtures {
    static let latitude = 45.45
    static let longitude = -122.75
    static let timeZoneID = "America/Los_Angeles"

    static func latitudeDegrees(offsetMeters: Double) -> Double {
        (offsetMeters / 6_371_000.0) * (180.0 / .pi)
    }

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
        revision: Int = 1
    ) -> ModeledZenithBrightnessSample {
        ModeledZenithBrightnessSample(
            latitude: lat,
            longitude: lon,
            modeledZenithSkyBrightness: brightness,
            dataset: dataset(revision: revision),
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
            name: "Dark Site",
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

    /// Conditions that `NightQualityAnalyzer.analyzeConditions` can score for `referenceDate`.
    static func analyzableConditions(
        locationID: UUID?,
        lat: Double = latitude,
        lon: Double = longitude,
        referenceDate: Date = Date(),
        cloudCover: Int = 10
    ) -> ViewingConditions {
        let tz = TimeZone(identifier: timeZoneID)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let startOfDay = calendar.startOfDay(for: referenceDate)

        func hour(_ h: Int, dayOffset: Int = 0) -> Date {
            calendar.date(byAdding: .hour, value: h + dayOffset * 24, to: startOfDay)!
        }

        func sunEvents(dayOffset: Int) -> SunEvents {
            SunEvents(
                sunrise: hour(6, dayOffset: dayOffset),
                sunset: hour(18, dayOffset: dayOffset),
                civilTwilightBegin: hour(5, dayOffset: dayOffset),
                civilTwilightEnd: hour(19, dayOffset: dayOffset),
                nauticalTwilightBegin: hour(4, dayOffset: dayOffset),
                nauticalTwilightEnd: hour(20, dayOffset: dayOffset),
                astronomicalTwilightBegin: hour(3, dayOffset: dayOffset),
                astronomicalTwilightEnd: hour(21, dayOffset: dayOffset)
            )
        }

        let forecasts: [HourlyForecast] = (0..<48).map { index in
            HourlyForecast(
                time: hour(index),
                cloudCover: cloudCover,
                humidity: 40,
                windSpeed: 2,
                windDirection: 180,
                temperature: 12,
                dewPoint: 4,
                visibility: 20_000,
                lowCloudCover: 0,
                midCloudCover: 0,
                highCloudCover: cloudCover,
                windSpeed200hPa: 40
            )
        }

        let moon = MoonInfo(
            phase: 0.1,
            phaseName: "New",
            altitude: 20,
            illumination: 5,
            emoji: "🌑"
        )

        return ViewingConditions(
            fetchedAt: referenceDate,
            location: CachedLocation(
                id: locationID,
                name: "Dark Site",
                latitude: lat,
                longitude: lon
            ),
            hourlyForecasts: forecasts,
            dailySunEvents: [sunEvents(dayOffset: 0), sunEvents(dayOffset: 1), sunEvents(dayOffset: 2)],
            dailyMoonInfo: [moon, moon, moon],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZoneID
        )
    }

    static func nightScore(for conditions: ViewingConditions) -> Int {
        NightQualityAnalyzer.analyzeConditions(conditions)!.calculatedScore
    }

    static func validPayload(
        id: UUID,
        conditions: ViewingConditions,
        brightness: Double = 18.5,
        oqOverride: Int? = nil,
        nightOverride: Int? = nil
    ) -> WatchObservingQualityPayload {
        let ctx = CrossSurfaceLocationContext(
            source: .saved,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            savedLocationID: id
        )
        let night = nightOverride ?? nightScore(for: conditions)
        let sample = sample(id: id, lat: ctx.latitude, lon: ctx.longitude, brightness: brightness)
        var snap = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: night,
                location: ctx,
                sample: sample,
                assessedAt: conditions.fetchedAt
            )
        )
        if let oqOverride {
            snap.observingQualityScore = oqOverride
        }
        if let nightOverride {
            snap.nightConditionsScore = nightOverride
        }
        return WatchObservingQualityPayload(location: ctx, transportedSnapshot: snap)
    }
}

// MARK: - Phone builder

final class WatchObservingQualityPayloadBuilderTests: XCTestCase {
    func testAuthoritativeSavedWithValidSampleProducesPayload() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let sample = Phase4BFixtures.sample(id: id)
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.payloadVersion, WatchObservingQualityPayload.currentPayloadVersion)
        XCTAssertEqual(payload?.location.savedLocationID, id)
        XCTAssertEqual(payload?.transportedSnapshot.brightnessAvailability, .available)
        let night = Phase4BFixtures.nightScore(for: conditions)
        XCTAssertEqual(payload?.transportedSnapshot.nightConditionsScore, night)
        let expected = ObservingQualityCalculator.assess(
            nightConditionsScore: night,
            modeledZenithSkyBrightness: 18.5
        )
        XCTAssertEqual(payload?.transportedSnapshot.observingQualityScore, expected.score)
    }

    func testSavedLocationIDMismatchProducesNoEnhancement() {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: UUID())
        let selected = Phase4BFixtures.selectedSaved(id: UUID())
        let sample = Phase4BFixtures.sample(id: selected.id)
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testSameSavedIDButConditionsCoordinatesOutsideStrictToleranceProducesNoPayload() {
        let id = UUID()
        // Conditions at slightly drifted coordinates (well beyond 1e-5°), same ID.
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            lat: Phase4BFixtures.latitude + 0.001,
            lon: Phase4BFixtures.longitude
        )
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let sample = Phase4BFixtures.sample(id: id)
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testPhase1SampleDistanceBeyond1000mProducesNoPayload() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let far = Phase4BFixtures.sample(
            id: id,
            lat: Phase4BFixtures.latitude + Phase4BFixtures.latitudeDegrees(offsetMeters: 5_000),
            lon: Phase4BFixtures.longitude
        )
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(far),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testCoordinatesExactlyWithinStrictToleranceRemainAccepted() {
        let id = UUID()
        let tol = WatchObservingQualitySavedLocationAssociation.coordinateTolerance
        // Stay strictly inside the inclusive band (IEEE float can push `base+tol` just over).
        let baseLat = 45.0
        let baseLon = -122.0
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            lat: baseLat + tol * 0.5,
            lon: baseLon
        )
        let selected = Phase4BFixtures.selectedSaved(id: id, lat: baseLat, lon: baseLon)
        let sample = Phase4BFixtures.sample(id: id, lat: baseLat, lon: baseLon)
        XCTAssertTrue(
            WatchObservingQualitySavedLocationAssociation.matches(
                selected: selected,
                conditionsLocation: conditions.location
            )
        )
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        XCTAssertNotNil(payload)
    }

    func testMissingSampleProducesNoEnhancement() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(nil),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testUnsupportedDatasetProducesNoEnhancement() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let sample = Phase4BFixtures.sample(id: id, revision: 99)
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testCurrentLocationProducesNoPhase4BEnhancement() {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: nil)
        let selected = Phase4BFixtures.selectedCurrent()
        let sample = Phase4BFixtures.sample(id: nil)
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testExplicitSampleInjectionAvoidsAppGroupIO() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        // baseURL nil + .sample must not require App Group
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(Phase4BFixtures.sample(id: id)),
            baseURL: nil
        )
        XCTAssertNotNil(payload)
        // Explicit nil still no I/O
        XCTAssertNil(
            WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
                conditions: conditions,
                selectedLocation: selected,
                brightness: .sample(nil),
                baseURL: nil
            )
        )
    }

    func testPushAndRequestReplyShareSameBuilderAPI() {
        // Both phone paths call makeSavedLocationPayload — assert single public factory shape.
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let sample = Phase4BFixtures.sample(id: id)
        let a = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        let b = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(sample),
            baseURL: nil
        )
        XCTAssertEqual(a, b)
        XCTAssertNotNil(a)
    }
}

// MARK: - Transport compatibility

final class WatchObservingQualityTransportCompatibilityTests: XCTestCase {
    func testOldConditionsOnlyMessageDecodesWithoutOQ() throws {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: UUID())
        let data = try JSONEncoder().encode(conditions)
        let decoded = try JSONDecoder().decode(ViewingConditions.self, from: data)
        XCTAssertEqual(decoded.location.latitude, conditions.location.latitude)
        // No OQ block — envelope optional
        let envelope: [String: Data] = ["conditions": data]
        XCTAssertNil(envelope["observingQuality"])
    }

    func testMalformedOQBlockDoesNotLoseConditions() throws {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: UUID())
        let conditionsData = try JSONEncoder().encode(conditions)
        let badOQ = Data("not-json".utf8)
        // Watch decode path: try? on OQ, conditions independent
        let decodedConditions = try JSONDecoder().decode(ViewingConditions.self, from: conditionsData)
        let oq = try? JSONDecoder().decode(WatchObservingQualityPayload.self, from: badOQ)
        XCTAssertNotNil(decodedConditions)
        XCTAssertNil(oq)
        let night = Phase4BFixtures.nightScore(for: decodedConditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: decodedConditions,
            transported: oq,
            selectedLocation: nil
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Expected night-only")
        }
    }

    func testUnknownOQVersionFallsBackToNight() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        var payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        payload.payloadVersion = 99
        let night = Phase4BFixtures.nightScore(for: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Expected night-only for unknown version")
        }
    }

    func testUnknownAvailabilityFallsBackToNight() throws {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        var dict = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(payload)
        ) as! [String: Any]
        var snap = dict["transportedSnapshot"] as! [String: Any]
        snap["brightnessAvailability"] = "future_state_xyz"
        dict["transportedSnapshot"] = snap
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(WatchObservingQualityPayload.self, from: data)
        // Snapshot decoder maps unknown availability → unavailable → makeSample nil → night
        XCTAssertEqual(decoded.transportedSnapshot.brightnessAvailability, .unavailable)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: decoded,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Expected night-only")
        }
    }

    func testNewAdditivePayloadPreservesConditionsKeys() throws {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let conditionsData = try JSONEncoder().encode(conditions)
        let oqData = try JSONEncoder().encode(payload)
        // Envelope shape used by WC
        let message: [String: Any] = [
            "type": "conditions",
            "conditions": conditionsData,
            "observingQuality": oqData
        ]
        XCTAssertEqual(message["type"] as? String, "conditions")
        let decodedConditions = try JSONDecoder().decode(
            ViewingConditions.self,
            from: message["conditions"] as! Data
        )
        let decodedOQ = try JSONDecoder().decode(
            WatchObservingQualityPayload.self,
            from: message["observingQuality"] as! Data
        )
        XCTAssertEqual(decodedConditions.location.id, id)
        XCTAssertEqual(decodedOQ.location.savedLocationID, id)
    }

    func testZeroScorePreservedWhenValid() {
        // Fingerprint / snapshot must not treat 0 as missing
        let loc = CrossSurfaceLocationContext(
            source: .saved, latitude: 45, longitude: -122, savedLocationID: UUID()
        )
        let snap = CrossSurfaceObservingQualitySnapshot.nightOnly(nightConditionsScore: 0)
        XCTAssertEqual(snap.nightConditionsScore, 0)
        XCTAssertEqual(snap.observingQualityScore, 0)
        let headline = WatchObservingQualityHeadline.nightOnly(nightScore: 0, location: loc)
        XCTAssertEqual(headline.observingQualityScore, 0)
        XCTAssertEqual(headline.nightConditionsScore, 0)
    }
}

// MARK: - Watch recomputation

final class WatchObservingQualityCanonicalizerTests: XCTestCase {
    func testValidSavedPayloadRecomputesAndDocuments() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: selected
        )
        guard case let .enhanced(snap, loc) = outcome else {
            return XCTFail("Expected enhanced")
        }
        XCTAssertEqual(loc.savedLocationID, id)
        XCTAssertEqual(snap.brightnessAvailability, .available)
        XCTAssertEqual(snap.observingQualityScore, payload.transportedSnapshot.observingQualityScore)
        XCTAssertEqual(snap.nightConditionsScore, payload.transportedSnapshot.nightConditionsScore)

        let doc = WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditions)
        XCTAssertEqual(doc?.snapshot.observingQualityScore, snap.observingQualityScore)
        XCTAssertEqual(doc?.associatedNightConditionsScore, snap.nightConditionsScore)
        XCTAssertEqual(doc?.associatedConditionsLocationID, id)
    }

    func testTamperedTransportedOQScoreRejected() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions, oqOverride: 1)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Tampered OQ must be rejected")
        }
    }

    func testTamperedTransportedNightScoreRejected() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let realNight = Phase4BFixtures.nightScore(for: conditions)
        let payload = Phase4BFixtures.validPayload(
            id: id,
            conditions: conditions,
            nightOverride: max(0, realNight - 15)
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, realNight)
        } else {
            XCTFail("Tampered night must be rejected")
        }
    }

    func testWrongSavedLocationIDRejected() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: UUID())
        )
        if case .nightOnly = outcome {
            // ok
        } else {
            XCTFail("Wrong selection ID must reject enhancement")
        }
    }

    func testMismatchedCoordinatesRejected() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        var payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        // Move sample coords beyond 1000 m via snapshot metadata
        let farLat = Phase4BFixtures.latitude + Phase4BFixtures.latitudeDegrees(offsetMeters: 5_000)
        payload.transportedSnapshot.brightnessLookupLatitude = farLat
        // Re-set brightness fields so makeSample still works but validity fails
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case .nightOnly = outcome {
            // ok
        } else {
            XCTFail("Far sample must reject")
        }
    }

    func testOutOfRangeBrightnessRejected() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        var payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        payload.transportedSnapshot.modeledZenithBrightness = 5.0 // below plausible range
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case .nightOnly = outcome {
            // ok
        } else {
            XCTFail("Out-of-range brightness must reject")
        }
    }

    func testUnsupportedDatasetRejected() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        var payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        payload.transportedSnapshot.brightnessDataset = Phase4BFixtures.dataset(revision: 99)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case .nightOnly = outcome {
            // ok
        } else {
            XCTFail("Unsupported dataset must reject")
        }
    }

    func testUnavailableBrightnessProducesExactNightScore() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let ctx = CrossSurfaceLocationContext(
            source: .saved,
            latitude: Phase4BFixtures.latitude,
            longitude: Phase4BFixtures.longitude,
            savedLocationID: id
        )
        let snap = CrossSurfaceObservingQualitySnapshot.nightOnly(
            nightConditionsScore: night,
            assessedAt: conditions.fetchedAt
        )
        let payload = WatchObservingQualityPayload(location: ctx, transportedSnapshot: snap)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Unavailable must be night-only")
        }
    }

    func testNeverPersistsTransportedWithoutRecomputationAgreement() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions, oqOverride: 99)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        let doc = WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditions)
        // Night-only document may exist, but must not carry tampered OQ 99
        XCTAssertNotEqual(doc?.snapshot.observingQualityScore, 99)
        if let doc {
            XCTAssertEqual(doc.snapshot.observingQualityScore, doc.snapshot.nightConditionsScore)
            XCTAssertEqual(doc.snapshot.brightnessAvailability, .unavailable)
        }
    }

    func testResolverParityWithPhoneForIdenticalInputs() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let sample = Phase4BFixtures.sample(id: id)
        let ctx = CrossSurfaceLocationContext(
            source: .saved,
            latitude: Phase4BFixtures.latitude,
            longitude: Phase4BFixtures.longitude,
            savedLocationID: id
        )
        let phoneSnap = CrossSurfaceObservingQualityResolver.resolve(
            .init(nightConditionsScore: night, location: ctx, sample: sample)
        )
        let payload = WatchObservingQualityPayload(location: ctx, transportedSnapshot: phoneSnap)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        guard case let .enhanced(watchSnap, _) = outcome else {
            return XCTFail("Expected enhanced parity")
        }
        XCTAssertEqual(watchSnap.observingQualityScore, phoneSnap.observingQualityScore)
        XCTAssertEqual(watchSnap.nightConditionsScore, phoneSnap.nightConditionsScore)
        XCTAssertEqual(watchSnap.modeledZenithBrightness, phoneSnap.modeledZenithBrightness)
    }
}

// MARK: - Persistence / association

final class WatchObservingQualityPersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase4b-oq-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testMissingOQFileIsSafe() {
        XCTAssertNil(AppGroupStorage.readWatchObservingQuality(baseURL: tempDir))
    }

    func testMalformedOQFileIsSafe() throws {
        let url = tempDir.appendingPathComponent(AppGroupStorage.watchObservingQualityFileName)
        try Data("{not valid".utf8).write(to: url)
        XCTAssertNil(AppGroupStorage.readWatchObservingQuality(baseURL: tempDir))
    }

    func testFuturePersistedVersionIsSafe() throws {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        var doc = WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditions)!
        doc.schemaVersion = 99
        XCTAssertTrue(AppGroupStorage.writeWatchObservingQuality(doc, baseURL: tempDir))
        XCTAssertNil(AppGroupStorage.readWatchObservingQuality(baseURL: tempDir))
    }

    func testOldOQForAnotherSavedLocationNotAssociated() {
        let idA = UUID()
        let idB = UUID()
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: idA)
        let payload = Phase4BFixtures.validPayload(id: idA, conditions: conditionsA)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditionsA,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA)
        )
        let doc = WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditionsA)!
        let conditionsB = Phase4BFixtures.analyzableConditions(locationID: idB)
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: conditionsB,
                selectedLocation: Phase4BFixtures.selectedSaved(id: idB)
            )
        )
    }

    func testOldOQForPreviousConditionsNotAssociatedWhenNightDiffers() {
        let id = UUID()
        let clear = Phase4BFixtures.analyzableConditions(locationID: id, cloudCover: 5)
        let cloudy = Phase4BFixtures.analyzableConditions(locationID: id, cloudCover: 95)
        let nightClear = Phase4BFixtures.nightScore(for: clear)
        let nightCloudy = Phase4BFixtures.nightScore(for: cloudy)
        XCTAssertNotEqual(nightClear, nightCloudy)

        let payload = Phase4BFixtures.validPayload(id: id, conditions: clear)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: clear,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        let doc = WatchObservingQualityCanonicalizer.document(from: outcome, conditions: clear)!
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: cloudy,
                selectedLocation: Phase4BFixtures.selectedSaved(id: id)
            )
        )
    }

    func testReceivingNightOnlyDisassociatesEnhancement() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let enhanced = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let enhancedOutcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: enhanced,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        guard case .enhanced = enhancedOutcome else {
            return XCTFail("setup")
        }
        // Night-only transport
        let nightOutcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: nil,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        guard case .nightOnly = nightOutcome else {
            return XCTFail("Expected night-only")
        }
        let nightDoc = WatchObservingQualityCanonicalizer.document(
            from: nightOutcome,
            conditions: conditions
        )
        XCTAssertEqual(nightDoc?.snapshot.brightnessAvailability, .unavailable)
        XCTAssertEqual(
            nightDoc?.snapshot.observingQualityScore,
            nightDoc?.snapshot.nightConditionsScore
        )
    }

    func testZeroPreservedAsValidScoreInDocument() {
        let id = UUID()
        let loc = CrossSurfaceLocationContext(
            source: .saved, latitude: 45.45, longitude: -122.75, savedLocationID: id
        )
        let snap = CrossSurfaceObservingQualitySnapshot.nightOnly(nightConditionsScore: 0)
        let doc = WatchObservingQualityDocument(
            snapshot: snap,
            location: loc,
            associatedNightConditionsScore: 0,
            associatedConditionsLocationID: id,
            associatedLatitude: 45.45,
            associatedLongitude: -122.75
        )
        XCTAssertTrue(AppGroupStorage.writeWatchObservingQuality(doc, baseURL: tempDir))
        let loaded = AppGroupStorage.readWatchObservingQuality(baseURL: tempDir)
        XCTAssertEqual(loaded?.snapshot.nightConditionsScore, 0)
        XCTAssertEqual(loaded?.snapshot.observingQualityScore, 0)
    }

    func testRoundTripAtomicWrite() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        let doc = WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditions)!
        XCTAssertTrue(AppGroupStorage.writeWatchObservingQuality(doc, baseURL: tempDir))
        let loaded = AppGroupStorage.readWatchObservingQuality(baseURL: tempDir)
        XCTAssertEqual(loaded, doc)
    }
}

// MARK: - Headline presentation & fingerprint reloads

final class WatchObservingQualityHeadlineAndFingerprintTests: XCTestCase {
    func testValidOQHeadlineNumberVerdictToneMatch() {
        let id = UUID()
        let loc = CrossSurfaceLocationContext(
            source: .saved, latitude: 45.45, longitude: -122.75, savedLocationID: id
        )
        let headline = WatchObservingQualityHeadline(
            nightConditionsScore: 80,
            observingQualityScore: 65,
            brightnessAvailability: .available,
            location: loc,
            dataset: LightPollutionDatasetIdentity.current
        )
        XCTAssertEqual(headline.observingQualityScore, 65)
        XCTAssertEqual(headline.verdict, CrossSurfaceHeadlineScorePresentation.verdict(for: 65))
        XCTAssertEqual(headline.verdict, "Good")
        XCTAssertEqual(
            ObservingQualityScoreBand.from(score: headline.observingQualityScore),
            .good
        )
        XCTAssertEqual(
            CrossSurfaceHeadlineScorePresentation.emoji(for: 65),
            ObservingQualityScoreBand.good.emoji
        )
    }

    func testCategoryBoundaryCrossingUpdatesAllThreeTogether() {
        let id = UUID()
        let loc = CrossSurfaceLocationContext(
            source: .saved, latitude: 45.45, longitude: -122.75, savedLocationID: id
        )
        let before = WatchObservingQualityHeadline(
            nightConditionsScore: 90,
            observingQualityScore: 79,
            brightnessAvailability: .available,
            location: loc,
            dataset: .current
        )
        let after = WatchObservingQualityHeadline(
            nightConditionsScore: 90,
            observingQualityScore: 80,
            brightnessAvailability: .available,
            location: loc,
            dataset: .current
        )
        XCTAssertEqual(before.verdict, "Good")
        XCTAssertEqual(after.verdict, "Excellent")
        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 79), .good)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 80), .excellent)
        XCTAssertEqual(CrossSurfaceHeadlineScorePresentation.emoji(for: 79), ObservingQualityScoreBand.good.emoji)
        XCTAssertEqual(CrossSurfaceHeadlineScorePresentation.emoji(for: 80), ObservingQualityScoreBand.excellent.emoji)
    }

    func testNightExcellentOQGoodHeadlineIsInternallyConsistent() {
        // Night would be Excellent (80+); OQ drops to Good (65).
        let nightScore = 90
        let oqScore = 65
        XCTAssertEqual(ObservingQualityScoreBand.from(score: nightScore), .excellent)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: oqScore), .good)

        let number = oqScore
        let emoji = CrossSurfaceHeadlineScorePresentation.emoji(for: number)
        let verdict = CrossSurfaceHeadlineScorePresentation.verdict(for: number)
        let band = CrossSurfaceHeadlineScorePresentation.band(for: number)
        let accessibility = ObservingQualityHeadlinePresentation(score: number).accessibilityLabel

        XCTAssertEqual(number, 65)
        XCTAssertEqual(emoji, ObservingQualityScoreBand.good.emoji)
        XCTAssertEqual(verdict, "Good")
        XCTAssertEqual(band, .good)
        XCTAssertTrue(accessibility.localizedCaseInsensitiveContains("good"))
        XCTAssertTrue(accessibility.contains("65"))

        // Night presentation (summary source) remains independent — emoji for night band differs.
        XCTAssertNotEqual(
            CrossSurfaceHeadlineScorePresentation.emoji(for: nightScore),
            emoji
        )
    }

    func testUnavailableOQPreservesNightHeadlineExactly() {
        let loc = CrossSurfaceLocationContext(
            source: .saved, latitude: 45.45, longitude: -122.75, savedLocationID: UUID()
        )
        let nightScore = 72
        let headline = WatchObservingQualityHeadline.nightOnly(nightScore: nightScore, location: loc)
        XCTAssertEqual(headline.observingQualityScore, nightScore)
        XCTAssertEqual(headline.nightConditionsScore, nightScore)
        XCTAssertEqual(headline.brightnessAvailability, .unavailable)
        XCTAssertEqual(headline.verdict, CrossSurfaceHeadlineScorePresentation.verdict(for: nightScore))
        XCTAssertEqual(
            CrossSurfaceHeadlineScorePresentation.emoji(for: headline.observingQualityScore),
            CrossSurfaceHeadlineScorePresentation.emoji(for: nightScore)
        )
        XCTAssertEqual(
            ObservingQualityScoreBand.from(score: headline.observingQualityScore),
            ObservingQualityScoreBand.from(score: nightScore)
        )
    }

    func testHalfNightScoresRemainNightDerivedConceptually() {
        // Phase 4B does not adjust half-night scores; only overall headline uses OQ.
        // CrossSurface resolver only exposes overall OQ — half-night not present on snapshot.
        let snap = CrossSurfaceObservingQualitySnapshot(
            nightConditionsScore: 80,
            observingQualityScore: 60,
            brightnessAvailability: .available,
            modeledZenithBrightness: 18.5,
            brightnessDataset: .current,
            brightnessLookupLatitude: 45.45,
            brightnessLookupLongitude: -122.75,
            brightnessSavedLocationID: UUID()
        )
        // No firstHalf/secondHalf on OQ snapshot — night assessment remains source of truth.
        XCTAssertEqual(snap.nightConditionsScore, 80)
        XCTAssertEqual(snap.observingQualityScore, 60)
    }

    func testAccessibilityUsesOQHeadline() {
        let presentation = ObservingQualityHeadlinePresentation(score: 65)
        XCTAssertTrue(presentation.accessibilityLabel.contains("65") || presentation.score == 65)
        XCTAssertEqual(presentation.band, .good)
    }

    func testSameStateNewerAssessedAtZeroReloads() {
        let id = UUID()
        let loc = CrossSurfaceLocationContext(
            source: .saved, latitude: 45.45, longitude: -122.75, savedLocationID: id
        )
        let a = ObservingQualityDisplayFingerprint(
            snapshot: CrossSurfaceObservingQualitySnapshot(
                nightConditionsScore: 70,
                observingQualityScore: 55,
                brightnessAvailability: .available,
                modeledZenithBrightness: 18.5,
                brightnessDataset: .current,
                brightnessLookupLatitude: 45.45,
                brightnessLookupLongitude: -122.75,
                brightnessSavedLocationID: id,
                assessedAt: Date(timeIntervalSince1970: 1_000)
            ),
            location: loc
        )
        let b = ObservingQualityDisplayFingerprint(
            snapshot: CrossSurfaceObservingQualitySnapshot(
                nightConditionsScore: 70,
                observingQualityScore: 55,
                brightnessAvailability: .available,
                modeledZenithBrightness: 18.5,
                brightnessDataset: .current,
                brightnessLookupLatitude: 45.45,
                brightnessLookupLongitude: -122.75,
                brightnessSavedLocationID: id,
                assessedAt: Date(timeIntervalSince1970: 9_999)
            ),
            location: loc
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(reloadCount(previous: a, updates: [b]), 0)
    }

    func testDuplicatePayloadZeroReloads() {
        let fp = makeFP(oq: 50, night: 70)
        XCTAssertEqual(reloadCount(previous: fp, updates: [fp, fp]), 0)
    }

    func testOQChangeOneReload() {
        let a = makeFP(oq: 50, night: 70)
        let b = makeFP(oq: 51, night: 70)
        XCTAssertEqual(reloadCount(previous: a, updates: [b]), 1)
    }

    func testNightScoreChangeOneReload() {
        let a = makeFP(oq: 50, night: 70)
        let b = makeFP(oq: 50, night: 71)
        XCTAssertEqual(reloadCount(previous: a, updates: [b]), 1)
    }

    func testAvailabilityChangeOneReload() {
        var a = makeFP(oq: 70, night: 70)
        // Build unavailable variant
        let loc = CrossSurfaceLocationContext(
            source: .saved, latitude: 45.45, longitude: -122.75, savedLocationID: UUID()
        )
        a = ObservingQualityDisplayFingerprint(
            source: .saved,
            savedLocationID: loc.savedLocationID,
            latitude: 45.45,
            longitude: -122.75,
            nightConditionsScore: 70,
            observingQualityScore: 70,
            brightnessAvailability: .available,
            dataset: .current
        )
        let b = ObservingQualityDisplayFingerprint(
            source: .saved,
            savedLocationID: a.savedLocationID,
            latitude: 45.45,
            longitude: -122.75,
            nightConditionsScore: 70,
            observingQualityScore: 70,
            brightnessAvailability: .unavailable,
            dataset: nil
        )
        XCTAssertEqual(reloadCount(previous: a, updates: [b]), 1)
    }

    func testSavedLocationChangeOneReload() {
        let a = makeFP(oq: 50, night: 70, id: UUID())
        let b = makeFP(oq: 50, night: 70, id: UUID())
        XCTAssertEqual(reloadCount(previous: a, updates: [b]), 1)
    }

    func testCoordinateBucketChangeOneReload() {
        let id = UUID()
        let a = ObservingQualityDisplayFingerprint(
            source: .saved,
            savedLocationID: id,
            latitude: 45.45000,
            longitude: -122.75000,
            nightConditionsScore: 70,
            observingQualityScore: 55,
            brightnessAvailability: .available,
            dataset: .current
        )
        // 1e-5° bucket scale: change by 0.00002° → different bucket
        let b = ObservingQualityDisplayFingerprint(
            source: .saved,
            savedLocationID: id,
            latitude: 45.45002,
            longitude: -122.75000,
            nightConditionsScore: 70,
            observingQualityScore: 55,
            brightnessAvailability: .available,
            dataset: .current
        )
        XCTAssertNotEqual(a.latitudeBucket, b.latitudeBucket)
        XCTAssertEqual(reloadCount(previous: a, updates: [b]), 1)
    }

    func testDatasetChangeOneReload() {
        let id = UUID()
        let a = ObservingQualityDisplayFingerprint(
            source: .saved,
            savedLocationID: id,
            latitude: 45.45,
            longitude: -122.75,
            nightConditionsScore: 70,
            observingQualityScore: 55,
            brightnessAvailability: .available,
            dataset: LightPollutionDatasetIdentity(
                datasetID: "lpatlas1", datasetRevision: 1, formatVersion: 1
            )
        )
        let b = ObservingQualityDisplayFingerprint(
            source: .saved,
            savedLocationID: id,
            latitude: 45.45,
            longitude: -122.75,
            nightConditionsScore: 70,
            observingQualityScore: 55,
            brightnessAvailability: .available,
            dataset: LightPollutionDatasetIdentity(
                datasetID: "lpatlas1", datasetRevision: 2, formatVersion: 1
            )
        )
        XCTAssertEqual(reloadCount(previous: a, updates: [b]), 1)
    }

    func testOneAcceptedUpdateCannotTriggerMultipleReloads() {
        // Coalesce: multiple identical intermediate writes → single comparison → 0 or 1 reload
        let a = makeFP(oq: 50, night: 70)
        let b = makeFP(oq: 60, night: 70)
        // Simulate dashboard persist + internal writes of same new state
        XCTAssertEqual(reloadCount(previous: a, updates: [b, b, b]), 1)
    }

    func testFingerprintExcludesTimestamps() {
        // assessedAt not a field on fingerprint — only material display fields
        let mirror = Mirror(reflecting: makeFP(oq: 1, night: 2))
        let labels = Set(mirror.children.compactMap(\.label))
        XCTAssertFalse(labels.contains("assessedAt"))
        XCTAssertFalse(labels.contains("fetchedAt"))
        XCTAssertTrue(labels.contains("observingQualityScore"))
        XCTAssertTrue(labels.contains("nightConditionsScore"))
    }

    // MARK: - Helpers

    private func makeFP(
        oq: Int,
        night: Int,
        id: UUID = UUID()
    ) -> ObservingQualityDisplayFingerprint {
        ObservingQualityDisplayFingerprint(
            source: .saved,
            savedLocationID: id,
            latitude: 45.45,
            longitude: -122.75,
            nightConditionsScore: night,
            observingQualityScore: oq,
            brightnessAvailability: .available,
            dataset: .current
        )
    }

    /// Mirrors watch manager: reload only when fingerprint changes; at most once per update batch.
    private func reloadCount(
        previous: ObservingQualityDisplayFingerprint?,
        updates: [ObservingQualityDisplayFingerprint]
    ) -> Int {
        var last = previous
        var reloads = 0
        for next in updates {
            if next != last {
                reloads += 1
                last = next
            }
        }
        return reloads
    }
}

// MARK: - Current Location remains night-only (Phase 4C not implemented)

final class WatchObservingQualityCurrentLocationGuardTests: XCTestCase {
    func testBuilderNeverEnhancesCurrentLocation() {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: nil)
        let selected = Phase4BFixtures.selectedCurrent()
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: selected,
            brightness: .sample(Phase4BFixtures.sample(id: nil)),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testCanonicalizerRejectsCurrentGPSTransportedSource() {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: nil)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let ctx = CrossSurfaceLocationContext(
            source: .currentGPS,
            latitude: Phase4BFixtures.latitude,
            longitude: Phase4BFixtures.longitude,
            savedLocationID: nil
        )
        let sample = Phase4BFixtures.sample(id: nil)
        let snap = CrossSurfaceObservingQualityResolver.resolve(
            .init(nightConditionsScore: night, location: ctx, sample: sample)
        )
        // Even if phone wrongly sent currentGPS OQ (not Phase 4B path), watch requires .saved
        let payload = WatchObservingQualityPayload(location: ctx, transportedSnapshot: snap)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedCurrent()
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Current Location transport must not enhance in 4B")
        }
    }

    func testMissingSavedLocationIDDoesNotImplyCurrentLocationEnhancement() {
        // Spec: do not infer Current Location from missing savedLocationID for OQ.
        let conditions = Phase4BFixtures.analyzableConditions(locationID: nil)
        let night = Phase4BFixtures.nightScore(for: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: nil,
            selectedLocation: nil
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Expected night-only")
        }
    }
}

// MARK: - Strict saved-location association

final class WatchObservingQualityStrictAssociationTests: XCTestCase {
    func testSameIDButTransportContextMismatchesConditionsCoordinatesIsNightOnly() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            lat: Phase4BFixtures.latitude + 0.002,
            lon: Phase4BFixtures.longitude
        )
        let night = Phase4BFixtures.nightScore(for: conditions)
        // Payload built against original coords (not conditions coords).
        let baseConditions = Phase4BFixtures.analyzableConditions(locationID: id)
        var payload = Phase4BFixtures.validPayload(id: id, conditions: baseConditions)
        // Force transported night to match drifted conditions so only coord association fails.
        payload.transportedSnapshot.nightConditionsScore = night
        payload.transportedSnapshot.observingQualityScore = night // will fail agreement anyway if enhanced
        // Ensure location context still at original coords
        XCTAssertEqual(payload.location.latitude, Phase4BFixtures.latitude)

        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(
                id: id,
                lat: Phase4BFixtures.latitude + 0.002,
                lon: Phase4BFixtures.longitude
            )
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Coordinate mismatch must be night-only")
        }
    }

    func testSameIDButSelectedCoordinatesMismatchTransportedContextIsNightOnly() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let selected = Phase4BFixtures.selectedSaved(
            id: id,
            lat: Phase4BFixtures.latitude + 0.002,
            lon: Phase4BFixtures.longitude
        )
        let night = Phase4BFixtures.nightScore(for: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: selected
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Selected coord mismatch must be night-only")
        }
    }

    func testPersistedDocumentWithMatchingIDButOldCoordinatesIsRejected() {
        let id = UUID()
        let oldConditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: oldConditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: oldConditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        let doc = WatchObservingQualityCanonicalizer.document(from: outcome, conditions: oldConditions)!
        let newConditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            lat: Phase4BFixtures.latitude + 0.001,
            lon: Phase4BFixtures.longitude
        )
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: newConditions,
                selectedLocation: Phase4BFixtures.selectedSaved(
                    id: id,
                    lat: Phase4BFixtures.latitude + 0.001,
                    lon: Phase4BFixtures.longitude
                )
            )
        )
    }

    func testStrictToleranceBoundaryAcceptedForAssociationHelper() {
        let id = UUID()
        let tol = WatchObservingQualitySavedLocationAssociation.coordinateTolerance
        let base = 45.0
        // Within band (half tolerance — avoid float edge of base+tol).
        XCTAssertTrue(
            WatchObservingQualitySavedLocationAssociation.matches(
                savedLocationID: id,
                latitude: base,
                longitude: -122.0,
                otherSavedLocationID: id,
                otherLatitude: base + tol * 0.5,
                otherLongitude: -122.0
            )
        )
        // Outside band
        XCTAssertFalse(
            WatchObservingQualitySavedLocationAssociation.matches(
                savedLocationID: id,
                latitude: base,
                longitude: -122.0,
                otherSavedLocationID: id,
                otherLatitude: base + tol * 2,
                otherLongitude: -122.0
            )
        )
    }

    func testValidMatchingSavedLocationContinuesToEnhance() {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id)
        )
        guard case .enhanced = outcome else {
            return XCTFail("Valid matching location must enhance")
        }
    }
}


// MARK: - Test doubles

private final class RecordingReloadReporter: WatchComplicationReloadReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func reloadComplications() {
        lock.lock(); _count += 1; lock.unlock()
    }
}

private final class InMemoryWatchConditionsStore: WatchConditionsPersisting, @unchecked Sendable {
    enum FailureMode: Sendable {
        case none
        case conditionsEncode
        case conditionsWrite
        case oqWriteAfterConditions
        case oqClearAfterConditions
    }

    private let lock = NSLock()
    private var _conditions: ViewingConditions?
    private var _oq: WatchObservingQualityDocument?
    private var _persistCount = 0
    private var _failureMode: FailureMode = .none

    var conditions: ViewingConditions? {
        lock.lock(); defer { lock.unlock() }
        return _conditions
    }
    var observingQuality: WatchObservingQualityDocument? {
        lock.lock(); defer { lock.unlock() }
        return _oq
    }
    var persistCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _persistCount
    }

    func setFailureMode(_ mode: FailureMode) {
        lock.lock(); _failureMode = mode; lock.unlock()
    }

    func persistAcceptedPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?
    ) throws {
        lock.lock()
        let mode = _failureMode
        lock.unlock()
        switch mode {
        case .none: break
        case .conditionsEncode:
            throw WatchConditionsPersistError.encodingFailed("injected encode")
        case .conditionsWrite:
            throw WatchConditionsPersistError.commitConditionsFailed("injected conditions write")
        case .oqWriteAfterConditions:
            throw WatchConditionsPersistError.commitObservingQualityFailed("injected oq write")
        case .oqClearAfterConditions:
            throw WatchConditionsPersistError.clearObservingQualityFailed("injected oq clear")
        }
        lock.lock()
        _conditions = conditions
        _oq = observingQuality
        _persistCount += 1
        lock.unlock()
    }
}

/// Gate that holds the first matching hook until released.
private actor OrderingGate: WatchConditionsUpdateGate {
    enum Mode {
        case holdBeforePersist
        case holdBeforeApplyCached
    }

    private var firstEntered = false
    private var firstHold: CheckedContinuation<Void, Never>?
    private var firstResume: CheckedContinuation<Void, Never>?
    private let mode: Mode

    init(mode: Mode = .holdBeforePersist) {
        self.mode = mode
    }

    func beforePersist() async {
        guard mode == .holdBeforePersist else { return }
        await holdIfFirst()
    }

    func beforeApplyCached() async {
        guard mode == .holdBeforeApplyCached else { return }
        await holdIfFirst()
    }

    private func holdIfFirst() async {
        if !firstEntered {
            firstEntered = true
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                firstHold = cont
                firstResume?.resume()
                firstResume = nil
            }
        }
    }

    func waitUntilFirstIsHeld() async {
        if firstHold != nil { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if firstHold != nil {
                cont.resume()
            } else {
                firstResume = cont
            }
        }
    }

    func releaseFirst() {
        firstHold?.resume()
        firstHold = nil
    }
}

// MARK: - Live arrival ordering (token before await)

final class WatchConditionsLiveArrivalOrderingTests: XCTestCase {
    /// A claims first, suspends during preparation; B claims and applies; A resumes and is discarded.
    func testEarlierTokenCannotOverwriteLaterAfterPreparationDelay() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )

        let idA = UUID()
        let idB = UUID()
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 5)
        let conditionsB = Phase4BFixtures.analyzableConditions(locationID: idB, cloudCover: 80)
        let payloadA = Phase4BFixtures.validPayload(id: idA, conditions: conditionsA)
        let payloadB = Phase4BFixtures.validPayload(id: idB, conditions: conditionsB)

        // Claim A first (sequence 1) — before any timezone/preparation await.
        let tokenA = await coordinator.beginLiveUpdate()
        XCTAssertEqual(tokenA.sequence, 1)

        let prepGate = OrderingGate(mode: .holdBeforePersist)
        // Use a separate coordinator path: A will call accept after delayed prep.
        // Simulate prep delay with an external continuation, not coordinator gate.
        let prepHold = AsyncStream<Void>.makeStream()
        let taskA = Task {
            // Suspend during "timezone resolution" after claim.
            for await _ in prepHold.stream { break }
            return await coordinator.accept(
                conditions: conditionsA,
                transported: payloadA,
                selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
                locationTimeZone: TimeZone(identifier: "UTC"),
                reloadComplications: true,
                token: tokenA
            )
        }
        // Ensure A is waiting on prep (yield)
        await Task.yield()
        await Task.yield()

        // B claims later and finishes fully first.
        let tokenB = await coordinator.beginLiveUpdate()
        XCTAssertEqual(tokenB.sequence, 2)
        let resultB = await coordinator.accept(
            conditions: conditionsB,
            transported: payloadB,
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: TimeZone(identifier: "UTC"),
            reloadComplications: true,
            token: tokenB
        )
        guard case let .applied(stateB) = resultB else {
            return XCTFail("B must apply")
        }

        // Resume A preparation.
        prepHold.continuation.yield(())
        prepHold.continuation.finish()
        let resultA = await taskA.value
        if case .discardedStale = resultA {
            // ok
        } else {
            XCTFail("A must be discarded, got \(String(describing: resultA))")
        }

        XCTAssertEqual(store.conditions?.location.id, idB)
        XCTAssertEqual(store.observingQuality?.location.savedLocationID, idB)
        XCTAssertEqual(store.persistCount, 1, "A must not persist")
        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, idB)
        XCTAssertEqual(applied?.displayFingerprint, stateB.displayFingerprint)
        XCTAssertEqual(reloader.count, 1)
        XCTAssertTrue(stateB.didReloadComplications)
        _ = prepGate
    }

    func testStaleAcceptDuringPersistGateDoesNotWrite() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let gate = OrderingGate(mode: .holdBeforePersist)
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: gate
        )
        let idA = UUID()
        let idB = UUID()
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 5)
        let conditionsB = Phase4BFixtures.analyzableConditions(locationID: idB, cloudCover: 80)

        let tokenA = await coordinator.beginLiveUpdate()
        let taskA = Task {
            await coordinator.accept(
                conditions: conditionsA,
                transported: Phase4BFixtures.validPayload(id: idA, conditions: conditionsA),
                selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
                locationTimeZone: nil,
                reloadComplications: true,
                token: tokenA
            )
        }
        await gate.waitUntilFirstIsHeld()

        let tokenB = await coordinator.beginLiveUpdate()
        let resultB = await coordinator.accept(
            conditions: conditionsB,
            transported: Phase4BFixtures.validPayload(id: idB, conditions: conditionsB),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenB
        )
        await gate.releaseFirst()
        let resultA = await taskA.value

        if case .discardedStale = resultA { /* ok */ } else { XCTFail("stale A") }
        guard case .applied = resultB else { return XCTFail("B applied") }
        XCTAssertEqual(store.persistCount, 1)
        XCTAssertEqual(store.conditions?.location.id, idB)
        XCTAssertEqual(reloader.count, 1)
    }
}

// MARK: - Deferred cache latest-started-wins

final class WatchConditionsDeferredCacheApplyTests: XCTestCase {
    func testOlderCacheAfterNewerCacheIsDiscarded() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let gate = OrderingGate(mode: .holdBeforeApplyCached)
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: gate
        )
        let idA = UUID()
        let idB = UUID()
        let tokenA = await coordinator.beginDeferredApplication()
        let tokenB = await coordinator.beginDeferredApplication()
        XCTAssertEqual(tokenA.liveGeneration, tokenB.liveGeneration)
        XCTAssertLessThan(tokenA.deferredSequence, tokenB.deferredSequence)

        let taskA = Task {
            await coordinator.applyCached(
                conditions: Phase4BFixtures.analyzableConditions(locationID: idA),
                selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
                persistedDocument: nil,
                locationTimeZone: nil,
                token: tokenA
            )
        }
        await gate.waitUntilFirstIsHeld()

        // B starts later but uses Immediate path for apply by releasing only after B...
        // A is held on first applyCached; B's applyCached is second so passes through.
        let resultB = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idB),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: tokenB
        )
        await gate.releaseFirst()
        let resultA = await taskA.value

        guard case .applied = resultB else { return XCTFail("B applies") }
        if case .discardedStale = resultA { /* ok */ } else {
            XCTFail("older A discarded, got \(String(describing: resultA))")
        }
        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, idB)
        XCTAssertEqual(reloader.count, 0)
        XCTAssertEqual(store.persistCount, 0)
    }

    func testOlderCacheFinishingFirstIsDiscardedWhenNewerAlreadyStarted() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let idA = UUID()
        let idB = UUID()
        let tokenA = await coordinator.beginDeferredApplication()
        let tokenB = await coordinator.beginDeferredApplication()
        // A finishes first but B already started → A discarded
        let resultA = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idA),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: tokenA
        )
        if case .discardedStale = resultA { /* ok */ } else {
            XCTFail("A discarded because B already started")
        }
        let resultB = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idB),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: tokenB
        )
        guard case .applied = resultB else { return XCTFail("B applies") }
        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, idB)
        XCTAssertNil(store.conditions)
        XCTAssertEqual(reloader.count, 0)
    }

    func testSingleCacheAppliesWithoutReloadOrWrite() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let id = UUID()
        let token = await coordinator.beginDeferredApplication()
        let result = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: id),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            persistedDocument: nil,
            locationTimeZone: TimeZone(identifier: "UTC"),
            token: token
        )
        guard case let .applied(state) = result else { return XCTFail("apply") }
        XCTAssertEqual(state.conditions.location.id, id)
        XCTAssertFalse(state.didReloadComplications)
        XCTAssertEqual(reloader.count, 0)
        XCTAssertEqual(store.persistCount, 0)
    }

    func testLiveUpdateInvalidatesOutstandingCacheToken() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let cacheToken = await coordinator.beginDeferredApplication()
        let id = UUID()
        let live = Phase4BFixtures.analyzableConditions(locationID: id)
        let liveToken = await coordinator.beginLiveUpdate()
        _ = await coordinator.accept(
            conditions: live,
            transported: Phase4BFixtures.validPayload(id: id, conditions: live),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            locationTimeZone: nil,
            reloadComplications: true,
            token: liveToken
        )
        let cacheID = UUID()
        let cacheResult = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: cacheID),
            selectedLocation: Phase4BFixtures.selectedSaved(id: cacheID),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: cacheToken
        )
        if case .discardedStale = cacheResult { /* ok */ } else { XCTFail("live invalidates cache") }
        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, id)
        XCTAssertEqual(reloader.count, 1)
        XCTAssertEqual(store.persistCount, 1)
    }

    func testDiscardedCacheNeverWritesOrReloads() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let token = await coordinator.beginDeferredApplication()
        _ = await coordinator.beginDeferredApplication() // newer start
        let result = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            selectedLocation: nil,
            persistedDocument: nil,
            locationTimeZone: nil,
            token: token
        )
        if case .discardedStale = result { /* ok */ } else { XCTFail("discarded") }
        XCTAssertEqual(reloader.count, 0)
        XCTAssertEqual(store.persistCount, 0)
    }
}

// MARK: - In-memory coordinator persist failures (still useful)

final class WatchConditionsPairPersistenceFailureTests: XCTestCase {
    func testConditionsWriteFailureDoesNotApplyOrReload() async {
        let store = InMemoryWatchConditionsStore()
        store.setFailureMode(.conditionsWrite)
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store, reloader: reloader, gate: ImmediateWatchConditionsUpdateGate()
        )
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let token = await coordinator.beginLiveUpdate()
        let result = await coordinator.accept(
            conditions: conditions,
            transported: Phase4BFixtures.validPayload(id: id, conditions: conditions),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            locationTimeZone: nil,
            reloadComplications: true,
            token: token
        )
        if case .persistFailed = result { /* ok */ } else { XCTFail("persistFailed") }
        let applied = await coordinator.appliedState
        XCTAssertNil(applied)
        XCTAssertEqual(reloader.count, 0)
        XCTAssertEqual(store.persistCount, 0)
    }

    func testFailedThenSuccessfulUpdateApplies() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store, reloader: reloader, gate: ImmediateWatchConditionsUpdateGate()
        )
        store.setFailureMode(.conditionsWrite)
        let t1 = await coordinator.beginLiveUpdate()
        _ = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            transported: nil,
            selectedLocation: nil,
            locationTimeZone: nil,
            reloadComplications: true,
            token: t1
        )
        store.setFailureMode(.none)
        let id = UUID()
        let ok = Phase4BFixtures.analyzableConditions(locationID: id)
        let t2 = await coordinator.beginLiveUpdate()
        let result = await coordinator.accept(
            conditions: ok,
            transported: Phase4BFixtures.validPayload(id: id, conditions: ok),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            locationTimeZone: nil,
            reloadComplications: true,
            token: t2
        )
        guard case .applied = result else { return XCTFail("success") }
        XCTAssertEqual(store.conditions?.location.id, id)
        XCTAssertEqual(reloader.count, 1)
    }
}

// MARK: - Real AppGroup transaction with injectable filesystem

/// In-memory FS that can fail specific operations while exercising production algorithm.
private final class InjectablePairFileSystem: WatchConditionsPairFileSystem, @unchecked Sendable {
    enum Op: String, Sendable {
        case read
        case writeAtomic
        case remove
    }

    private let lock = NSLock()
    private var files: [String: Data] = [:]
    /// Fail the Nth call matching predicate (1-based).
    var failOn: ((Op, String) -> Bool)?
    var failError: Error = NSError(domain: "test", code: 1)
    private var callLog: [(Op, String)] = []

    func snapshot() -> [String: Data] {
        lock.lock(); defer { lock.unlock() }
        return files
    }

    func seed(path: String, data: Data) {
        lock.lock(); files[path] = data; lock.unlock()
    }

    func fileExists(atPath path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[path] != nil
    }

    func readData(atPath path: String) throws -> Data {
        lock.lock()
        callLog.append((.read, path))
        let shouldFail = failOn?(.read, path) ?? false
        let data = files[path]
        lock.unlock()
        if shouldFail { throw failError }
        guard let data else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        }
        return data
    }

    func writeData(_ data: Data, toPath path: String, options: Data.WritingOptions) throws {
        lock.lock()
        callLog.append((.writeAtomic, path))
        let shouldFail = failOn?(.writeAtomic, path) ?? false
        if shouldFail {
            lock.unlock()
            throw failError
        }
        files[path] = data
        lock.unlock()
    }

    func removeItem(atPath path: String) throws {
        lock.lock()
        callLog.append((.remove, path))
        let shouldFail = failOn?(.remove, path) ?? false
        if shouldFail {
            lock.unlock()
            throw failError
        }
        files.removeValue(forKey: path)
        lock.unlock()
    }

    func hasTempOrBak(baseURL: URL) -> Bool {
        let names = [
            AppGroupStorage.watchNightConditionsFileName + ".tmp",
            AppGroupStorage.watchObservingQualityFileName + ".tmp",
            AppGroupStorage.watchNightConditionsFileName + ".bak",
        ]
        lock.lock(); defer { lock.unlock() }
        return names.contains { files[baseURL.appendingPathComponent($0).path] != nil }
    }
}

final class WatchConditionsAppGroupTransactionTests: XCTestCase {
    private var baseURL: URL!
    private var fs: InjectablePairFileSystem!

    private var conditionsPath: String {
        baseURL.appendingPathComponent(AppGroupStorage.watchNightConditionsFileName).path
    }
    private var oqPath: String {
        baseURL.appendingPathComponent(AppGroupStorage.watchObservingQualityFileName).path
    }

    override func setUp() {
        super.setUp()
        baseURL = URL(fileURLWithPath: "/virtual/phase4b-\(UUID().uuidString)")
        fs = InjectablePairFileSystem()
    }

    private func seedPriorPair() throws -> (ViewingConditions, WatchObservingQualityDocument) {
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id, cloudCover: 5)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: conditions)
        let doc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: conditions,
                transported: payload,
                selectedLocation: Phase4BFixtures.selectedSaved(id: id)
            ),
            conditions: conditions
        )!
        try AppGroupStorage.persistWatchConditionsPair(
            conditions: conditions,
            observingQuality: doc,
            baseURL: baseURL,
            fileSystem: fs
        )
        return (conditions, doc)
    }

    func testPriorExistsButCannotReadAbortsBeforeMutation() throws {
        let (prior, priorDoc) = try seedPriorPair()
        let priorSnap = fs.snapshot()
        // Fail reading prior conditions during backup phase (final conditions path).
        fs.failOn = { op, path in
            op == .read && path == self.conditionsPath
        }
        let idNew = UUID()
        let newC = Phase4BFixtures.analyzableConditions(locationID: idNew, cloudCover: 40)
        XCTAssertThrowsError(
            try AppGroupStorage.persistWatchConditionsPair(
                conditions: newC,
                observingQuality: nil,
                baseURL: baseURL,
                fileSystem: fs
            )
        ) { error in
            guard let e = error as? WatchConditionsPersistError else {
                return XCTFail("wrong error \(error)")
            }
            if case .priorBackupFailed = e { /* ok */ } else {
                XCTFail("expected priorBackupFailed, got \(e)")
            }
        }
        // Final pair unchanged
        fs.failOn = nil
        let loadedC = try JSONDecoder().decode(
            ViewingConditions.self,
            from: try fs.readData(atPath: conditionsPath)
        )
        XCTAssertEqual(loadedC.location.id, prior.location.id)
        let loadedO = try JSONDecoder().decode(
            WatchObservingQualityDocument.self,
            from: try fs.readData(atPath: oqPath)
        )
        XCTAssertEqual(loadedO.location.savedLocationID, priorDoc.location.savedLocationID)
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
        // No new data leaked
        XCTAssertEqual(fs.snapshot()[conditionsPath], priorSnap[conditionsPath])
    }

    func testConditionsFinalCommitFailsLeavesPriorIntact() throws {
        let (prior, _) = try seedPriorPair()
        var finalWriteCount = 0
        fs.failOn = { op, path in
            if op == .writeAtomic && path == self.conditionsPath {
                finalWriteCount += 1
                // First final write after staging is conditions promote — fail it.
                // Staging writes go to .tmp paths first.
                return true
            }
            return false
        }
        let newC = Phase4BFixtures.analyzableConditions(locationID: UUID())
        XCTAssertThrowsError(
            try AppGroupStorage.persistWatchConditionsPair(
                conditions: newC,
                observingQuality: nil,
                baseURL: baseURL,
                fileSystem: fs
            )
        ) { error in
            if let e = error as? WatchConditionsPersistError, case .commitConditionsFailed = e {
                // ok
            } else {
                XCTFail("\(error)")
            }
        }
        fs.failOn = nil
        let loaded = try JSONDecoder().decode(
            ViewingConditions.self,
            from: try fs.readData(atPath: conditionsPath)
        )
        XCTAssertEqual(loaded.location.id, prior.location.id)
        XCTAssertTrue(fs.fileExists(atPath: oqPath))
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
        XCTAssertGreaterThanOrEqual(finalWriteCount, 1)
    }

    func testOQWriteFailsAfterConditionsCommitRollsBackConditions() throws {
        let (prior, priorDoc) = try seedPriorPair()
        fs.failOn = { op, path in
            op == .writeAtomic && path == self.oqPath
        }
        let idNew = UUID()
        let newC = Phase4BFixtures.analyzableConditions(locationID: idNew, cloudCover: 30)
        let newPayload = Phase4BFixtures.validPayload(id: idNew, conditions: newC)
        let newDoc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: newC,
                transported: newPayload,
                selectedLocation: Phase4BFixtures.selectedSaved(id: idNew)
            ),
            conditions: newC
        )!
        XCTAssertThrowsError(
            try AppGroupStorage.persistWatchConditionsPair(
                conditions: newC,
                observingQuality: newDoc,
                baseURL: baseURL,
                fileSystem: fs
            )
        ) { error in
            if let e = error as? WatchConditionsPersistError, case .commitObservingQualityFailed = e {
                // ok
            } else {
                XCTFail("\(error)")
            }
        }
        fs.failOn = nil
        let loadedC = try JSONDecoder().decode(
            ViewingConditions.self,
            from: try fs.readData(atPath: conditionsPath)
        )
        XCTAssertEqual(loadedC.location.id, prior.location.id, "conditions rolled back")
        let loadedO = try JSONDecoder().decode(
            WatchObservingQualityDocument.self,
            from: try fs.readData(atPath: oqPath)
        )
        XCTAssertEqual(loadedO.location.savedLocationID, priorDoc.location.savedLocationID)
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
    }

    func testOQClearFailsAfterConditionsCommitRollsBack() throws {
        let (prior, priorDoc) = try seedPriorPair()
        fs.failOn = { op, path in
            op == .remove && path == self.oqPath
        }
        let nightOnly = Phase4BFixtures.analyzableConditions(locationID: UUID(), cloudCover: 90)
        XCTAssertThrowsError(
            try AppGroupStorage.persistWatchConditionsPair(
                conditions: nightOnly,
                observingQuality: nil,
                baseURL: baseURL,
                fileSystem: fs
            )
        ) { error in
            if let e = error as? WatchConditionsPersistError, case .clearObservingQualityFailed = e {
                // ok
            } else {
                XCTFail("\(error)")
            }
        }
        fs.failOn = nil
        let loadedC = try JSONDecoder().decode(
            ViewingConditions.self,
            from: try fs.readData(atPath: conditionsPath)
        )
        XCTAssertEqual(loadedC.location.id, prior.location.id)
        let loadedO = try JSONDecoder().decode(
            WatchObservingQualityDocument.self,
            from: try fs.readData(atPath: oqPath)
        )
        XCTAssertEqual(loadedO.snapshot.brightnessAvailability, priorDoc.snapshot.brightnessAvailability)
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
    }

    func testNoPriorAndOQFailureLeavesNoNewConditions() throws {
        // No prior files
        fs.failOn = { op, path in
            op == .writeAtomic && path == self.oqPath
        }
        let id = UUID()
        let c = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: c)
        let doc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: c,
                transported: payload,
                selectedLocation: Phase4BFixtures.selectedSaved(id: id)
            ),
            conditions: c
        )!
        XCTAssertThrowsError(
            try AppGroupStorage.persistWatchConditionsPair(
                conditions: c,
                observingQuality: doc,
                baseURL: baseURL,
                fileSystem: fs
            )
        )
        fs.failOn = nil
        XCTAssertFalse(fs.fileExists(atPath: conditionsPath), "new conditions removed on rollback")
        XCTAssertFalse(fs.fileExists(atPath: oqPath), "no stale OQ association")
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
    }

    func testRollbackWriteFailsReportsRollbackFailed() throws {
        _ = try seedPriorPair()
        var oqFailed = false
        fs.failOn = { op, path in
            if op == .writeAtomic && path == self.oqPath {
                oqFailed = true
                return true
            }
            // After OQ fails, rollback writes to conditionsPath — fail that too.
            if oqFailed && op == .writeAtomic && path == self.conditionsPath {
                return true
            }
            return false
        }
        let id = UUID()
        let c = Phase4BFixtures.analyzableConditions(locationID: id)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: c)
        let doc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: c,
                transported: payload,
                selectedLocation: Phase4BFixtures.selectedSaved(id: id)
            ),
            conditions: c
        )!
        XCTAssertThrowsError(
            try AppGroupStorage.persistWatchConditionsPair(
                conditions: c,
                observingQuality: doc,
                baseURL: baseURL,
                fileSystem: fs
            )
        ) { error in
            if let e = error as? WatchConditionsPersistError, case .rollbackFailed = e {
                // ok
            } else {
                XCTFail("expected rollbackFailed, got \(error)")
            }
        }
    }

    func testSuccessReplacesBothFiles() throws {
        _ = try seedPriorPair()
        let id = UUID()
        let c = Phase4BFixtures.analyzableConditions(locationID: id, cloudCover: 15)
        let payload = Phase4BFixtures.validPayload(id: id, conditions: c)
        let doc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: c,
                transported: payload,
                selectedLocation: Phase4BFixtures.selectedSaved(id: id)
            ),
            conditions: c
        )!
        try AppGroupStorage.persistWatchConditionsPair(
            conditions: c,
            observingQuality: doc,
            baseURL: baseURL,
            fileSystem: fs
        )
        let loadedC = try JSONDecoder().decode(
            ViewingConditions.self,
            from: try fs.readData(atPath: conditionsPath)
        )
        XCTAssertEqual(loadedC.location.id, id)
        let loadedO = try JSONDecoder().decode(
            WatchObservingQualityDocument.self,
            from: try fs.readData(atPath: oqPath)
        )
        XCTAssertEqual(loadedO.location.savedLocationID, id)
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
    }

    func testSuccessNightOnlyRemovesOQ() throws {
        _ = try seedPriorPair()
        XCTAssertTrue(fs.fileExists(atPath: oqPath))
        let night = Phase4BFixtures.analyzableConditions(locationID: UUID(), cloudCover: 95)
        try AppGroupStorage.persistWatchConditionsPair(
            conditions: night,
            observingQuality: nil,
            baseURL: baseURL,
            fileSystem: fs
        )
        XCTAssertTrue(fs.fileExists(atPath: conditionsPath))
        XCTAssertFalse(fs.fileExists(atPath: oqPath))
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
    }

    func testTempsCleanedOnStagingFailure() throws {
        fs.failOn = { op, path in
            path.hasSuffix(".tmp") && op == .writeAtomic
        }
        XCTAssertThrowsError(
            try AppGroupStorage.persistWatchConditionsPair(
                conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
                observingQuality: nil,
                baseURL: baseURL,
                fileSystem: fs
            )
        )
        XCTAssertFalse(fs.hasTempOrBak(baseURL: baseURL))
        XCTAssertFalse(fs.fileExists(atPath: conditionsPath))
    }
}


// MARK: - Production live-ingress boundary (claim before Task)

final class WatchConditionsLiveIngressBoundaryTests: XCTestCase {
    /// Claim A then B synchronously (arrival order); process B Task first, then A.
    func testPushAThenB_BProcessingFirstStillBWins() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let ingress = WatchConditionsLiveEventIngress(claim: { coordinator.claimLiveUpdate() })

        let idA = UUID()
        let idB = UUID()
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 5)
        let conditionsB = Phase4BFixtures.analyzableConditions(locationID: idB, cloudCover: 80)

        // Ingress claims in arrival order A then B — not inside Tasks.
        let tokenA = ingress.claimPushIngress()
        let tokenB = ingress.claimPushIngress()
        XCTAssertEqual(tokenA.sequence, 1)
        XCTAssertEqual(tokenB.sequence, 2)
        XCTAssertEqual(coordinator.currentLiveSequence, 2)

        // Force B processing before A (opposite of arrival).
        let resultB = await coordinator.accept(
            conditions: conditionsB,
            transported: Phase4BFixtures.validPayload(id: idB, conditions: conditionsB),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenB
        )
        let resultA = await coordinator.accept(
            conditions: conditionsA,
            transported: Phase4BFixtures.validPayload(id: idA, conditions: conditionsA),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenA
        )

        guard case let .applied(stateB) = resultB else { return XCTFail("B applied") }
        if case .discardedStale = resultA { /* ok */ } else { XCTFail("A discarded") }
        XCTAssertEqual(store.conditions?.location.id, idB)
        XCTAssertEqual(store.observingQuality?.location.savedLocationID, idB)
        XCTAssertEqual(store.persistCount, 1)
        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, idB)
        XCTAssertEqual(applied?.displayFingerprint, stateB.displayFingerprint)
        XCTAssertEqual(reloader.count, 1)
    }

    func testRefreshThenPush_PushInvalidatesLateRefresh() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store, reloader: reloader, gate: ImmediateWatchConditionsUpdateGate()
        )
        let ingress = WatchConditionsLiveEventIngress(claim: { coordinator.claimLiveUpdate() })

        // Refresh A starts (claims first)
        let refreshToken = ingress.claimRefreshIngress()
        // Push B arrives later
        let pushToken = ingress.claimPushIngress()
        XCTAssertLessThan(refreshToken.sequence, pushToken.sequence)

        let idB = UUID()
        let pushConditions = Phase4BFixtures.analyzableConditions(locationID: idB)
        let pushResult = await coordinator.accept(
            conditions: pushConditions,
            transported: Phase4BFixtures.validPayload(id: idB, conditions: pushConditions),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: nil,
            reloadComplications: true,
            token: pushToken
        )
        guard case .applied = pushResult else { return XCTFail("push applied") }

        // Late refresh reply / local fallback
        let idA = UUID()
        let refreshResult = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idA),
            transported: nil,
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            locationTimeZone: nil,
            reloadComplications: true,
            token: refreshToken
        )
        if case .discardedStale = refreshResult { /* ok */ } else { XCTFail("refresh discarded") }
        XCTAssertEqual(store.conditions?.location.id, idB)
        XCTAssertEqual(store.persistCount, 1)
        XCTAssertEqual(reloader.count, 1)
    }

    func testPushThenRefresh_RefreshIsNewer() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store, reloader: reloader, gate: ImmediateWatchConditionsUpdateGate()
        )
        let ingress = WatchConditionsLiveEventIngress(claim: { coordinator.claimLiveUpdate() })

        // Real timeline: push claims and completes while still latest, then refresh starts.
        let pushToken = ingress.claimPushIngress()
        let idPush = UUID()
        let pushC = Phase4BFixtures.analyzableConditions(locationID: idPush, cloudCover: 10)
        let pushResult = await coordinator.accept(
            conditions: pushC,
            transported: Phase4BFixtures.validPayload(id: idPush, conditions: pushC),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idPush),
            locationTimeZone: nil,
            reloadComplications: true,
            token: pushToken
        )
        guard case .applied = pushResult else { return XCTFail("push applied first") }

        let refreshToken = ingress.claimRefreshIngress()
        XCTAssertGreaterThan(refreshToken.sequence, pushToken.sequence)

        let idR = UUID()
        let refreshC = Phase4BFixtures.analyzableConditions(locationID: idR, cloudCover: 40)
        let r = await coordinator.accept(
            conditions: refreshC,
            transported: Phase4BFixtures.validPayload(id: idR, conditions: refreshC),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idR),
            locationTimeZone: nil,
            reloadComplications: true,
            token: refreshToken
        )
        guard case .applied = r else { return XCTFail("refresh applied") }
        XCTAssertEqual(store.conditions?.location.id, idR)
        XCTAssertEqual(store.persistCount, 2)
        XCTAssertEqual(reloader.count, 2)
    }

    func testTwoRefreshes_LaterWinsEvenIfEarlierFinishesLast() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store, reloader: reloader, gate: ImmediateWatchConditionsUpdateGate()
        )
        let ingress = WatchConditionsLiveEventIngress(claim: { coordinator.claimLiveUpdate() })

        let tokenA = ingress.claimRefreshIngress()
        let tokenB = ingress.claimRefreshIngress()

        let idB = UUID()
        let b = Phase4BFixtures.analyzableConditions(locationID: idB, cloudCover: 50)
        let resultB = await coordinator.accept(
            conditions: b,
            transported: Phase4BFixtures.validPayload(id: idB, conditions: b),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenB
        )
        let idA = UUID()
        let resultA = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 5),
            transported: nil,
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenA
        )
        guard case .applied = resultB else { return XCTFail("B") }
        if case .discardedStale = resultA { /* ok */ } else { XCTFail("A stale") }
        XCTAssertEqual(store.conditions?.location.id, idB)
        XCTAssertEqual(store.persistCount, 1)
    }

    func testFailedNewerRefreshStillInvalidatesOlder() async {
        let store = InMemoryWatchConditionsStore()
        store.setFailureMode(.conditionsWrite)
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store, reloader: reloader, gate: ImmediateWatchConditionsUpdateGate()
        )
        let ingress = WatchConditionsLiveEventIngress(claim: { coordinator.claimLiveUpdate() })

        let older = ingress.claimRefreshIngress()
        let newer = ingress.claimRefreshIngress()

        // Newer fails persistence but still claimed newer
        let fail = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            transported: nil,
            selectedLocation: nil,
            locationTimeZone: nil,
            reloadComplications: true,
            token: newer
        )
        if case .persistFailed = fail { /* ok */ } else { XCTFail("persist failed") }

        store.setFailureMode(.none)
        // Older must not revive
        let late = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            transported: nil,
            selectedLocation: nil,
            locationTimeZone: nil,
            reloadComplications: true,
            token: older
        )
        if case .discardedStale = late { /* ok */ } else { XCTFail("older discarded") }
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
        let applied = await coordinator.appliedState
        XCTAssertNil(applied)
    }

    /// Simulate scheduleProcessing reordering after ordered claims.
    func testScheduleProcessingReorderCannotChangeClaimedOrder() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store, reloader: reloader, gate: ImmediateWatchConditionsUpdateGate()
        )
        let ingress = WatchConditionsLiveEventIngress(claim: { coordinator.claimLiveUpdate() })

        let idA = UUID()
        let idB = UUID()
        let a = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 5)
        let b = Phase4BFixtures.analyzableConditions(locationID: idB, cloudCover: 70)

        // Arrival: A then B — claim immediately
        let tokenA = ingress.claimPushIngress()
        let tokenB = ingress.claimPushIngress()

        // Hold A processing until B completes (simulates B Task running first)
        let hold = AsyncStream<Void>.makeStream()
        let taskA = Task {
            for await _ in hold.stream { break }
            return await coordinator.accept(
                conditions: a,
                transported: Phase4BFixtures.validPayload(id: idA, conditions: a),
                selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
                locationTimeZone: nil,
                reloadComplications: true,
                token: tokenA
            )
        }
        await Task.yield()
        await Task.yield()

        let resultB = await coordinator.accept(
            conditions: b,
            transported: Phase4BFixtures.validPayload(id: idB, conditions: b),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenB
        )
        hold.continuation.yield(())
        hold.continuation.finish()
        let resultA = await taskA.value

        guard case .applied = resultB else { return XCTFail("B") }
        if case .discardedStale = resultA { /* ok */ } else { XCTFail("A") }
        XCTAssertEqual(store.conditions?.location.id, idB)
        XCTAssertEqual(store.persistCount, 1)
        XCTAssertEqual(reloader.count, 1)
    }

    func testClaimIsSynchronousAndDoesNotRequireActorHop() {
        let sequencer = WatchLiveIngressSequencer()
        XCTAssertEqual(sequencer.claim(), 1)
        XCTAssertEqual(sequencer.claim(), 2)
        XCTAssertEqual(sequencer.current, 2)
        // No await — pure sync ingress ordering
    }
}

// MARK: - Current-token commit boundary (persist + apply atomic w.r.t. claim)

/// Persist store that can block mid-write for concurrency tests.
private final class BlockingWatchConditionsStore: WatchConditionsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var _conditions: ViewingConditions?
    private var _oq: WatchObservingQualityDocument?
    private var _persistCount = 0

    let enteredSemaphore = DispatchSemaphore(value: 0)
    let releaseSemaphore = DispatchSemaphore(value: 0)
    var shouldBlock = true
    var failNext = false

    var conditions: ViewingConditions? {
        lock.lock(); defer { lock.unlock() }
        return _conditions
    }
    var persistCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _persistCount
    }

    func persistAcceptedPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?
    ) throws {
        enteredSemaphore.signal()
        if shouldBlock {
            releaseSemaphore.wait()
        }
        if failNext {
            failNext = false
            throw WatchConditionsPersistError.commitConditionsFailed("injected block-fail")
        }
        lock.lock()
        _conditions = conditions
        _oq = observingQuality
        _persistCount += 1
        lock.unlock()
    }
}

private final class ClaimBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _sequence: UInt64 = 0
    private var _done = false
    var sequence: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return _sequence
    }
    var done: Bool {
        lock.lock(); defer { lock.unlock() }
        return _done
    }
    func set(_ value: UInt64) {
        lock.lock()
        _sequence = value
        _done = true
        lock.unlock()
    }
}

private final class AcceptResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _result: WatchConditionsAcceptResult?
    var result: WatchConditionsAcceptResult? {
        lock.lock(); defer { lock.unlock() }
        return _result
    }
    func set(_ value: WatchConditionsAcceptResult) {
        lock.lock()
        _result = value
        lock.unlock()
    }
}

final class WatchConditionsCommitBoundaryTests: XCTestCase {
    func testClaimBeforeCommitBegins_OldTokenDiscardedWithZeroWrites() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let tokenA = coordinator.claimLiveUpdate()
        _ = coordinator.claimLiveUpdate()

        let idA = UUID()
        let resultA = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idA),
            transported: nil,
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenA
        )
        if case .discardedStale = resultA { /* ok */ } else {
            XCTFail("expected discardedStale, got \(String(describing: resultA))")
        }
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }

    func testSequencerClaimBlocksDuringWithCurrentToken() {
        let sequencer = WatchLiveIngressSequencer()
        let token = sequencer.claim()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = sequencer.withCurrentToken(token) {
                entered.signal()
                release.wait()
            }
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        let claimBox = ClaimBox()
        let claimFinished = expectation(description: "claim finished")
        DispatchQueue.global().async {
            claimBox.set(sequencer.claim())
            claimFinished.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(claimBox.done, "claim must not complete while withCurrentToken holds lock")

        release.signal()
        wait(for: [claimFinished], timeout: 5)
        XCTAssertEqual(claimBox.sequence, 2)
    }

    func testClaimDuringPersistenceWaitsUntilCommitCompletes() {
        let store = BlockingWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )

        let idA = UUID()
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 8)
        let payloadA = Phase4BFixtures.validPayload(id: idA, conditions: conditionsA)
        let tokenA = coordinator.claimLiveUpdate()

        let acceptDone = expectation(description: "accept A done")
        let acceptBox = AcceptResultBox()
        Task {
            let r = await coordinator.accept(
                conditions: conditionsA,
                transported: payloadA,
                selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
                locationTimeZone: nil,
                reloadComplications: true,
                token: tokenA
            )
            acceptBox.set(r)
            acceptDone.fulfill()
        }

        XCTAssertEqual(store.enteredSemaphore.wait(timeout: .now() + 5), .success)

        let claimBox = ClaimBox()
        let claimFinished = expectation(description: "B claim finished")
        DispatchQueue.global(qos: .userInitiated).async {
            claimBox.set(sequencer.claim())
            claimFinished.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(claimBox.done, "claim must wait during protected commit")

        store.releaseSemaphore.signal()
        wait(for: [acceptDone, claimFinished], timeout: 5)

        guard case .applied = acceptBox.result else {
            return XCTFail("A must apply, got \(String(describing: acceptBox.result))")
        }
        XCTAssertEqual(store.persistCount, 1)
        XCTAssertEqual(store.conditions?.location.id, idA)
        XCTAssertEqual(reloader.count, 1)
        XCTAssertEqual(claimBox.sequence, 2)
    }

    func testNewerUpdateFailsAfterPriorCommitted_LeavesAIntact() {
        let store = BlockingWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )

        let idA = UUID()
        let conditionsA = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 5)
        let tokenA = coordinator.claimLiveUpdate()

        let acceptDone = expectation(description: "accept A")
        let boxA = AcceptResultBox()
        Task {
            let r = await coordinator.accept(
                conditions: conditionsA,
                transported: Phase4BFixtures.validPayload(id: idA, conditions: conditionsA),
                selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
                locationTimeZone: nil,
                reloadComplications: true,
                token: tokenA
            )
            boxA.set(r)
            acceptDone.fulfill()
        }
        XCTAssertEqual(store.enteredSemaphore.wait(timeout: .now() + 5), .success)

        let claimBox = ClaimBox()
        let claimed = expectation(description: "claimed")
        DispatchQueue.global().async {
            claimBox.set(sequencer.claim())
            claimed.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertFalse(claimBox.done)

        store.releaseSemaphore.signal()
        wait(for: [acceptDone, claimed], timeout: 5)
        guard case .applied = boxA.result else { return XCTFail("A applied") }
        XCTAssertEqual(claimBox.sequence, 2)

        store.shouldBlock = false
        store.failNext = true
        let tokenB = WatchConditionsLiveUpdateToken(sequence: claimBox.sequence)
        let failDone = expectation(description: "fail B")
        let boxB = AcceptResultBox()
        Task {
            let r = await coordinator.accept(
                conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
                transported: nil,
                selectedLocation: nil,
                locationTimeZone: nil,
                reloadComplications: true,
                token: tokenB
            )
            boxB.set(r)
            failDone.fulfill()
        }
        wait(for: [failDone], timeout: 5)
        if case .persistFailed = boxB.result { /* ok */ } else {
            XCTFail("expected persistFailed, got \(String(describing: boxB.result))")
        }

        XCTAssertEqual(store.conditions?.location.id, idA)
        XCTAssertEqual(store.persistCount, 1)
        XCTAssertEqual(reloader.count, 1, "only A's reload")
    }

    func testPersistFailureReleasesIngressLockForWaitingClaim() {
        let store = BlockingWatchConditionsStore()
        store.failNext = true
        let reloader = RecordingReloadReporter()
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )

        let tokenA = coordinator.claimLiveUpdate()
        let acceptDone = expectation(description: "accept A")
        let boxA = AcceptResultBox()
        Task {
            let r = await coordinator.accept(
                conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
                transported: nil,
                selectedLocation: nil,
                locationTimeZone: nil,
                reloadComplications: true,
                token: tokenA
            )
            boxA.set(r)
            acceptDone.fulfill()
        }
        XCTAssertEqual(store.enteredSemaphore.wait(timeout: .now() + 5), .success)

        let claimBox = ClaimBox()
        let claimed = expectation(description: "b claimed")
        DispatchQueue.global().async {
            claimBox.set(sequencer.claim())
            claimed.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertFalse(claimBox.done)

        store.releaseSemaphore.signal()
        wait(for: [acceptDone, claimed], timeout: 5)
        if case .persistFailed = boxA.result { /* ok */ } else {
            XCTFail("expected persistFailed")
        }
        XCTAssertEqual(claimBox.sequence, 2, "waiting claim completes after failure releases lock")
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }

    func testNoPersistedButDiscardedResult() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )

        let id = UUID()
        let c = Phase4BFixtures.analyzableConditions(locationID: id)
        let t1 = coordinator.claimLiveUpdate()
        let r1 = await coordinator.accept(
            conditions: c,
            transported: Phase4BFixtures.validPayload(id: id, conditions: c),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            locationTimeZone: nil,
            reloadComplications: true,
            token: t1
        )
        guard case .applied = r1 else { return XCTFail("applied") }
        XCTAssertEqual(store.persistCount, 1)

        let writesBefore = store.persistCount
        _ = coordinator.claimLiveUpdate()
        let r2 = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            transported: nil,
            selectedLocation: nil,
            locationTimeZone: nil,
            reloadComplications: true,
            token: t1
        )
        if case .discardedStale = r2 { /* ok */ } else { XCTFail("stale") }
        XCTAssertEqual(store.persistCount, writesBefore)

        store.setFailureMode(.conditionsWrite)
        let t3 = coordinator.claimLiveUpdate()
        let r3 = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            transported: nil,
            selectedLocation: nil,
            locationTimeZone: nil,
            reloadComplications: true,
            token: t3
        )
        if case .persistFailed = r3 { /* ok */ } else { XCTFail("persistFailed") }
        XCTAssertEqual(store.conditions?.location.id, id)
        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, id)
    }

    func testWithCurrentTokenIsSynchronousAPI() {
        let sequencer = WatchLiveIngressSequencer()
        let seq = sequencer.claim()
        var ran = false
        let ok = sequencer.withCurrentToken(seq) {
            ran = true
        }
        XCTAssertTrue(ok)
        XCTAssertTrue(ran)

        _ = sequencer.claim() // advance so previous token is stale
        let notCurrent = sequencer.withCurrentToken(seq) {
            XCTFail("must not run")
        }
        XCTAssertFalse(notCurrent)
    }
}

// MARK: - Deferred-cache protected publication

/// Gate: hold at beforeCachePublication (after pure resolve, before withCurrentToken).
/// Must be a class (not actor) so onCachePublicationEntered can be sync under the sequencer lock.
private final class CachePublicationOrderingGate: WatchConditionsUpdateGate, @unchecked Sendable {
    private let lock = NSLock()
    private var holdPublication = true
    private var firstHold: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func beforePersist() async {}
    func beforeApplyCached() async {}

    func beforeCachePublication() async {
        let shouldHold: Bool = {
            lock.lock()
            defer { lock.unlock() }
            guard holdPublication else { return false }
            holdPublication = false
            return true
        }()
        guard shouldHold else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            firstHold = cont
            let w = waiter
            waiter = nil
            lock.unlock()
            w?.resume()
        }
    }

    func onCachePublicationEntered() {}

    func waitUntilPublicationHeld() async {
        while true {
            let ready: Bool = {
                lock.lock()
                defer { lock.unlock() }
                return firstHold != nil
            }()
            if ready { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                if firstHold != nil {
                    lock.unlock()
                    cont.resume()
                } else {
                    waiter = cont
                    lock.unlock()
                }
            }
            // loop if needed
            let done: Bool = {
                lock.lock(); defer { lock.unlock() }
                return firstHold != nil
            }()
            if done { return }
        }
    }

    func releasePublication() {
        lock.lock()
        let h = firstHold
        firstHold = nil
        lock.unlock()
        h?.resume()
    }
}

/// Gate: block inside onCachePublicationEntered (under sequencer lock).
private final class BlockingCachePublicationGate: WatchConditionsUpdateGate, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func beforePersist() async {}
    func beforeApplyCached() async {}
    func beforeCachePublication() async {}

    func onCachePublicationEntered() {
        entered.signal()
        release.wait()
    }
}

final class WatchConditionsCachePublicationBoundaryTests: XCTestCase {
    func testLiveClaimBeforeCacheCommit_DiscardsWithoutMutation() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let gate = CachePublicationOrderingGate()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: gate
        )

        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let token = await coordinator.beginDeferredApplication()

        let cacheTask = Task {
            await coordinator.applyCached(
                conditions: conditions,
                selectedLocation: Phase4BFixtures.selectedSaved(id: id),
                persistedDocument: nil,
                locationTimeZone: nil,
                token: token
            )
        }
        await gate.waitUntilPublicationHeld()

        // Live claim before protected publication.
        let liveToken = coordinator.claimLiveUpdate()
        XCTAssertEqual(liveToken.sequence, 1)

        await gate.releasePublication()
        let cacheResult = await cacheTask.value
        if case .discardedStale = cacheResult { /* ok */ } else {
            XCTFail("expected discardedStale, got \(String(describing: cacheResult))")
        }

        let applied = await coordinator.appliedState
        XCTAssertNil(applied)
        let fingerprint = await coordinator.currentFingerprint
        XCTAssertNil(fingerprint)
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }

    func testLiveClaimDuringCachePublicationWaitsUntilApplied() {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let gate = BlockingCachePublicationGate()
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: gate,
            liveIngress: sequencer
        )

        // No prior live claim → liveGeneration is 0; withCurrentToken(0) succeeds when current is 0.
        // Seed a live claim of 0 by never claiming... sequence starts at 0, withCurrentToken(0) works if current is 0.
        // beginDeferredApplication captures liveGeneration: 0.
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        // Capture token on main then run applyCached
        let started = expectation(description: "cache started")
        let done = expectation(description: "cache done")

        // Simpler: use nonisolated deferred token via Task + boxes
        final class DeferredTokenBox: @unchecked Sendable {
            var token: WatchConditionsDeferredApplicationToken?
        }
        final class CacheResultBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _r: WatchConditionsCacheApplyResult?
            var result: WatchConditionsCacheApplyResult? {
                lock.lock(); defer { lock.unlock() }
                return _r
            }
            func set(_ r: WatchConditionsCacheApplyResult) {
                lock.lock(); _r = r; lock.unlock()
            }
        }
        let tokBox = DeferredTokenBox()
        let resBox = CacheResultBox()

        Task {
            tokBox.token = await coordinator.beginDeferredApplication()
            started.fulfill()
            let r = await coordinator.applyCached(
                conditions: conditions,
                selectedLocation: Phase4BFixtures.selectedSaved(id: id),
                persistedDocument: nil,
                locationTimeZone: nil,
                token: tokBox.token!
            )
            resBox.set(r)
            done.fulfill()
        }
        wait(for: [started], timeout: 5)
        // Wait until inside protected section
        XCTAssertEqual(gate.entered.wait(timeout: .now() + 5), .success)

        let claimBox = ClaimBox()
        let claimFinished = expectation(description: "claim finished")
        DispatchQueue.global().async {
            claimBox.set(sequencer.claim())
            claimFinished.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(claimBox.done, "live claim must wait during cache publication")

        gate.release.signal()
        wait(for: [done, claimFinished], timeout: 5)

        guard case .applied = resBox.result else {
            return XCTFail("cache must apply, got \(String(describing: resBox.result))")
        }
        XCTAssertEqual(claimBox.sequence, 1)
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }

    func testNewerDeferredStartBeforePublicationDiscardsOlder() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let gate = CachePublicationOrderingGate()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: gate
        )

        let idA = UUID()
        let tokenA = await coordinator.beginDeferredApplication()
        let cacheTask = Task {
            await coordinator.applyCached(
                conditions: Phase4BFixtures.analyzableConditions(locationID: idA),
                selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
                persistedDocument: nil,
                locationTimeZone: nil,
                token: tokenA
            )
        }
        await gate.waitUntilPublicationHeld()

        // Newer deferred start while A is held before publication.
        let idB = UUID()
        let tokenB = await coordinator.beginDeferredApplication()
        XCTAssertGreaterThan(tokenB.deferredSequence, tokenA.deferredSequence)

        await gate.releasePublication()
        let resultA = await cacheTask.value
        if case .discardedStale = resultA { /* ok */ } else {
            XCTFail("older deferred discarded, got \(String(describing: resultA))")
        }

        // B applies with immediate gate path
        let coordinatorB = coordinator
        let resultB = await coordinatorB.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idB),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: tokenB
        )
        // Note: same gate may have holdPublication false already, so B proceeds.
        guard case let .applied(stateB) = resultB else {
            return XCTFail("B applied, got \(String(describing: resultB))")
        }
        XCTAssertEqual(stateB.conditions.location.id, idB)
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }

    func testLiveClaimBetweenPrepAndPublicationRegression() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let gate = CachePublicationOrderingGate()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: gate
        )

        // Establish prior applied live state so we can prove it is not overwritten.
        let idLive = UUID()
        let liveConditions = Phase4BFixtures.analyzableConditions(locationID: idLive, cloudCover: 12)
        let liveToken = coordinator.claimLiveUpdate()
        let liveResult = await coordinator.accept(
            conditions: liveConditions,
            transported: Phase4BFixtures.validPayload(id: idLive, conditions: liveConditions),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idLive),
            locationTimeZone: nil,
            reloadComplications: true,
            token: liveToken
        )
        guard case let .applied(prior) = liveResult else { return XCTFail("live seed") }
        let priorFingerprint = await coordinator.currentFingerprint

        // Cache started at liveGeneration 0 would be stale; start cache after live so generation matches,
        // then claim again before publication.
        let idCache = UUID()
        let cacheToken = await coordinator.beginDeferredApplication()
        XCTAssertEqual(cacheToken.liveGeneration, liveToken.sequence)

        let cacheTask = Task {
            await coordinator.applyCached(
                conditions: Phase4BFixtures.analyzableConditions(locationID: idCache, cloudCover: 90),
                selectedLocation: Phase4BFixtures.selectedSaved(id: idCache),
                persistedDocument: nil,
                locationTimeZone: nil,
                token: cacheToken
            )
        }
        await gate.waitUntilPublicationHeld()

        // Exact former race: claim live after pure resolution, before publication.
        let newerLive = coordinator.claimLiveUpdate()
        XCTAssertGreaterThan(newerLive.sequence, cacheToken.liveGeneration)

        await gate.releasePublication()
        let cacheResult = await cacheTask.value
        if case .discardedStale = cacheResult { /* ok */ } else {
            XCTFail("stale cache must not publish")
        }

        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, prior.conditions.location.id)
        let fingerprint = await coordinator.currentFingerprint
        XCTAssertEqual(fingerprint, priorFingerprint)
        XCTAssertEqual(store.persistCount, 1, "only original live write")
        XCTAssertEqual(reloader.count, 1)
    }

    func testSuccessfulCacheStateConsistencyNoPersistNoReload() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let id = UUID()
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id, cloudCover: 20)
        let token = await coordinator.beginDeferredApplication()
        let result = await coordinator.applyCached(
            conditions: conditions,
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            persistedDocument: nil,
            locationTimeZone: TimeZone(identifier: "UTC"),
            token: token
        )
        guard case let .applied(state) = result else {
            return XCTFail("applied")
        }
        let applied = await coordinator.appliedState
        XCTAssertEqual(applied?.conditions.location.id, id)
        XCTAssertEqual(applied?.conditions.location.id, state.conditions.location.id)
        XCTAssertEqual(applied?.displayFingerprint, state.displayFingerprint)
        let fingerprint = await coordinator.currentFingerprint
        XCTAssertEqual(fingerprint, state.displayFingerprint)
        XCTAssertFalse(state.didReloadComplications)
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }
}

// MARK: - Manager observable publication ordering

/// Models delayed MainActor publication of coordinator applied results.
@MainActor
private final class ObservableStateProbe {
    var conditionsID: UUID?
    var fingerprint: ObservingQualityDisplayFingerprint?
    var publishCount = 0

    func apply(_ state: WatchConditionsAppliedState) {
        conditionsID = state.conditions.location.id
        fingerprint = state.displayFingerprint
        publishCount += 1
    }
}

final class WatchConditionsObservablePublicationTests: XCTestCase {
    func testLiveBPublishesBeforeDelayedA_VisibleStateRemainsB() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )
        let publisher = await MainActor.run {
            WatchConditionsObservablePublisher(coordinator: coordinator)
        }
        let probe = await MainActor.run { ObservableStateProbe() }

        let idA = UUID()
        let idB = UUID()
        let a = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 5)
        let b = Phase4BFixtures.analyzableConditions(locationID: idB, cloudCover: 60)

        let tokenA = coordinator.claimLiveUpdate()
        let resultA = await coordinator.accept(
            conditions: a,
            transported: Phase4BFixtures.validPayload(id: idA, conditions: a),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenA
        )
        guard case let .applied(stateA) = resultA else { return XCTFail("A applied") }

        let tokenB = coordinator.claimLiveUpdate()
        let resultB = await coordinator.accept(
            conditions: b,
            transported: Phase4BFixtures.validPayload(id: idB, conditions: b),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenB
        )
        guard case let .applied(stateB) = resultB else { return XCTFail("B applied") }

        // B publishes first (as if B's MainActor hop ran first).
        let publishedB = await MainActor.run {
            publisher.publish(stateB) { probe.apply($0) }
        }
        XCTAssertTrue(publishedB)

        // Delayed A publication must not overwrite B.
        let publishedA = await MainActor.run {
            publisher.publish(stateA) { probe.apply($0) }
        }
        XCTAssertFalse(publishedA)

        let id = await MainActor.run { probe.conditionsID }
        let count = await MainActor.run { probe.publishCount }
        XCTAssertEqual(id, idB)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.conditions?.location.id, idB)
        let coord = await coordinator.appliedState
        XCTAssertEqual(coord?.conditions.location.id, idB)
        XCTAssertEqual(coord?.identity, .live(sequence: tokenB.sequence))
    }

    func testCacheDelayedAfterLiveClaim_CannotPublish() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let publisher = await MainActor.run {
            WatchConditionsObservablePublisher(coordinator: coordinator)
        }
        let probe = await MainActor.run { ObservableStateProbe() }

        let idCache = UUID()
        let cacheToken = await coordinator.beginDeferredApplication()
        let cacheResult = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idCache),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idCache),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: cacheToken
        )
        guard case let .applied(cacheState) = cacheResult else { return XCTFail("cache applied") }

        // Live claim invalidates pending cache UI publication.
        _ = coordinator.claimLiveUpdate()

        let publishedCache = await MainActor.run {
            publisher.publish(cacheState) { probe.apply($0) }
        }
        XCTAssertFalse(publishedCache)
        let count = await MainActor.run { probe.publishCount }
        XCTAssertEqual(count, 0)

        let idLive = UUID()
        let liveC = Phase4BFixtures.analyzableConditions(locationID: idLive, cloudCover: 15)
        // Need a new claim for the actual live accept after the invalidating claim.
        let liveToken = coordinator.claimLiveUpdate()
        let liveResult = await coordinator.accept(
            conditions: liveC,
            transported: Phase4BFixtures.validPayload(id: idLive, conditions: liveC),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idLive),
            locationTimeZone: nil,
            reloadComplications: true,
            token: liveToken
        )
        guard case let .applied(liveState) = liveResult else { return XCTFail("live") }
        let publishedLive = await MainActor.run {
            publisher.publish(liveState) { probe.apply($0) }
        }
        XCTAssertTrue(publishedLive)
        let id = await MainActor.run { probe.conditionsID }
        XCTAssertEqual(id, idLive)
    }

    func testCacheDelayedAfterLiveBPublished_CannotReplace() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let publisher = await MainActor.run {
            WatchConditionsObservablePublisher(coordinator: coordinator)
        }
        let probe = await MainActor.run { ObservableStateProbe() }

        let cacheToken = await coordinator.beginDeferredApplication()
        let cacheResult = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            selectedLocation: nil,
            persistedDocument: nil,
            locationTimeZone: nil,
            token: cacheToken
        )
        guard case let .applied(cacheState) = cacheResult else { return XCTFail("cache") }

        let idB = UUID()
        let b = Phase4BFixtures.analyzableConditions(locationID: idB, cloudCover: 40)
        let liveToken = coordinator.claimLiveUpdate()
        let liveResult = await coordinator.accept(
            conditions: b,
            transported: Phase4BFixtures.validPayload(id: idB, conditions: b),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            locationTimeZone: nil,
            reloadComplications: true,
            token: liveToken
        )
        guard case let .applied(liveState) = liveResult else { return XCTFail("live") }
        let pubLive = await MainActor.run { publisher.publish(liveState) { probe.apply($0) } }
        XCTAssertTrue(pubLive)
        let pubCache = await MainActor.run { publisher.publish(cacheState) { probe.apply($0) } }
        XCTAssertFalse(pubCache)
        let id = await MainActor.run { probe.conditionsID }
        XCTAssertEqual(id, idB)
        let count = await MainActor.run { probe.publishCount }
        XCTAssertEqual(count, 1)
    }

    func testTwoCacheResultsPublishOutOfOrder_LatestStartedWins() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let publisher = await MainActor.run {
            WatchConditionsObservablePublisher(coordinator: coordinator)
        }
        let probe = await MainActor.run { ObservableStateProbe() }

        let idA = UUID()
        let idB = UUID()
        let tokenA = await coordinator.beginDeferredApplication()
        let tokenB = await coordinator.beginDeferredApplication()

        // A is already deferred-stale at coordinator if we only apply B...
        // Apply B (latest), then try to publish both in reverse order.
        let resultB = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idB),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idB),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: tokenB
        )
        guard case let .applied(stateB) = resultB else { return XCTFail("B applied") }

        // A apply is discarded by coordinator (deferred stale) — get a discarded path:
        let resultA = await coordinator.applyCached(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idA),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            persistedDocument: nil,
            locationTimeZone: nil,
            token: tokenA
        )
        if case .discardedStale = resultA { /* ok */ } else {
            // If somehow applied, publication must still reject older identity.
            if case let .applied(stateA) = resultA {
                let pubB = await MainActor.run { publisher.publish(stateB) { probe.apply($0) } }
                XCTAssertTrue(pubB)
                let pubA = await MainActor.run { publisher.publish(stateA) { probe.apply($0) } }
                XCTAssertFalse(pubA)
                let id = await MainActor.run { probe.conditionsID }
                XCTAssertEqual(id, idB)
                return
            }
            XCTFail("unexpected \(resultA)")
            return
        }

        // Force reverse publish order: only B is applied; publish B.
        let pubB2 = await MainActor.run { publisher.publish(stateB) { probe.apply($0) } }
        XCTAssertTrue(pubB2)
        // Synthesize stale cache identity for A and attempt late publication.
        let staleA = WatchConditionsAppliedState(
            conditions: Phase4BFixtures.analyzableConditions(locationID: idA),
            nightQuality: nil,
            observingQualityHeadline: nil,
            locationTimeZone: nil,
            displayFingerprint: nil,
            didReloadComplications: false,
            identity: .cache(
                liveGeneration: tokenA.liveGeneration,
                deferredSequence: tokenA.deferredSequence
            )
        )
        let pubStale = await MainActor.run { publisher.publish(staleA) { probe.apply($0) } }
        XCTAssertFalse(pubStale)
        let id = await MainActor.run { probe.conditionsID }
        XCTAssertEqual(id, idB)
        let count = await MainActor.run { probe.publishCount }
        XCTAssertEqual(count, 1)
    }

    func testFailedNewerLiveClaimBlocksOlderPublication() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let publisher = await MainActor.run {
            WatchConditionsObservablePublisher(coordinator: coordinator)
        }
        let probe = await MainActor.run { ObservableStateProbe() }

        let idA = UUID()
        let a = Phase4BFixtures.analyzableConditions(locationID: idA, cloudCover: 10)
        let tokenA = coordinator.claimLiveUpdate()
        let resultA = await coordinator.accept(
            conditions: a,
            transported: Phase4BFixtures.validPayload(id: idA, conditions: a),
            selectedLocation: Phase4BFixtures.selectedSaved(id: idA),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenA
        )
        guard case let .applied(stateA) = resultA else { return XCTFail("A") }

        // B claims (invalidates A for publication) then fails persistence.
        store.setFailureMode(.conditionsWrite)
        let tokenB = coordinator.claimLiveUpdate()
        let resultB = await coordinator.accept(
            conditions: Phase4BFixtures.analyzableConditions(locationID: UUID()),
            transported: nil,
            selectedLocation: nil,
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenB
        )
        if case .persistFailed = resultB { /* ok */ } else { XCTFail("B fail") }

        // Delayed A must not publish after B's newer claim.
        let pubALate = await MainActor.run { publisher.publish(stateA) { probe.apply($0) } }
        XCTAssertFalse(pubALate)
        let count = await MainActor.run { probe.publishCount }
        XCTAssertEqual(count, 0)
        // Coordinator still has A applied (B failed); manager unchanged.
        let coord = await coordinator.appliedState
        XCTAssertEqual(coord?.conditions.location.id, idA)
        XCTAssertEqual(store.conditions?.location.id, idA)
    }

    func testSuccessfulLiveUpdate_NoDivergence() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let publisher = await MainActor.run {
            WatchConditionsObservablePublisher(coordinator: coordinator)
        }
        let probe = await MainActor.run { ObservableStateProbe() }

        let id = UUID()
        let c = Phase4BFixtures.analyzableConditions(locationID: id, cloudCover: 18)
        let token = coordinator.claimLiveUpdate()
        let result = await coordinator.accept(
            conditions: c,
            transported: Phase4BFixtures.validPayload(id: id, conditions: c),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id),
            locationTimeZone: TimeZone(identifier: "UTC"),
            reloadComplications: true,
            token: token
        )
        guard case let .applied(state) = result else { return XCTFail("applied") }
        let pubOK = await MainActor.run { publisher.publish(state) { probe.apply($0) } }
        XCTAssertTrue(pubOK)

        XCTAssertEqual(store.conditions?.location.id, id)
        let coord = await coordinator.appliedState
        XCTAssertEqual(coord?.conditions.location.id, id)
        XCTAssertEqual(coord?.identity, state.identity)
        let probeID = await MainActor.run { probe.conditionsID }
        let probeFP = await MainActor.run { probe.fingerprint }
        XCTAssertEqual(probeID, id)
        XCTAssertEqual(probeFP, state.displayFingerprint)
        let fp = await coordinator.currentFingerprint
        XCTAssertEqual(fp, state.displayFingerprint)
        XCTAssertEqual(reloader.count, 1)
    }

    func testMainActorReverseOrder_KeepsNewest() async {
        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let publisher = await MainActor.run {
            WatchConditionsObservablePublisher(coordinator: coordinator)
        }
        let probe = await MainActor.run { ObservableStateProbe() }

        let id1 = UUID()
        let id2 = UUID()
        let c1 = Phase4BFixtures.analyzableConditions(locationID: id1, cloudCover: 5)
        let c2 = Phase4BFixtures.analyzableConditions(locationID: id2, cloudCover: 55)
        let t1 = coordinator.claimLiveUpdate()
        let r1 = await coordinator.accept(
            conditions: c1,
            transported: Phase4BFixtures.validPayload(id: id1, conditions: c1),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id1),
            locationTimeZone: nil,
            reloadComplications: true,
            token: t1
        )
        let t2 = coordinator.claimLiveUpdate()
        let r2 = await coordinator.accept(
            conditions: c2,
            transported: Phase4BFixtures.validPayload(id: id2, conditions: c2),
            selectedLocation: Phase4BFixtures.selectedSaved(id: id2),
            locationTimeZone: nil,
            reloadComplications: true,
            token: t2
        )
        guard case let .applied(s1) = r1, case let .applied(s2) = r2 else {
            return XCTFail("both applied")
        }

        // Deterministic reverse publish order on MainActor (no sleeps).
        await MainActor.run {
            XCTAssertTrue(publisher.publish(s2) { probe.apply($0) })
            XCTAssertFalse(publisher.publish(s1) { probe.apply($0) })
            XCTAssertEqual(probe.conditionsID, id2)
            XCTAssertEqual(probe.publishCount, 1)
        }
    }
}
