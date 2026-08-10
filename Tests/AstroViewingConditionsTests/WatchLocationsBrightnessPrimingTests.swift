import Foundation
import XCTest
@testable import SharedCode

final class WatchLocationsBrightnessPrimingTests: XCTestCase {
    private let lat = 45.45
    private let lon = -122.75

    private func sample(
        id: UUID,
        lat: Double? = nil,
        lon: Double? = nil,
        brightness: Double = 18.5,
        revision: Int = 1,
        sampledAt: Date = Date().addingTimeInterval(-60)
    ) -> ModeledZenithBrightnessSample {
        ModeledZenithBrightnessSample(
            latitude: lat ?? self.lat,
            longitude: lon ?? self.lon,
            modeledZenithSkyBrightness: brightness,
            dataset: LightPollutionDatasetIdentity(
                datasetID: "lpatlas1",
                datasetRevision: revision,
                formatVersion: 1
            ),
            sampledAt: sampledAt,
            savedLocationID: id
        )
    }

    private func pin(id: UUID, lat: Double? = nil, lon: Double? = nil) -> CachedLocation {
        CachedLocation(
            id: id,
            name: "Pin",
            latitude: lat ?? self.lat,
            longitude: lon ?? self.lon
        )
    }

    // MARK: - Encode / decode seam

    func testDecodeMissingFieldIsEmptyBackwardCompatible() {
        let samples = WatchLocationsBrightnessPriming.decodeSamples(from: ["status": "ok"])
        XCTAssertTrue(samples.isEmpty)
    }

