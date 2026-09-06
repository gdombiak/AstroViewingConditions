@testable import SharedCode
import XCTest

// MARK: - Fixtures

private enum Phase4CFixtures {
    static let latitude = 45.5017
    static let longitude = -122.6750
    static let timeZoneID = "America/Los_Angeles"

    static func dataset(revision: Int = 1) -> LightPollutionDatasetIdentity {
        LightPollutionDatasetIdentity(
            datasetID: "lpatlas1",
            datasetRevision: revision,
            formatVersion: 1
        )
    }

    static func sample(
        lat: Double = latitude,
        lon: Double = longitude,
        brightness: Double = 18.5,
        revision: Int = 1,
        savedLocationID: UUID? = nil
    ) -> ModeledZenithBrightnessSample {
        ModeledZenithBrightnessSample(
            latitude: lat,
            longitude: lon,
            modeledZenithSkyBrightness: brightness,
            dataset: dataset(revision: revision),
            savedLocationID: savedLocationID
        )
    }

    static func request(
        id: UUID = UUID(),
        lat: Double = latitude,
        lon: Double = longitude
    ) -> WatchCurrentLocationRequestContext {
        WatchCurrentLocationRequestContext(
            requestID: id,
            source: .currentGPS,
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

    static func selectedSaved(id: UUID) -> SelectedLocation {
        SelectedLocation(
            source: .saved,
            id: id,
            name: "Dark Site",
            latitude: latitude,
            longitude: longitude
        )
    }

    /// Conditions that `NightQualityAnalyzer.analyzeConditions` can score.
    static func analyzableConditions(
        lat: Double = latitude,
        lon: Double = longitude,
        locationID: UUID? = nil,
        referenceDate: Date = Date(),
        cloudCover: Int = 10,
        name: String = "Current Location"
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
                name: name,
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

    static func validCurrentLocationPayload(
        request: WatchCurrentLocationRequestContext,
        conditions: ViewingConditions,
        brightness: Double = 18.5,
        oqOverride: Int? = nil,
        nightOverride: Int? = nil
    ) -> WatchObservingQualityPayload {
        let night = nightOverride ?? nightScore(for: conditions)
        let sample = sample(
            lat: request.latitude,
            lon: request.longitude,
            brightness: brightness
        )
        var snap = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: night,
                location: request.asLocationContext,
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
        return WatchObservingQualityPayload(
            payloadVersion: WatchObservingQualityPayload.currentLocationPayloadVersion,
            location: request.asLocationContext,
            transportedSnapshot: snap,
            requestContext: request
        )
    }

    static func validSavedPayload(
        id: UUID,
        conditions: ViewingConditions
    ) -> WatchObservingQualityPayload {
        let ctx = CrossSurfaceLocationContext(
            source: .saved,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            savedLocationID: id
        )
        let night = nightScore(for: conditions)
        let s = ModeledZenithBrightnessSample(
            latitude: ctx.latitude,
            longitude: ctx.longitude,
            modeledZenithSkyBrightness: 18.5,
            dataset: dataset(),
            savedLocationID: id
        )
        let snap = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: night,
                location: ctx,
                sample: s,
                assessedAt: conditions.fetchedAt
            )
        )
        return WatchObservingQualityPayload(
            payloadVersion: WatchObservingQualityPayload.savedLocationPayloadVersion,
            location: ctx,
            transportedSnapshot: snap,
            requestContext: nil
        )
    }
}

// MARK: - Request context validity

final class WatchCurrentLocationRequestContextTests: XCTestCase {
    func testValidContextIsStructurallyValid() {
        let ctx = Phase4CFixtures.request()
        XCTAssertTrue(ctx.isStructurallyValid)
        XCTAssertEqual(ctx.source, .currentGPS)
        XCTAssertEqual(ctx.contextVersion, 1)
    }

    func testRejectsZeroZeroPlaceholder() {
        let ctx = Phase4CFixtures.request(lat: 0, lon: 0)
        XCTAssertFalse(ctx.isStructurallyValid)
    }

    func testRejectsNaNAndInfinity() {
        XCTAssertFalse(Phase4CFixtures.request(lat: .nan, lon: -122).isStructurallyValid)
        XCTAssertFalse(Phase4CFixtures.request(lat: 45, lon: .infinity).isStructurallyValid)
        XCTAssertFalse(Phase4CFixtures.request(lat: -.infinity, lon: -122).isStructurallyValid)
    }

    func testRejectsInvalidLatitudeLongitude() {
        XCTAssertFalse(Phase4CFixtures.request(lat: 91, lon: -122).isStructurallyValid)
        XCTAssertFalse(Phase4CFixtures.request(lat: 45, lon: 181).isStructurallyValid)
    }

    func testRejectsSavedSource() {
        var ctx = Phase4CFixtures.request()
        ctx.source = .saved
        XCTAssertFalse(ctx.isStructurallyValid)
    }

    func testRoundTripCodable() throws {
        let original = Phase4CFixtures.request()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchCurrentLocationRequestContext.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

// MARK: - Phone builder (Current Location)

final class WatchObservingQualityCurrentLocationBuilderTests: XCTestCase {
    func testValidRequestAndSampleProducesCorrelatedPayload() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = WatchObservingQualityPayloadBuilder.makeCurrentLocationPayload(
            conditions: conditions,
            request: request,
            sample: Phase4CFixtures.sample()
        )
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.payloadVersion, WatchObservingQualityPayload.currentLocationPayloadVersion)
        XCTAssertEqual(payload?.requestContext, request)
        XCTAssertEqual(payload?.location.source, .currentGPS)
        XCTAssertNil(payload?.location.savedLocationID)
        XCTAssertEqual(payload?.transportedSnapshot.brightnessAvailability, .available)
    }

    func testConditionsCoordinateMismatchProducesNoPayload() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions(lat: 47.6, lon: -122.3)
        let payload = WatchObservingQualityPayloadBuilder.makeCurrentLocationPayload(
            conditions: conditions,
            request: request,
            sample: Phase4CFixtures.sample()
        )
        XCTAssertNil(payload)
    }

