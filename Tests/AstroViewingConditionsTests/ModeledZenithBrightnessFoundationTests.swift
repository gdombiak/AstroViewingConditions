@testable import SharedCode
import XCTest

private struct FixedBrightnessProvider: LightPollutionProviding {
    let value: Double?
    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? { value }
}

/// Counts provider invocations for association / invalid-coordinate tests.
private final class RecordingBrightnessProvider: LightPollutionProviding, @unchecked Sendable {
    let value: Double?
    private(set) var callCount = 0
    private(set) var lastLatitude: Double?
    private(set) var lastLongitude: Double?

    init(value: Double?) {
        self.value = value
    }

    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        callCount += 1
        lastLatitude = latitude
        lastLongitude = longitude
        return value
    }
}

final class ModeledZenithBrightnessFoundationTests: XCTestCase {

    // MARK: - Fixtures

    /// Pure north-south offset (meters) at the equator using the same sphere as validity.
    private func latitudeDegrees(offsetMeters northOfEquator: Double) -> Double {
        (northOfEquator / 6_371_000.0) * (180.0 / .pi)
    }

    private func baseSample(
        latitude: Double = 45.45,
        longitude: Double = -122.75,
        brightness: Double = 18.5,
        dataset: LightPollutionDatasetIdentity = .current,
        sampledAt: Date = Date(),
        savedLocationID: UUID? = nil
    ) -> ModeledZenithBrightnessSample {
        ModeledZenithBrightnessSample(
            latitude: latitude,
            longitude: longitude,
            modeledZenithSkyBrightness: brightness,
            dataset: dataset,
            sampledAt: sampledAt,
            savedLocationID: savedLocationID
        )
    }

    // MARK: - Identity

    func testCurrentDatasetIdentityFields() {
        let id = LightPollutionDatasetIdentity.current
        XCTAssertEqual(id.datasetID, "lpatlas1")
        XCTAssertEqual(id.datasetRevision, 1)
        XCTAssertEqual(id.formatVersion, 1)
    }

    func testDatasetCompatibilityRequiresAllLogicalFields() {
        let current = LightPollutionDatasetIdentity.current
        XCTAssertTrue(current.isCompatible(with: current))
        XCTAssertFalse(
            current.isCompatible(
                with: LightPollutionDatasetIdentity(
                    datasetID: "lpatlas1",
                    datasetRevision: 2,
                    formatVersion: 1
                )
            )
        )
        XCTAssertFalse(
            current.isCompatible(
                with: LightPollutionDatasetIdentity(
                    datasetID: "lpatlas1",
                    datasetRevision: 1,
                    formatVersion: 2
                )
            )
        )
        XCTAssertFalse(
            current.isCompatible(
                with: LightPollutionDatasetIdentity(
                    datasetID: "other",
                    datasetRevision: 1,
                    formatVersion: 1
                )
            )
        )
    }

