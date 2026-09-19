@testable import SharedCode
import XCTest

final class SavedLocationModeledBrightnessStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-companion-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private var store: SavedLocationModeledBrightnessStore {
        SavedLocationModeledBrightnessStore(baseURL: tempDirectory)
    }

    private func sample(
        id: UUID,
        lat: Double = 45.45,
        lon: Double = -122.75,
        brightness: Double = 18.5
    ) -> ModeledZenithBrightnessSample {
        ModeledZenithBrightnessSample(
            latitude: lat,
            longitude: lon,
            modeledZenithSkyBrightness: brightness,
            dataset: .current,
            sampledAt: Date(timeIntervalSince1970: 2_000_000_000),
            savedLocationID: id
        )
    }

    func testMissingFileReturnsMissing() {
        XCTAssertEqual(store.load(), .missing)
    }

    func testRoundTripV1Document() {
        let id = UUID()
        var document = SavedLocationModeledBrightnessDocument.empty()
        document.samplesBySavedLocationID[id.uuidString] = sample(id: id)
        XCTAssertTrue(store.write(document))

        switch store.load() {
        case .ready(let loaded):
            XCTAssertEqual(loaded.schemaVersion, 1)
            XCTAssertEqual(loaded.samplesBySavedLocationID[id.uuidString]?.modeledZenithSkyBrightness, 18.5)
            XCTAssertEqual(loaded.samplesBySavedLocationID[id.uuidString]?.savedLocationID, id)
        default:
            XCTFail("Expected ready document")
        }
    }

    func testMalformedJSONReturnsMalformed() throws {
        let url = tempDirectory.appendingPathComponent(SavedLocationModeledBrightnessStore.fileName)
        try Data("{not-json".utf8).write(to: url)
        XCTAssertEqual(store.load(), .malformed)
    }

    func testUnsupportedSchemaVersion() throws {
        let payload: [String: Any] = [
            "schemaVersion": 999,
            "samplesBySavedLocationID": [:] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(
            to: tempDirectory.appendingPathComponent(SavedLocationModeledBrightnessStore.fileName)
        )
        XCTAssertEqual(store.load(), .unsupportedSchema(foundVersion: 999))
    }

    func testStructuralScrubDropsIllegalEntries() {
        let goodID = UUID()
        let badKeyID = UUID()
        let mismatchedID = UUID()
        var document = SavedLocationModeledBrightnessDocument.empty()
        document.samplesBySavedLocationID[goodID.uuidString] = sample(id: goodID)
        // Key is not a UUID string
        document.samplesBySavedLocationID["not-a-uuid"] = sample(id: badKeyID)
        // Key does not match sample.savedLocationID
        document.samplesBySavedLocationID[mismatchedID.uuidString] = sample(id: goodID)
        // Illegal coordinates
        document.samplesBySavedLocationID[UUID().uuidString] = ModeledZenithBrightnessSample(
            latitude: 91,
            longitude: 0,
            modeledZenithSkyBrightness: 18.5,
            savedLocationID: UUID()
        )
        // Out-of-range brightness
        let brightID = UUID()
        document.samplesBySavedLocationID[brightID.uuidString] = ModeledZenithBrightnessSample(
            latitude: 0,
            longitude: 0,
            modeledZenithSkyBrightness: 5,
            savedLocationID: brightID
        )

        XCTAssertTrue(store.write(document))
        switch store.load() {
        case .ready(let loaded):
            XCTAssertEqual(loaded.samplesBySavedLocationID.count, 1)
            XCTAssertNotNil(loaded.samplesBySavedLocationID[goodID.uuidString])
        default:
            XCTFail("Expected ready document")
        }
    }
}