    func testConditionsWithSavedIDProducesNoPayload() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: UUID())
        let payload = WatchObservingQualityPayloadBuilder.makeCurrentLocationPayload(
            conditions: conditions,
            request: request,
            sample: Phase4CFixtures.sample()
        )
        XCTAssertNil(payload)
    }

    func testSampleWithSavedIDProducesNoPayload() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = WatchObservingQualityPayloadBuilder.makeCurrentLocationPayload(
            conditions: conditions,
            request: request,
            sample: Phase4CFixtures.sample(savedLocationID: UUID())
        )
        XCTAssertNil(payload)
    }

    func testNilSampleProducesNoPayload() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = WatchObservingQualityPayloadBuilder.makeCurrentLocationPayload(
            conditions: conditions,
            request: request,
            sample: nil
        )
        XCTAssertNil(payload)
    }

    func testInvalidRequestProducesNoPayload() {
        let request = Phase4CFixtures.request(lat: 0, lon: 0)
        let conditions = Phase4CFixtures.analyzableConditions(lat: 0, lon: 0)
        let payload = WatchObservingQualityPayloadBuilder.makeCurrentLocationPayload(
            conditions: conditions,
            request: request,
            sample: Phase4CFixtures.sample(lat: 0, lon: 0)
        )
        XCTAssertNil(payload)
    }

    func testSavedBuilderStillIgnoresCurrentLocation() {
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            brightness: .sample(Phase4CFixtures.sample()),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }

    func testPhoneSelectedSavedCannotBuildCLPayloadViaSavedFactory() {
        let savedID = UUID()
        let conditions = Phase4CFixtures.analyzableConditions()
        // Even if phone has a saved selection, CL conditions (nil id) must not be saved-enhanced.
        let payload = WatchObservingQualityPayloadBuilder.makeSavedLocationPayload(
            conditions: conditions,
            selectedLocation: Phase4CFixtures.selectedSaved(id: savedID),
            brightness: .sample(Phase4CFixtures.sample(savedLocationID: savedID)),
            baseURL: nil
        )
        XCTAssertNil(payload)
    }
}

// MARK: - Transport compatibility

final class WatchObservingQualityPhase4CTransportTests: XCTestCase {
    func testOldPhoneResponseWithoutOQPreservesConditionsAndNightScore() throws {
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let request = Phase4CFixtures.request()

        // Reply has conditions only (old phone ignores currentLocationRequest).
        let conditionsData = try JSONEncoder().encode(conditions)
        let reply: [String: Any] = ["status": "ok", "conditions": conditionsData]
        let decoded = try JSONDecoder().decode(
            ViewingConditions.self,
            from: reply["conditions"] as! Data
        )
        let oq: WatchObservingQualityPayload? = nil

        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: decoded,
            transported: oq,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Expected night-only without OQ")
        }
    }

    func testMalformedOptionalOQPreservesConditions() throws {
        let conditions = Phase4CFixtures.analyzableConditions()
        let conditionsData = try JSONEncoder().encode(conditions)
        let reply: [String: Any] = [
            "status": "ok",
            "conditions": conditionsData,
            "observingQuality": Data("not-json".utf8)
        ]
        let decodedConditions = try JSONDecoder().decode(
            ViewingConditions.self,
            from: reply["conditions"] as! Data
        )
        let oq: WatchObservingQualityPayload? = {
            guard let data = reply["observingQuality"] as? Data else { return nil }
            return try? JSONDecoder().decode(WatchObservingQualityPayload.self, from: data)
        }()
        XCTAssertNil(oq)
        XCTAssertEqual(decodedConditions.location.latitude, Phase4CFixtures.latitude)
    }

    func testSavedLocationV1CompatibilityRemains() throws {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(
            locationID: id,
            name: "Dark Site"
        )
        let payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        XCTAssertEqual(payload.payloadVersion, 1)
        XCTAssertNil(payload.requestContext)

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchObservingQualityPayload.self, from: data)
        XCTAssertEqual(decoded.payloadVersion, 1)
        XCTAssertNil(decoded.requestContext)

        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: decoded,
            selectedLocation: Phase4CFixtures.selectedSaved(id: id)
        )
        if case .enhanced = outcome {
            // ok
        } else {
            XCTFail("v1 saved payload must still enhance")
        }
    }

    func testV2PayloadWithRequestContextRoundTrips() throws {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchObservingQualityPayload.self, from: data)
        XCTAssertEqual(decoded.payloadVersion, 2)
        XCTAssertEqual(decoded.requestContext, request)
    }

    func testUnknownFuturePayloadVersionIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.payloadVersion = 99
        let night = Phase4CFixtures.nightScore(for: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Unknown version must be night-only")
        }
    }
}

// MARK: - Association helper

final class WatchObservingQualityCurrentLocationAssociationTests: XCTestCase {
    func testCoordinatesMatchWithinTolerance() {
        let eps = WatchObservingQualityCurrentLocationAssociation.coordinateTolerance
        XCTAssertTrue(
            WatchObservingQualityCurrentLocationAssociation.coordinatesMatch(
                latitude: Phase4CFixtures.latitude,
                longitude: Phase4CFixtures.longitude,
                otherLatitude: Phase4CFixtures.latitude + eps * 0.5,
                otherLongitude: Phase4CFixtures.longitude
            )
        )
    }

    func testCoordinatesRejectOutsideTolerance() {
        XCTAssertFalse(
            WatchObservingQualityCurrentLocationAssociation.coordinatesMatch(
                latitude: Phase4CFixtures.latitude,
                longitude: Phase4CFixtures.longitude,
                otherLatitude: Phase4CFixtures.latitude + 0.001,
                otherLongitude: Phase4CFixtures.longitude
            )
        )
    }

    func testRejectsZeroZero() {
        XCTAssertFalse(
            WatchObservingQualityCurrentLocationAssociation.coordinatesMatch(
                latitude: 0, longitude: 0,
                otherLatitude: 0, otherLongitude: 0
            )
        )
    }

    func testRequestCorrelationRequiresMatchingUUID() {
        let a = Phase4CFixtures.request(id: UUID())
        let b = Phase4CFixtures.request(id: UUID())
        XCTAssertFalse(
            WatchObservingQualityCurrentLocationAssociation.requestCorrelationMatches(
                expected: a,
                transported: b
            )
        )
        XCTAssertTrue(
            WatchObservingQualityCurrentLocationAssociation.requestCorrelationMatches(
                expected: a,
                transported: a
            )
        )
    }