    func testDatasetIdentityCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(LightPollutionDatasetIdentity.current)
        let decoded = try JSONDecoder().decode(LightPollutionDatasetIdentity.self, from: data)
        XCTAssertEqual(decoded, .current)
    }

    func testSampleCodableRoundTripPreservesFields() throws {
        let id = UUID()
        let sample = ModeledZenithBrightnessSample(
            latitude: 45.45,
            longitude: -122.75,
            modeledZenithSkyBrightness: 18.539606,
            dataset: .current,
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000),
            savedLocationID: id
        )
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(ModeledZenithBrightnessSample.self, from: data)
        XCTAssertEqual(decoded, sample)
    }

    func testSampleCodableWithoutSavedLocationID() throws {
        let sample = ModeledZenithBrightnessSample(
            latitude: 0,
            longitude: 0,
            modeledZenithSkyBrightness: 22.0,
            savedLocationID: nil
        )
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(ModeledZenithBrightnessSample.self, from: data)
        XCTAssertNil(decoded.savedLocationID)
        XCTAssertEqual(decoded.modeledZenithSkyBrightness, 22.0, accuracy: 1e-9)
    }

    // MARK: - Brightness range

    func testBrightnessRangeBoundaries() {
        XCTAssertTrue(ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(13.0))
        XCTAssertTrue(ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(22.5))
        XCTAssertTrue(ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(18.5))
        XCTAssertFalse(ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(12.99))
        XCTAssertFalse(ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(22.51))
        XCTAssertFalse(ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(.nan))
        XCTAssertFalse(ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(.infinity))
    }

    // MARK: - Geographic domains

    func testGeographicCoordinateBoundsAccepted() {
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: -90, longitude: 0)
        )
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 90, longitude: 0)
        )
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 0, longitude: -180)
        )
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 0, longitude: 180)
        )
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 45.45, longitude: -122.75)
        )
    }

    func testGeographicCoordinateOutOfRangeRejected() {
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: -90.01, longitude: 0)
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 90.01, longitude: 0)
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 0, longitude: -180.01)
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 0, longitude: 180.01)
        )
    }

    func testGeographicCoordinateNonFiniteRejected() {
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: .nan, longitude: 0)
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 0, longitude: .nan)
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: .infinity, longitude: 0)
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 0, longitude: -.infinity)
        )
    }

    func testCoordinatesMatchRejectsInvalidGeographicDomains() {
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 91,
                sampleLongitude: 0,
                requestLatitude: 0,
                requestLongitude: 0
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 0,
                sampleLongitude: 0,
                requestLatitude: 0,
                requestLongitude: 200
            )
        )
    }

    func testCoordinatesMatchRejectsInvalidMaxDistance() {
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 0,
                sampleLongitude: 0,
                requestLatitude: 0,
                requestLongitude: 0,
                maxDistanceMeters: -1
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 0,
                sampleLongitude: 0,
                requestLatitude: 0,
                requestLongitude: 0,
                maxDistanceMeters: .infinity
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 0,
                sampleLongitude: 0,
                requestLatitude: 0,
                requestLongitude: 0,
                maxDistanceMeters: .nan
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidMaxDistanceMeters(-0.1)
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValidMaxDistanceMeters(.infinity)
        )
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidMaxDistanceMeters(0)
        )
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidMaxDistanceMeters(1_000)
        )
    }

    // MARK: - Distance / 1000 m boundary

    func testCoordinateDistanceSamePointIsZero() {
        let d = ModeledZenithBrightnessValidity.distanceMeters(
            latitude1: 45.45,
            longitude1: -122.75,
            latitude2: 45.45,
            longitude2: -122.75
        )
        XCTAssertEqual(d, 0, accuracy: 1e-6)
    }

    func testCoordinateMatchWithinOneKilometer() {
        let lat2 = 45.45 + (500.0 / 111_320.0)
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 45.45,
                sampleLongitude: -122.75,
                requestLatitude: lat2,
                requestLongitude: -122.75
            )
        )
    }

    func testCoordinateMatchFailsBeyondOneKilometer() {
        let lat2 = 45.45 + (2_000.0 / 111_320.0)
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 45.45,
                sampleLongitude: -122.75,
                requestLatitude: lat2,
                requestLongitude: -122.75
            )
        )
    }

    func testExactlyOneThousandMetersIsAccepted() {
        // Pure meridional offset on the same sphere as distanceMeters → exact 1000 m.
        let lat2 = latitudeDegrees(offsetMeters: 1_000)
        let d = ModeledZenithBrightnessValidity.distanceMeters(
            latitude1: 0,
            longitude1: 0,
            latitude2: lat2,
            longitude2: 0
        )
        XCTAssertEqual(d, 1_000, accuracy: 1e-6)
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 0,
                sampleLongitude: 0,
                requestLatitude: lat2,
                requestLongitude: 0
            )
        )
    }

    func testJustOverOneThousandMetersIsRejected() {
        let lat2 = latitudeDegrees(offsetMeters: 1_000.5)
        let d = ModeledZenithBrightnessValidity.distanceMeters(
            latitude1: 0,
            longitude1: 0,
            latitude2: lat2,
            longitude2: 0
        )
        XCTAssertGreaterThan(d, 1_000)
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.coordinatesMatch(
                sampleLatitude: 0,
                sampleLongitude: 0,
                requestLatitude: lat2,
                requestLongitude: 0
            )
        )
    }

    // MARK: - Sample validity

    func testSampleInvalidWhenDatasetRevisionDiffers() {
        let sample = baseSample(
            dataset: LightPollutionDatasetIdentity(
                datasetID: "lpatlas1",
                datasetRevision: 99,
                formatVersion: 1
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75
            )
        )
    }

    func testSampleInvalidWhenCoordinatesMove() {
        let sample = baseSample()
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.5,
                longitude: -122.75
            )
        )
    }

    func testSampleInvalidWhenBrightnessOutOfRange() {
        let sample = baseSample(brightness: 30.0)
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75
            )
        )
    }

    func testSavedLocationIDMismatchInvalidates() {
        let a = UUID()
        let b = UUID()
        let sample = baseSample(savedLocationID: a)
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forSavedLocationID: a,
                locationLatitude: 45.45,
                locationLongitude: -122.75
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forSavedLocationID: b,
                locationLatitude: 45.45,
                locationLongitude: -122.75
            )
        )
    }

    func testSavedLocationAssociationExactSemantics() {
        let a = UUID()
        let b = UUID()
        let withA = baseSample(savedLocationID: a)
        let withNil = baseSample(savedLocationID: nil)

        XCTAssertTrue(
            ModeledZenithBrightnessValidity.savedLocationAssociationMatches(
                sample: withA,
                requestedSavedLocationID: a
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.savedLocationAssociationMatches(
                sample: withNil,
                requestedSavedLocationID: a
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.savedLocationAssociationMatches(
                sample: withA,
                requestedSavedLocationID: b
            )
        )
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.savedLocationAssociationMatches(
                sample: withNil,
                requestedSavedLocationID: nil
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.savedLocationAssociationMatches(
                sample: withA,
                requestedSavedLocationID: nil
            )
        )
    }

    // MARK: - maxAge contract

    func testMaxAgeExpiry() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sample = baseSample(sampledAt: now.addingTimeInterval(-3_600))
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75,
                maxAge: 7_200,
                now: now
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75,
                maxAge: 1_800,
                now: now
            )
        )
    }

    func testMaxAgeFutureSampledAtBeyondClockSkewIsInvalid() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        // More than the documented 1 s clock-skew allowance.
        let sample = baseSample(sampledAt: now.addingTimeInterval(1.001))
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75,
                maxAge: 3_600,
                now: now
            )
        )
        // Exactly at the skew bound remains valid.
        let atSkew = baseSample(sampledAt: now.addingTimeInterval(1.0))
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValid(
                sample: atSkew,
                forRequestAtLatitude: 45.45,
                longitude: -122.75,
                maxAge: 3_600,
                now: now
            )
        )
    }

    func testNegativeMaxAgeIsInvalid() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sample = baseSample(sampledAt: now)
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75,
                maxAge: -1,
                now: now
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isSampleAgeValid(
                sampledAt: now,
                maxAge: -0.1,
                now: now
            )
        )
    }

    func testNonFiniteMaxAgeIsInvalid() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let sample = baseSample(sampledAt: now)
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75,
                maxAge: .infinity,
                now: now
            )
        )
        XCTAssertFalse(
            ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: 45.45,
                longitude: -122.75,
                maxAge: .nan,
                now: now
            )
        )
    }

    // MARK: - Resolver sample

    func testResolverReturnsNilForProviderNil() {
        let provider = FixedBrightnessProvider(value: nil)
        XCTAssertNil(
            ModeledZenithBrightnessResolver.sample(
                from: provider,
                latitude: 45.45,
                longitude: -122.75
            )
        )
    }

    func testResolverReturnsNilForOutOfRangeBrightness() {
        let provider = FixedBrightnessProvider(value: 5.0)
        XCTAssertNil(
            ModeledZenithBrightnessResolver.sample(
                from: provider,
                latitude: 45.45,
                longitude: -122.75
            )
        )
    }

    func testResolverAttachesDatasetAndSavedLocationID() {
        let provider = FixedBrightnessProvider(value: 18.5)
        let id = UUID()
        let sample = ModeledZenithBrightnessResolver.sample(
            from: provider,
            latitude: 45.45,
            longitude: -122.75,
            savedLocationID: id
        )
        XCTAssertEqual(sample?.modeledZenithSkyBrightness, 18.5)
        XCTAssertEqual(sample?.dataset, .current)
        XCTAssertEqual(sample?.savedLocationID, id)
        XCTAssertEqual(sample?.latitude, 45.45)
        XCTAssertEqual(sample?.longitude, -122.75)
    }

    func testResolverSampleDoesNotInvokeProviderForInvalidCoordinates() {
        let provider = RecordingBrightnessProvider(value: 18.5)
        XCTAssertNil(
            ModeledZenithBrightnessResolver.sample(
                from: provider,
                latitude: 91,
                longitude: 0
            )
        )
        XCTAssertNil(
            ModeledZenithBrightnessResolver.sample(
                from: provider,
                latitude: 0,
                longitude: 181
            )
        )
        XCTAssertNil(
            ModeledZenithBrightnessResolver.sample(
                from: provider,
                latitude: .nan,
                longitude: 0
            )
        )
        XCTAssertEqual(provider.callCount, 0)
    }

    // MARK: - Resolver resolve / association

    func testResolvePrefersValidCacheOverProvider() {
        let cached = baseSample(brightness: 18.1, sampledAt: Date())
        let provider = RecordingBrightnessProvider(value: 21.0)
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: 45.45,
            requestLongitude: -122.75,
            cached: cached,
            provider: provider
        )
        XCTAssertEqual(resolved!.modeledZenithSkyBrightness, 18.1, accuracy: 1e-9)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testResolveFallsBackToProviderWhenCacheStaleByDataset() {
        let cached = baseSample(
            brightness: 18.1,
            dataset: LightPollutionDatasetIdentity(
                datasetID: "lpatlas1",
                datasetRevision: 0,
                formatVersion: 1
            )
        )
        let provider = FixedBrightnessProvider(value: 21.0)
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: 45.45,
            requestLongitude: -122.75,
            cached: cached,
            provider: provider
        )
        XCTAssertEqual(resolved!.modeledZenithSkyBrightness, 21.0, accuracy: 1e-9)
    }

    func testResolveReturnsNilWhenCacheInvalidAndNoProvider() {
        let cached = baseSample(latitude: 10, longitude: 10, brightness: 18.0)
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: 45.45,
            requestLongitude: -122.75,
            cached: cached,
            provider: nil
        )
        XCTAssertNil(resolved)
    }

    func testResolveAssociationMatchingSavedIDsUsesCacheWithoutProvider() {
        let id = UUID()
        let cached = baseSample(brightness: 17.2, savedLocationID: id)
        let provider = RecordingBrightnessProvider(value: 21.0)
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: 45.45,
            requestLongitude: -122.75,
            cached: cached,
            provider: provider,
            savedLocationID: id
        )
        XCTAssertEqual(resolved!.modeledZenithSkyBrightness, 17.2, accuracy: 1e-9)
        XCTAssertEqual(resolved!.savedLocationID, id)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testResolveAssociationRequestedSavedIDRejectsCachedNil() {
        let id = UUID()
        let cached = baseSample(brightness: 17.2, savedLocationID: nil)
        let provider = RecordingBrightnessProvider(value: 21.0)
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: 45.45,
            requestLongitude: -122.75,
            cached: cached,
            provider: provider,
            savedLocationID: id
        )
        XCTAssertEqual(resolved!.modeledZenithSkyBrightness, 21.0, accuracy: 1e-9)
        XCTAssertEqual(resolved!.savedLocationID, id)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testResolveAssociationCoordinateOnlyRejectsCachedSavedID() {
        let id = UUID()
        let cached = baseSample(brightness: 17.2, savedLocationID: id)
        let provider = RecordingBrightnessProvider(value: 21.0)
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: 45.45,
            requestLongitude: -122.75,
            cached: cached,
            provider: provider,
            savedLocationID: nil
        )
        XCTAssertEqual(resolved!.modeledZenithSkyBrightness, 21.0, accuracy: 1e-9)
        XCTAssertNil(resolved!.savedLocationID)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testResolveAssociationCoordinateOnlyMatchingNilsUsesCache() {
        let cached = baseSample(brightness: 17.2, savedLocationID: nil)
        let provider = RecordingBrightnessProvider(value: 21.0)
        let resolved = ModeledZenithBrightnessResolver.resolve(
            requestLatitude: 45.45,
            requestLongitude: -122.75,
            cached: cached,
            provider: provider,
            savedLocationID: nil
        )
        XCTAssertEqual(resolved!.modeledZenithSkyBrightness, 17.2, accuracy: 1e-9)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testResolveAssociationMismatchWithNoProviderReturnsNil() {
        let a = UUID()
        let b = UUID()
        let cached = baseSample(brightness: 17.2, savedLocationID: a)
        // Requested B vs cached A
        XCTAssertNil(
            ModeledZenithBrightnessResolver.resolve(
                requestLatitude: 45.45,
                requestLongitude: -122.75,
                cached: cached,
                provider: nil,
                savedLocationID: b
            )
        )
        // Requested A vs cached nil
        XCTAssertNil(
            ModeledZenithBrightnessResolver.resolve(
                requestLatitude: 45.45,
                requestLongitude: -122.75,
                cached: baseSample(brightness: 17.2, savedLocationID: nil),
                provider: nil,
                savedLocationID: a
            )
        )
        // Coordinate-only vs cached A
        XCTAssertNil(
            ModeledZenithBrightnessResolver.resolve(
                requestLatitude: 45.45,
                requestLongitude: -122.75,
                cached: cached,
                provider: nil,
                savedLocationID: nil
            )
        )
    }

    func testResolveDoesNotInvokeProviderForInvalidCoordinates() {
        let provider = RecordingBrightnessProvider(value: 18.5)
        let cached = baseSample()
        XCTAssertNil(
            ModeledZenithBrightnessResolver.resolve(
                requestLatitude: 95,
                requestLongitude: 0,
                cached: cached,
                provider: provider
            )
        )
        XCTAssertNil(
            ModeledZenithBrightnessResolver.resolve(
                requestLatitude: 0,
                requestLongitude: 200,
                cached: nil,
                provider: provider
            )
        )
        XCTAssertEqual(provider.callCount, 0)
    }
}