    func testEncodeDecodeRoundTrip() throws {
        let id = UUID()
        let s = sample(id: id)
        let data = try XCTUnwrap(WatchLocationsBrightnessPriming.encodeSamples([s]))
        let decoded = WatchLocationsBrightnessPriming.decodeSamples(
            from: [WatchLocationsBrightnessPriming.replyPayloadKey: data]
        )
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.savedLocationID, id)
        XCTAssertEqual(decoded.first?.modeledZenithSkyBrightness, 18.5)
    }

    func testEncodeEmptyReturnsNil() {
        XCTAssertNil(WatchLocationsBrightnessPriming.encodeSamples([]))
    }

    // MARK: - Apply to cache

    func testThreeValidSamplesPrimeCache() {
        let ids = [UUID(), UUID(), UUID()]
        let locations = ids.map { pin(id: $0) }
        let samples = ids.map { sample(id: $0) }
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)

        WatchLocationsBrightnessPriming.applyToCache(
            samples: samples,
            locations: locations,
            cache: cache
        )

        for id in ids {
            XCTAssertNotNil(
                cache.sample(forSavedLocationID: id, latitude: lat, longitude: lon)
            )
        }
    }

    func testPartialSamplesLeaveOthersUncached() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let locations = [pin(id: a), pin(id: b), pin(id: c)]
        // Only A and C have samples.
        let samples = [sample(id: a), sample(id: c)]
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)

        WatchLocationsBrightnessPriming.applyToCache(
            samples: samples,
            locations: locations,
            cache: cache
        )

        XCTAssertNotNil(cache.sample(forSavedLocationID: a, latitude: lat, longitude: lon))
        XCTAssertNil(cache.sample(forSavedLocationID: b, latitude: lat, longitude: lon))
        XCTAssertNotNil(cache.sample(forSavedLocationID: c, latitude: lat, longitude: lon))
    }

    func testStaleDatasetNotUsable() {
        let id = UUID()
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)
        WatchLocationsBrightnessPriming.applyToCache(
            samples: [sample(id: id, revision: 99)],
            locations: [pin(id: id)],
            cache: cache
        )
        // Physically retained if structural upsert ran after validity check — applyToCache
        // must not upsert invalid samples at all.
        XCTAssertNil(cache.sample(forSavedLocationID: id, latitude: lat, longitude: lon))
        XCTAssertNil(cache.documentSnapshotForTesting().samplesBySavedLocationID[id.uuidString])
    }

    func testWrongSavedLocationIDRejected() {
        let pinID = UUID()
        let otherID = UUID()
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)
        WatchLocationsBrightnessPriming.applyToCache(
            samples: [sample(id: otherID)],
            locations: [pin(id: pinID)],
            cache: cache
        )
        XCTAssertNil(cache.sample(forSavedLocationID: pinID, latitude: lat, longitude: lon))
        XCTAssertNil(cache.sample(forSavedLocationID: otherID, latitude: lat, longitude: lon))
    }

    func testMovedCoordinatesRejected() {
        let id = UUID()
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)
        // Sample at home coords; pin moved ~2+ km.
        WatchLocationsBrightnessPriming.applyToCache(
            samples: [sample(id: id)],
            locations: [pin(id: id, lat: lat + 0.02)],
            cache: cache
        )
        XCTAssertNil(
            cache.sample(forSavedLocationID: id, latitude: lat + 0.02, longitude: lon)
        )
    }

    func testMalformedNilIDSampleRejected() {
        let id = UUID()
        let clSample = ModeledZenithBrightnessSample(
            latitude: lat,
            longitude: lon,
            modeledZenithSkyBrightness: 18.5,
            dataset: LightPollutionDatasetIdentity.current,
            sampledAt: Date().addingTimeInterval(-60),
            savedLocationID: nil
        )
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)
        WatchLocationsBrightnessPriming.applyToCache(
            samples: [clSample, sample(id: id)],
            locations: [pin(id: id)],
            cache: cache
        )
        // CL sample must not prime saved path; valid saved sample still applied.
        XCTAssertNil(cache.documentSnapshotForTesting().currentLocationSample)
        XCTAssertNotNil(cache.sample(forSavedLocationID: id, latitude: lat, longitude: lon))
    }

    func testOmissionDoesNotDeleteExistingCache() {
        let id = UUID()
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)
        cache.upsert(sample(id: id, brightness: 18.5))
        XCTAssertNotNil(cache.sample(forSavedLocationID: id, latitude: lat, longitude: lon))

        // Later locations reply with empty samples — must not clear.
        WatchLocationsBrightnessPriming.applyToCache(
            samples: [],
            locations: [pin(id: id)],
            cache: cache
        )
        XCTAssertEqual(
            cache.sample(forSavedLocationID: id, latitude: lat, longitude: lon)?
                .modeledZenithSkyBrightness,
            18.5
        )
    }

    func testCurrentSampleReplacesOlderForSameID() {
        let id = UUID()
        let cache = AppGroupWatchModeledBrightnessCache(document: .empty(), baseURL: nil)
        cache.upsert(sample(id: id, brightness: 16.0))
        WatchLocationsBrightnessPriming.applyToCache(
            samples: [sample(id: id, brightness: 18.5)],
            locations: [pin(id: id)],
            cache: cache
        )
        XCTAssertEqual(
            cache.sample(forSavedLocationID: id, latitude: lat, longitude: lon)?
                .modeledZenithSkyBrightness,
            18.5
        )
    }

    func testPhoneValidSamplesSourceFiltersInvalidPins() {
        // When iOS store is empty/missing, validSamples is empty (no invent).
        let id = UUID()
        let locations = [pin(id: id)]
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-lp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let samples = WatchLocationsBrightnessPriming.validSamples(
            for: locations,
            baseURL: temp
        )
        XCTAssertTrue(samples.isEmpty)
    }

    func testPhoneValidSamplesReadsDurableIOSStore() throws {
        let id = UUID()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ios-lp-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let s = sample(id: id)
        var doc = SavedLocationModeledBrightnessDocument.empty()
        doc.samplesBySavedLocationID[id.uuidString] = s
        let store = SavedLocationModeledBrightnessStore(baseURL: temp)
        XCTAssertTrue(store.write(doc))

        let locations = [pin(id: id)]
        let samples = WatchLocationsBrightnessPriming.validSamples(
            for: locations,
            baseURL: temp
        )
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.savedLocationID, id)
    }
}