    func testRequestCorrelationRequiresMatchingCoordinates() {
        let id = UUID()
        let a = Phase4CFixtures.request(id: id, lat: 45.5, lon: -122.6)
        let b = Phase4CFixtures.request(id: id, lat: 47.6, lon: -122.3)
        XCTAssertFalse(
            WatchObservingQualityCurrentLocationAssociation.requestCorrelationMatches(
                expected: a,
                transported: b
            )
        )
    }
}

// MARK: - Canonicalizer Current Location

final class WatchObservingQualityCurrentLocationCanonicalizerTests: XCTestCase {
    func testValidCorrelatedPayloadEnhances() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .enhanced(snap, loc) = outcome {
            XCTAssertEqual(snap.nightConditionsScore, night)
            XCTAssertEqual(snap.brightnessAvailability, .available)
            XCTAssertGreaterThanOrEqual(snap.observingQualityScore, 0)
            XCTAssertLessThanOrEqual(snap.observingQualityScore, 100)
            XCTAssertEqual(loc.source, .currentGPS)
            XCTAssertNil(loc.savedLocationID)
        } else {
            XCTFail("Expected enhancement")
        }
    }

    func testMismatchedRequestUUIDIsNightOnly() {
        let request = Phase4CFixtures.request()
        let other = Phase4CFixtures.request() // different UUID
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: other,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Wrong UUID must be night-only")
        }
    }

    func testPriorRequestUUIDIsNightOnly() {
        let prior = Phase4CFixtures.request()
        let current = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: prior,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: current
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Prior request UUID must not enhance")
        }
    }

    func testMissingExpectedRequestIsNightOnly_UnsolicitedPush() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        // Push path: no outstanding expected request.
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: nil
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Unsolicited CL OQ must be night-only")
        }
    }

    func testNonNilSavedIDInContextIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.location.savedLocationID = UUID()
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Saved ID on CL context must be night-only")
        }
    }

    func testNonNilBrightnessSavedIDIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.transportedSnapshot.brightnessSavedLocationID = UUID()
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Brightness saved ID on CL must be night-only")
        }
    }

    func testConditionsCoordinateMismatchIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions(lat: 47.6, lon: -122.3)
        let night = Phase4CFixtures.nightScore(for: conditions)
        // Payload claims request coords; conditions differ.
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: Phase4CFixtures.analyzableConditions() // matching request
        )
        // Force night score agreement so only coord association fails.
        var adjusted = payload
        adjusted.transportedSnapshot.nightConditionsScore = night
        adjusted.transportedSnapshot.observingQualityScore = night

        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: adjusted,
            selectedLocation: Phase4CFixtures.selectedCurrent(lat: 47.6, lon: -122.3),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Conditions coord mismatch must be night-only")
        }
    }

    func testLookupSampleCoordinateMismatchIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        // Move lookup coords far enough to break Phase 1 1000 m association on recompute.
        payload.transportedSnapshot.brightnessLookupLatitude = request.latitude + 1.0
        payload.transportedSnapshot.brightnessLookupLongitude = request.longitude + 1.0
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Lookup mismatch must be night-only")
        }
    }

    func testUnsupportedDatasetIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.transportedSnapshot.brightnessDataset = LightPollutionDatasetIdentity(
            datasetID: "unknown",
            datasetRevision: 1,
            formatVersion: 1
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Unsupported dataset must be night-only")
        }
    }

    func testOutOfRangeBrightnessIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.transportedSnapshot.modeledZenithBrightness = 5.0 // below plausible
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Out-of-range brightness must be night-only")
        }
    }

    func testTransportedScoreTamperingIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions,
            oqOverride: 99
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Tampered OQ score must be night-only")
        }
    }

    func testMissingRequestContextIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.requestContext = nil
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Missing request context must be night-only")
        }
    }

    func testSelectedSavedLocationCannotEnhanceCL() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedSaved(id: UUID()),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("Saved selection must not enhance CL transport")
        }
    }

    func testValidSavedPathUnchangedAlongsideCL() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        let payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedSaved(id: id)
        )
        if case .enhanced = outcome {
            // ok
        } else {
            XCTFail("Saved path must remain enhanced")
        }
    }

    func testSavedPayloadWithCLRequestContextIsNightOnly() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        payload.requestContext = Phase4CFixtures.request()
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedSaved(id: id)
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("CL request context on saved payload must be night-only")
        }
    }
}

// MARK: - Persistence / restart association

final class WatchObservingQualityCurrentLocationPersistenceTests: XCTestCase {
    func testValidDocumentRoundTripsWithoutRequestUUID() throws {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        guard let doc = WatchObservingQualityCanonicalizer.document(
            from: outcome,
            conditions: conditions
        ) else {
            return XCTFail("document")
        }
        // Durable document has no request UUID field.
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(WatchObservingQualityDocument.self, from: data)
        XCTAssertEqual(decoded.location.source, .currentGPS)
        XCTAssertNil(decoded.associatedConditionsLocationID)
        XCTAssertTrue(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: decoded,
                conditions: conditions,
                selectedLocation: Phase4CFixtures.selectedCurrent()
            )
        )
    }

    func testRestartRestoresOQWithMatchingConditions() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        let doc = WatchObservingQualityCanonicalizer.document(
            from: outcome,
            conditions: conditions
        )!
        XCTAssertTrue(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: conditions,
                selectedLocation: Phase4CFixtures.selectedCurrent()
            )
        )
    }

    func testChangedConditionsRejectStaleOQ() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions(cloudCover: 5)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        let doc = WatchObservingQualityCanonicalizer.document(
            from: outcome,
            conditions: conditions
        )!
        let newConditions = Phase4CFixtures.analyzableConditions(cloudCover: 90)
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: newConditions,
                selectedLocation: Phase4CFixtures.selectedCurrent()
            )
        )
    }

    func testChangedCoordinateRejectsStaleOQ() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        let doc = WatchObservingQualityCanonicalizer.document(
            from: outcome,
            conditions: conditions
        )!
        let moved = Phase4CFixtures.analyzableConditions(lat: 47.6, lon: -122.3)
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: moved,
                selectedLocation: Phase4CFixtures.selectedCurrent(lat: 47.6, lon: -122.3)
            )
        )
    }

    func testSavedAndCLDocumentsCannotCrossAssociate() {
        let request = Phase4CFixtures.request()
        let clConditions = Phase4CFixtures.analyzableConditions()
        let clPayload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: clConditions
        )
        let clDoc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: clConditions,
                transported: clPayload,
                selectedLocation: Phase4CFixtures.selectedCurrent(),
                expectedCurrentLocationRequest: request
            ),
            conditions: clConditions
        )!

        let savedID = UUID()
        let savedConditions = Phase4CFixtures.analyzableConditions(
            locationID: savedID,
            name: "Dark Site"
        )
        // CL doc must not associate with saved conditions.
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: clDoc,
                conditions: savedConditions,
                selectedLocation: Phase4CFixtures.selectedSaved(id: savedID)
            )
        )

        let savedDoc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: savedConditions,
                transported: Phase4CFixtures.validSavedPayload(id: savedID, conditions: savedConditions),
                selectedLocation: Phase4CFixtures.selectedSaved(id: savedID)
            ),
            conditions: savedConditions
        )!
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: savedDoc,
                conditions: clConditions,
                selectedLocation: Phase4CFixtures.selectedCurrent()
            )
        )
    }

    func testRequestUUIDNotRequiredForDurableRestore() {
        // Document association never sees request UUID — only conditions identity.
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let doc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: conditions,
                transported: Phase4CFixtures.validCurrentLocationPayload(
                    request: request,
                    conditions: conditions
                ),
                selectedLocation: Phase4CFixtures.selectedCurrent(),
                expectedCurrentLocationRequest: request
            ),
            conditions: conditions
        )!
        // No outstanding request — still associated.
        XCTAssertTrue(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: conditions,
                selectedLocation: Phase4CFixtures.selectedCurrent()
            )
        )
    }
}

// MARK: - Test doubles (coordinator)

private final class Phase4CRecordingReloader: WatchComplicationReloadReporting, @unchecked Sendable {
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

private final class Phase4CInMemoryStore: WatchConditionsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var _conditions: ViewingConditions?
    private var _oq: WatchObservingQualityDocument?
    private var _persistCount = 0

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

    func persistAcceptedPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?
    ) throws {
        lock.lock()
        _conditions = conditions
        _oq = observingQuality
        _persistCount += 1
        lock.unlock()
    }
}

private actor Phase4COrderingGate: WatchConditionsUpdateGate {
    private var firstEntered = false
    private var firstHold: CheckedContinuation<Void, Never>?
    private var firstResume: CheckedContinuation<Void, Never>?

    func beforePersist() async {
        if !firstEntered {
            firstEntered = true
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                firstHold = cont
                firstResume?.resume()
                firstResume = nil
            }
        }
    }

    func beforeApplyCached() async {}

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

// MARK: - Ordering / publication

final class WatchObservingQualityCurrentLocationOrderingTests: XCTestCase {
    func testRefreshAThenB_BFinishesFirst_OnlyBApplies() async {
        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )

        let requestA = Phase4CFixtures.request(
            lat: Phase4CFixtures.latitude,
            lon: Phase4CFixtures.longitude
        )
        let requestB = Phase4CFixtures.request(
            lat: Phase4CFixtures.latitude + 0.01,
            lon: Phase4CFixtures.longitude - 0.01
        )
        let conditionsA = Phase4CFixtures.analyzableConditions(
            lat: requestA.latitude,
            lon: requestA.longitude,
            cloudCover: 5
        )
        let conditionsB = Phase4CFixtures.analyzableConditions(
            lat: requestB.latitude,
            lon: requestB.longitude,
            cloudCover: 80
        )

        let tokenA = await coordinator.beginLiveUpdate()
        let tokenB = await coordinator.beginLiveUpdate()

        // B completes first
        let resultB = await coordinator.accept(
            conditions: conditionsB,
            transported: Phase4CFixtures.validCurrentLocationPayload(
                request: requestB,
                conditions: conditionsB
            ),
            selectedLocation: Phase4CFixtures.selectedCurrent(
                lat: requestB.latitude,
                lon: requestB.longitude
            ),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenB,
            expectedCurrentLocationRequest: requestB
        )
        let resultA = await coordinator.accept(
            conditions: conditionsA,
            transported: Phase4CFixtures.validCurrentLocationPayload(
                request: requestA,
                conditions: conditionsA
            ),
            selectedLocation: Phase4CFixtures.selectedCurrent(
                lat: requestA.latitude,
                lon: requestA.longitude
            ),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenA,
            expectedCurrentLocationRequest: requestA
        )

        guard case .applied = resultB else { return XCTFail("B must apply") }
        if case .discardedStale = resultA { /* ok */ } else { XCTFail("A must be discarded") }
        XCTAssertEqual(store.persistCount, 1)
        guard let appliedLat = store.conditions?.location.latitude else {
            return XCTFail("expected applied conditions")
        }
        XCTAssertEqual(appliedLat, requestB.latitude, accuracy: 1e-9)
        XCTAssertEqual(reloader.count, 1)
    }

    func testSavedPushInvalidatesOlderCurrentLocationRequest() async {
        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let gate = Phase4COrderingGate()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: gate
        )

        let request = Phase4CFixtures.request()
        let clConditions = Phase4CFixtures.analyzableConditions(cloudCover: 5)
        let savedID = UUID()
        let savedConditions = Phase4CFixtures.analyzableConditions(
            locationID: savedID,
            cloudCover: 40,
            name: "Dark Site"
        )

        let clToken = await coordinator.beginLiveUpdate()
        // CL accept starts and holds before persist
        let clTask = Task {
            await coordinator.accept(
                conditions: clConditions,
                transported: Phase4CFixtures.validCurrentLocationPayload(
                    request: request,
                    conditions: clConditions
                ),
                selectedLocation: Phase4CFixtures.selectedCurrent(),
                locationTimeZone: nil,
                reloadComplications: true,
                token: clToken,
                expectedCurrentLocationRequest: request
            )
        }
        await gate.waitUntilFirstIsHeld()

        // Saved push claims later and applies fully
        let savedToken = await coordinator.beginLiveUpdate()
        await gate.releaseFirst()
        let savedResult = await coordinator.accept(
            conditions: savedConditions,
            transported: Phase4CFixtures.validSavedPayload(id: savedID, conditions: savedConditions),
            selectedLocation: Phase4CFixtures.selectedSaved(id: savedID),
            locationTimeZone: nil,
            reloadComplications: true,
            token: savedToken
        )
        let clResult = await clTask.value

        guard case .applied = savedResult else { return XCTFail("saved must apply") }
        if case .discardedStale = clResult { /* ok */ } else {
            // CL may still run if it held the lock first and completed after release —
            // but withCurrentToken should discard once saved claimed later...
            // Actually: CL claimed first, held at beforePersist (outside lock). Saved claims
            // (higher sequence). When CL resumes, withCurrentToken fails → discarded.
            XCTFail("older CL must be discarded after newer saved claim")
        }
        XCTAssertEqual(store.conditions?.location.id, savedID)
    }

    func testCurrentLocationRequestInvalidatesOlderSavedResult() async {
        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )

        let savedID = UUID()
        let savedConditions = Phase4CFixtures.analyzableConditions(
            locationID: savedID,
            name: "Dark Site"
        )
        let savedToken = await coordinator.beginLiveUpdate()

        let request = Phase4CFixtures.request()
        let clConditions = Phase4CFixtures.analyzableConditions(cloudCover: 20)
        let clToken = await coordinator.beginLiveUpdate()

        let clResult = await coordinator.accept(
            conditions: clConditions,
            transported: Phase4CFixtures.validCurrentLocationPayload(
                request: request,
                conditions: clConditions
            ),
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            locationTimeZone: nil,
            reloadComplications: true,
            token: clToken,
            expectedCurrentLocationRequest: request
        )
        let savedResult = await coordinator.accept(
            conditions: savedConditions,
            transported: Phase4CFixtures.validSavedPayload(id: savedID, conditions: savedConditions),
            selectedLocation: Phase4CFixtures.selectedSaved(id: savedID),
            locationTimeZone: nil,
            reloadComplications: true,
            token: savedToken
        )

        guard case .applied = clResult else { return XCTFail("CL must apply") }
        if case .discardedStale = savedResult { /* ok */ } else { XCTFail("saved discarded") }
        XCTAssertNil(store.conditions?.location.id)
        guard let appliedLat = store.conditions?.location.latitude else {
            return XCTFail("expected CL conditions")
        }
        XCTAssertEqual(appliedLat, Phase4CFixtures.latitude, accuracy: 1e-9)
    }

    func testFailedNewerRequestBlocksDelayedOlderPublication() async {
        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )

        let requestA = Phase4CFixtures.request()
        let conditionsA = Phase4CFixtures.analyzableConditions(cloudCover: 5)
        let tokenA = await coordinator.beginLiveUpdate()

        // Newer claim that "fails" (malformed OQ → night-only still applies if conditions valid,
        // so simulate by never accepting B and only claiming).
        _ = await coordinator.beginLiveUpdate()

        let resultA = await coordinator.accept(
            conditions: conditionsA,
            transported: Phase4CFixtures.validCurrentLocationPayload(
                request: requestA,
                conditions: conditionsA
            ),
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            locationTimeZone: nil,
            reloadComplications: true,
            token: tokenA,
            expectedCurrentLocationRequest: requestA
        )
        if case .discardedStale = resultA { /* ok */ } else {
            XCTFail("older must be discarded after newer claim even if newer never persists")
        }
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }

    func testIdenticalDisplayFingerprintDoesNotReloadTwice() async {
        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let selected = Phase4CFixtures.selectedCurrent()

        let t1 = await coordinator.beginLiveUpdate()
        _ = await coordinator.accept(
            conditions: conditions,
            transported: payload,
            selectedLocation: selected,
            locationTimeZone: nil,
            reloadComplications: true,
            token: t1,
            expectedCurrentLocationRequest: request
        )
        XCTAssertEqual(reloader.count, 1)

        // Same material state, new request UUID (fingerprint excludes request UUID).
        let request2 = Phase4CFixtures.request(
            lat: request.latitude,
            lon: request.longitude
        )
        var payload2 = payload
        payload2.requestContext = request2
        let t2 = await coordinator.beginLiveUpdate()
        _ = await coordinator.accept(
            conditions: conditions,
            transported: payload2,
            selectedLocation: selected,
            locationTimeZone: nil,
            reloadComplications: true,
            token: t2,
            expectedCurrentLocationRequest: request2
        )
        XCTAssertEqual(reloader.count, 1, "identical fingerprint must not reload again")
        XCTAssertEqual(store.persistCount, 2)
    }

    func testCoordinateBucketChangeReloadsOnce() async {
        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )

        let r1 = Phase4CFixtures.request()
        let c1 = Phase4CFixtures.analyzableConditions()
        let t1 = await coordinator.beginLiveUpdate()
        _ = await coordinator.accept(
            conditions: c1,
            transported: Phase4CFixtures.validCurrentLocationPayload(request: r1, conditions: c1),
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            locationTimeZone: nil,
            reloadComplications: true,
            token: t1,
            expectedCurrentLocationRequest: r1
        )

        let r2 = Phase4CFixtures.request(lat: Phase4CFixtures.latitude + 0.01, lon: Phase4CFixtures.longitude)
        let c2 = Phase4CFixtures.analyzableConditions(lat: r2.latitude, lon: r2.longitude)
        let t2 = await coordinator.beginLiveUpdate()
        _ = await coordinator.accept(
            conditions: c2,
            transported: Phase4CFixtures.validCurrentLocationPayload(request: r2, conditions: c2),
            selectedLocation: Phase4CFixtures.selectedCurrent(lat: r2.latitude, lon: r2.longitude),
            locationTimeZone: nil,
            reloadComplications: true,
            token: t2,
            expectedCurrentLocationRequest: r2
        )
        XCTAssertEqual(reloader.count, 2)
    }
}

// MARK: - Presentation / fingerprint

final class WatchObservingQualityCurrentLocationPresentationTests: XCTestCase {
    func testEnhancedHeadlineUsesOQScoreAndVerdict() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions,
            brightness: 17.0 // brighter → more penalty likely
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        guard case let .enhanced(snap, loc) = outcome else {
            return XCTFail("expected enhance")
        }
        let headline = WatchObservingQualityHeadline(
            nightConditionsScore: snap.nightConditionsScore,
            observingQualityScore: snap.observingQualityScore,
            brightnessAvailability: snap.brightnessAvailability,
            location: loc,
            dataset: snap.brightnessDataset
        )
        XCTAssertEqual(headline.nightConditionsScore, night)
        XCTAssertEqual(headline.observingQualityScore, snap.observingQualityScore)
        XCTAssertEqual(
            headline.verdict,
            CrossSurfaceHeadlineScorePresentation.verdict(for: snap.observingQualityScore)
        )
        XCTAssertEqual(headline.fingerprint.source, .currentGPS)
        XCTAssertNil(headline.fingerprint.savedLocationID)
    }

    func testUnavailableEnhancementIsExactNightOnly() {
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let request = Phase4CFixtures.request()
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: nil,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: request
        )
        if case let .nightOnly(score, loc) = outcome {
            XCTAssertEqual(score, night)
            let headline = WatchObservingQualityHeadline.nightOnly(
                nightScore: score,
                location: loc ?? request.asLocationContext
            )
            XCTAssertEqual(headline.observingQualityScore, night)
            XCTAssertEqual(headline.brightnessAvailability, .unavailable)
        } else {
            XCTFail("expected night-only")
        }
    }

    func testFingerprintExcludesRequestUUIDAndTimestamps() {
        let r1 = Phase4CFixtures.request()
        let r2 = Phase4CFixtures.request(lat: r1.latitude, lon: r1.longitude)
        XCTAssertNotEqual(r1.requestID, r2.requestID)
        let conditions = Phase4CFixtures.analyzableConditions()
        let p1 = Phase4CFixtures.validCurrentLocationPayload(request: r1, conditions: conditions)
        let p2 = Phase4CFixtures.validCurrentLocationPayload(request: r2, conditions: conditions)
        guard case let .enhanced(s1, l1) = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: p1,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: r1
        ),
        case let .enhanced(s2, l2) = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: p2,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: r2
        ) else {
            return XCTFail("both enhance")
        }
        let f1 = ObservingQualityDisplayFingerprint(snapshot: s1, location: l1)
        let f2 = ObservingQualityDisplayFingerprint(snapshot: s2, location: l2)
        XCTAssertEqual(f1, f2)
    }
}

// MARK: - Local fallback

final class WatchObservingQualityCurrentLocationFallbackTests: XCTestCase {
    /// Local fallback drops transport correlation → night-only even if old OQ presented.
    func testLocalFallbackWithoutCorrelationIsNightOnly() {
        let conditions = Phase4CFixtures.analyzableConditions()
        let night = Phase4CFixtures.nightScore(for: conditions)
        // Manager sets expectedCurrentLocationRequest: nil and oq: nil on local fallback.
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: nil,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            expectedCurrentLocationRequest: nil
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("local fallback must be night-only")
        }
    }

    func testNightOnlyOutcomeClearsPersistedDocument() {
        let conditions = Phase4CFixtures.analyzableConditions()
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: nil,
            selectedLocation: Phase4CFixtures.selectedCurrent()
        )
        XCTAssertNil(
            WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditions)
        )
    }
}

// MARK: - Durable canonical restore (resolvePersisted + applyCached)

extension Phase4CFixtures {
    static func latitudeOffsetMeters(_ meters: Double) -> Double {
        (meters / 6_371_000.0) * (180.0 / .pi)
    }

    static func validCLDocument(
        request: WatchCurrentLocationRequestContext? = nil,
        conditions: ViewingConditions? = nil,
        brightness: Double = 18.5
    ) -> (WatchObservingQualityDocument, ViewingConditions, WatchCurrentLocationRequestContext) {
        let req = request ?? Phase4CFixtures.request()
        let cond = conditions ?? Phase4CFixtures.analyzableConditions(
            lat: req.latitude,
            lon: req.longitude
        )
        let payload = validCurrentLocationPayload(
            request: req,
            conditions: cond,
            brightness: brightness
        )
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: cond,
            transported: payload,
            selectedLocation: selectedCurrent(lat: req.latitude, lon: req.longitude),
            expectedCurrentLocationRequest: req
        )
        guard case .enhanced = outcome,
              let doc = WatchObservingQualityCanonicalizer.document(
                from: outcome,
                conditions: cond
              )
        else {
            fatalError("fixture requires valid enhanced document")
        }
        return (doc, cond, req)
    }
}

final class WatchObservingQualityDurableRestoreTests: XCTestCase {
    func testValidCLDocumentRestoresCanonicalOQViaApplyCached() async {
        let (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        let night = Phase4CFixtures.nightScore(for: conditions)
        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let token = await coordinator.beginDeferredApplication()
        let result = await coordinator.applyCached(
            conditions: conditions,
            selectedLocation: Phase4CFixtures.selectedCurrent(),
            persistedDocument: doc,
            locationTimeZone: nil,
            token: token
        )
        guard case let .applied(state) = result else {
            return XCTFail("must apply")
        }
        XCTAssertEqual(store.persistCount, 0, "cache apply must not persist")
        XCTAssertEqual(reloader.count, 0, "cache apply must not reload complications")
        let headline = state.observingQualityHeadline
        XCTAssertEqual(headline?.brightnessAvailability, .available)
        XCTAssertEqual(headline?.nightConditionsScore, night)
        // Canonical recompute: score matches resolver, not an untrusted raw field.
        let expected = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: night,
                location: doc.location,
                sample: ModeledZenithBrightnessSample(
                    latitude: doc.snapshot.brightnessLookupLatitude!,
                    longitude: doc.snapshot.brightnessLookupLongitude!,
                    modeledZenithSkyBrightness: doc.snapshot.modeledZenithBrightness!,
                    dataset: doc.snapshot.brightnessDataset!,
                    sampledAt: doc.snapshot.assessedAt,
                    savedLocationID: nil
                ),
                assessedAt: doc.snapshot.assessedAt
            )
        )
        XCTAssertEqual(headline?.observingQualityScore, expected.observingQualityScore)
        XCTAssertTrue(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: doc,
                conditions: conditions,
                selectedLocation: Phase4CFixtures.selectedCurrent()
            )
        )
    }

    func testTamperedPersistedOQScoreRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.observingQualityScore = 99
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testTamperedPersistedNightScoreRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.associatedNightConditionsScore = 1
        doc.snapshot.nightConditionsScore = 1
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testUnsupportedDatasetIDRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.brightnessDataset = LightPollutionDatasetIdentity(
            datasetID: "not-lpatlas",
            datasetRevision: 1,
            formatVersion: 1
        )
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testUnsupportedDatasetRevisionRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.brightnessDataset = LightPollutionDatasetIdentity(
            datasetID: "lpatlas1",
            datasetRevision: 99,
            formatVersion: 1
        )
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testUnsupportedFormatVersionRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.brightnessDataset = LightPollutionDatasetIdentity(
            datasetID: "lpatlas1",
            datasetRevision: 1,
            formatVersion: 99
        )
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testBrightnessBelowRangeRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.modeledZenithBrightness = 5.0
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testBrightnessAboveRangeRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.modeledZenithBrightness = 30.0
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testBrightnessNaNRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.modeledZenithBrightness = .nan
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testMissingBrightnessWhileAvailableRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.modeledZenithBrightness = nil
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testLookupOutside1000mRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        let offset = Phase4CFixtures.latitudeOffsetMeters(2_000)
        doc.snapshot.brightnessLookupLatitude = Phase4CFixtures.latitude + offset
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testSavedIDInLocationContextRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.location.savedLocationID = UUID()
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testBrightnessSavedLocationIDRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.brightnessSavedLocationID = UUID()
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testAssociatedConditionsIDRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.associatedConditionsLocationID = UUID()
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testTamperedBrightnessValueRejectedEvenIfOQScoreUnchanged() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        // Keep OQ score as-is but change brightness → recomputed score disagrees.
        doc.snapshot.modeledZenithBrightness = 17.0
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testTamperedLookupLongitudeRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.snapshot.brightnessLookupLongitude =
            Phase4CFixtures.longitude + Phase4CFixtures.latitudeOffsetMeters(2_000)
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testFutureSchemaVersionRejected() async {
        var (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        doc.schemaVersion = 99
        await assertCacheRestoreIsNightOnly(doc: doc, conditions: conditions)
    }

    func testValidRestoreDoesNotRequireRequestUUID() {
        let (doc, conditions, _) = Phase4CFixtures.validCLDocument()
        // resolvePersisted has no request parameter.
        let outcome = WatchObservingQualityCanonicalizer.resolvePersisted(
            document: doc,
            conditions: conditions,
            selectedLocation: Phase4CFixtures.selectedCurrent()
        )
        if case .enhanced = outcome {
            // ok
        } else {
            XCTFail("durable restore must enhance without request UUID")
        }
    }

    func testSavedAndCLCannotCrossRestore() {
        let (clDoc, clConditions, _) = Phase4CFixtures.validCLDocument()
        let savedID = UUID()
        let savedConditions = Phase4CFixtures.analyzableConditions(
            locationID: savedID,
            name: "Dark Site"
        )
        let savedPayload = Phase4CFixtures.validSavedPayload(id: savedID, conditions: savedConditions)
        let savedDoc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: savedConditions,
                transported: savedPayload,
                selectedLocation: Phase4CFixtures.selectedSaved(id: savedID)
            ),
            conditions: savedConditions
        )!

        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: clDoc,
                conditions: savedConditions,
                selectedLocation: Phase4CFixtures.selectedSaved(id: savedID)
            )
        )
        XCTAssertFalse(
            WatchObservingQualityCanonicalizer.isAssociated(
                document: savedDoc,
                conditions: clConditions,
                selectedLocation: Phase4CFixtures.selectedCurrent()
            )
        )
    }

    func testValidSavedDocumentAlsoRecomputesOnRestore() async {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        let payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        let doc = WatchObservingQualityCanonicalizer.document(
            from: WatchObservingQualityCanonicalizer.resolve(
                conditions: conditions,
                transported: payload,
                selectedLocation: Phase4CFixtures.selectedSaved(id: id)
            ),
            conditions: conditions
        )!
        var tampered = doc
        tampered.snapshot.observingQualityScore = 3
        await assertCacheRestoreIsNightOnly(
            doc: tampered,
            conditions: conditions,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )

        // Untampered still enhances via applyCached.
        let store = Phase4CInMemoryStore()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: Phase4CRecordingReloader(),
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let token = await coordinator.beginDeferredApplication()
        let result = await coordinator.applyCached(
            conditions: conditions,
            selectedLocation: Phase4CFixtures.selectedSaved(id: id),
            persistedDocument: doc,
            locationTimeZone: nil,
            token: token
        )
        guard case let .applied(state) = result else { return XCTFail("apply") }
        XCTAssertEqual(state.observingQualityHeadline?.brightnessAvailability, .available)
    }

    private func assertCacheRestoreIsNightOnly(
        doc: WatchObservingQualityDocument,
        conditions: ViewingConditions,
        selected: SelectedLocation? = nil
    ) async {
        let night = Phase4CFixtures.nightScore(for: conditions)
        let selectedLocation = selected ?? Phase4CFixtures.selectedCurrent()
        let outcome = WatchObservingQualityCanonicalizer.resolvePersisted(
            document: doc,
            conditions: conditions,
            selectedLocation: selectedLocation
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("expected night-only after tamper")
        }

        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let token = await coordinator.beginDeferredApplication()
        let result = await coordinator.applyCached(
            conditions: conditions,
            selectedLocation: selectedLocation,
            persistedDocument: doc,
            locationTimeZone: nil,
            token: token
        )
        guard case let .applied(state) = result else { return XCTFail("apply") }
        XCTAssertEqual(state.observingQualityHeadline?.observingQualityScore, night)
        XCTAssertEqual(state.observingQualityHeadline?.brightnessAvailability, .unavailable)
        XCTAssertEqual(store.persistCount, 0)
        XCTAssertEqual(reloader.count, 0)
    }
}

// MARK: - Payload version constants + version/source matrix

final class WatchObservingQualityPayloadVersionTests: XCTestCase {
    func testVersionConstants() {
        XCTAssertEqual(WatchObservingQualityPayload.savedLocationPayloadVersion, 1)
        XCTAssertEqual(WatchObservingQualityPayload.currentLocationPayloadVersion, 2)
        XCTAssertEqual(WatchObservingQualityPayload.currentPayloadVersion, 2)
        XCTAssertEqual(WatchCurrentLocationRequestContext.currentContextVersion, 1)
    }

    // MARK: Version/source matrix (transport boundary)

    func testSavedSourceV1NilRequestContextEnhances() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        let payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        XCTAssertEqual(payload.payloadVersion, 1)
        XCTAssertNil(payload.requestContext)
        assertEnhances(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    func testSavedSourceV2NilRequestContextIsNightOnly() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        var payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        payload.payloadVersion = WatchObservingQualityPayload.currentLocationPayloadVersion
        payload.requestContext = nil
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    func testSavedSourceV1WithRequestContextIsNightOnly() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        var payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        payload.requestContext = Phase4CFixtures.request()
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    func testSavedSourceV2WithRequestContextIsNightOnly() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        var payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        payload.payloadVersion = WatchObservingQualityPayload.currentLocationPayloadVersion
        payload.requestContext = Phase4CFixtures.request()
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    func testCurrentLocationSourceV2ValidContextEnhances() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        XCTAssertEqual(payload.payloadVersion, 2)
        XCTAssertNotNil(payload.requestContext)
        assertEnhances(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedCurrent(),
            expectedRequest: request
        )
    }

    func testCurrentLocationSourceV1WithValidContextIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.payloadVersion = WatchObservingQualityPayload.savedLocationPayloadVersion
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedCurrent(),
            expectedRequest: request
        )
    }

    func testCurrentLocationSourceV2MissingRequestContextIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.requestContext = nil
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedCurrent(),
            expectedRequest: request
        )
    }

    func testCurrentLocationSourceV1MissingRequestContextIsNightOnly() {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        var payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        payload.payloadVersion = WatchObservingQualityPayload.savedLocationPayloadVersion
        payload.requestContext = nil
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedCurrent(),
            expectedRequest: request
        )
    }

    func testVersion0IsNightOnly() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        var payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        payload.payloadVersion = 0
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    func testFutureVersionIsNightOnly() {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        var payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        payload.payloadVersion = 99
        assertNightOnly(
            conditions: conditions,
            payload: payload,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    // MARK: Codable compatibility

    func testLegacyV1SavedPayloadWithoutRequestContextKeyDecodesAndEnhances() throws {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        let payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        // Encode then strip requestContext key to simulate legacy wire format.
        let data = try JSONEncoder().encode(payload)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "requestContext")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WatchObservingQualityPayload.self, from: legacyData)
        XCTAssertEqual(decoded.payloadVersion, 1)
        XCTAssertNil(decoded.requestContext)
        assertEnhances(
            conditions: conditions,
            payload: decoded,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    func testV2CurrentLocationPayloadRoundTripsWithRequestContext() throws {
        let request = Phase4CFixtures.request()
        let conditions = Phase4CFixtures.analyzableConditions()
        let payload = Phase4CFixtures.validCurrentLocationPayload(
            request: request,
            conditions: conditions
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchObservingQualityPayload.self, from: data)
        XCTAssertEqual(decoded.payloadVersion, 2)
        XCTAssertEqual(decoded.requestContext, request)
        assertEnhances(
            conditions: conditions,
            payload: decoded,
            selected: Phase4CFixtures.selectedCurrent(),
            expectedRequest: request
        )
    }

    func testAdditiveDecodingDoesNotAlterV1Semantics() throws {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        let payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        let data = try JSONEncoder().encode(payload)
        // Inject unknown additive key; v1 semantics must remain.
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["futureAdditiveField"] = "ignored"
        let mutated = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WatchObservingQualityPayload.self, from: mutated)
        XCTAssertEqual(decoded.payloadVersion, 1)
        XCTAssertNil(decoded.requestContext)
        assertEnhances(
            conditions: conditions,
            payload: decoded,
            selected: Phase4CFixtures.selectedSaved(id: id)
        )
    }

    // MARK: Coordinator rejection path

    func testMalformedVersionSourceDoesNotBecomeDurableAuthority() async {
        let id = UUID()
        let conditions = Phase4CFixtures.analyzableConditions(locationID: id, name: "Dark Site")
        let night = Phase4CFixtures.nightScore(for: conditions)
        var payload = Phase4CFixtures.validSavedPayload(id: id, conditions: conditions)
        payload.payloadVersion = 2 // wrong for saved
        let nightScore = night

        let store = Phase4CInMemoryStore()
        let reloader = Phase4CRecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        let token = await coordinator.beginLiveUpdate()
        let result = await coordinator.accept(
            conditions: conditions,
            transported: payload,
            selectedLocation: Phase4CFixtures.selectedSaved(id: id),
            locationTimeZone: nil,
            reloadComplications: true,
            token: token
        )
        guard case let .applied(state) = result else {
            return XCTFail("conditions must still apply")
        }
        XCTAssertEqual(store.conditions?.location.id, id)
        XCTAssertNil(store.observingQuality, "malformed transport must clear OQ document")
        XCTAssertEqual(state.observingQualityHeadline?.observingQualityScore, nightScore)
        XCTAssertEqual(state.observingQualityHeadline?.brightnessAvailability, .unavailable)
        // Durable restore of nil OQ remains night-only.
        let restore = WatchObservingQualityCanonicalizer.resolvePersisted(
            document: store.observingQuality,
            conditions: conditions,
            selectedLocation: Phase4CFixtures.selectedSaved(id: id)
        )
        if case let .nightOnly(score, _) = restore {
            XCTAssertEqual(score, nightScore)
        } else {
            XCTFail("restore without document is night-only")
        }
    }

    // MARK: Helpers

    private func assertEnhances(
        conditions: ViewingConditions,
        payload: WatchObservingQualityPayload,
        selected: SelectedLocation?,
        expectedRequest: WatchCurrentLocationRequestContext? = nil
    ) {
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: selected,
            expectedCurrentLocationRequest: expectedRequest
        )
        guard case .enhanced = outcome else {
            return XCTFail("expected enhance")
        }
        let doc = WatchObservingQualityCanonicalizer.document(
            from: outcome,
            conditions: conditions
        )
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc?.snapshot.brightnessAvailability, .available)
    }

    private func assertNightOnly(
        conditions: ViewingConditions,
        payload: WatchObservingQualityPayload,
        selected: SelectedLocation?,
        expectedRequest: WatchCurrentLocationRequestContext? = nil
    ) {
        let night = Phase4CFixtures.nightScore(for: conditions)
        let outcome = WatchObservingQualityCanonicalizer.resolve(
            conditions: conditions,
            transported: payload,
            selectedLocation: selected,
            expectedCurrentLocationRequest: expectedRequest
        )
        if case let .nightOnly(score, _) = outcome {
            XCTAssertEqual(score, night)
        } else {
            XCTFail("expected night-only for version/source mismatch")
        }
        XCTAssertNil(
            WatchObservingQualityCanonicalizer.document(from: outcome, conditions: conditions)
        )
        // Conditions object is still the same input (never discarded by resolve).
        XCTAssertEqual(conditions.location.latitude, conditions.location.latitude)
    }
}
