@testable import SharedCode
import XCTest

final class CurrentLocationModeledBrightnessStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cl-companion-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private var store: CurrentLocationModeledBrightnessStore {
        CurrentLocationModeledBrightnessStore(baseURL: tempDirectory)
    }

    private func sample(
        lat: Double = 45.45,
        lon: Double = -122.75,
        brightness: Double = 18.5,
        savedLocationID: UUID? = nil
    ) -> ModeledZenithBrightnessSample {
        ModeledZenithBrightnessSample(
            latitude: lat,
            longitude: lon,
            modeledZenithSkyBrightness: brightness,
            dataset: .current,
            sampledAt: Date(timeIntervalSince1970: 2_000_000_000),
            savedLocationID: savedLocationID
        )
    }

    func testMissingFileReturnsMissing() {
        XCTAssertEqual(store.load(), .missing)
    }

    func testRoundTripValidSample() {
        var document = CurrentLocationModeledBrightnessDocument.empty()
        document.sample = sample()
        XCTAssertTrue(store.write(document))
        switch store.load() {
        case .ready(let loaded):
            XCTAssertEqual(loaded.schemaVersion, 1)
            XCTAssertEqual(loaded.sample?.modeledZenithSkyBrightness, 18.5)
            XCTAssertNil(loaded.sample?.savedLocationID)
        default:
            XCTFail("Expected ready")
        }
    }

    func testSavedLocationIDMustBeNil() {
        var document = CurrentLocationModeledBrightnessDocument.empty()
        document.sample = sample(savedLocationID: UUID())
        XCTAssertTrue(store.write(document))
        switch store.load() {
        case .ready(let loaded):
            XCTAssertNil(loaded.sample)
        default:
            XCTFail("Expected ready empty sample")
        }
    }

    func testMalformedReturnsMalformed() throws {
        try Data("{bad".utf8).write(
            to: tempDirectory.appendingPathComponent(CurrentLocationModeledBrightnessStore.fileName)
        )
        XCTAssertEqual(store.load(), .malformed)
    }

    func testUnsupportedSchema() throws {
        let payload: [String: Any] = [
            "schemaVersion": 999,
            "sample": NSNull()
        ]
        try JSONSerialization.data(withJSONObject: payload).write(
            to: tempDirectory.appendingPathComponent(CurrentLocationModeledBrightnessStore.fileName)
        )
        XCTAssertEqual(store.load(), .unsupportedSchema(foundVersion: 999))
    }

    func testZeroZeroRemainsStructurallyLegal() {
        // Phase 1 / store do not special-case (0,0).
        XCTAssertTrue(
            ModeledZenithBrightnessValidity.isValidGeographicCoordinate(latitude: 0, longitude: 0)
        )
        var document = CurrentLocationModeledBrightnessDocument.empty()
        document.sample = sample(lat: 0, lon: 0)
        XCTAssertTrue(store.write(document))
        switch store.load() {
        case .ready(let loaded):
            XCTAssertEqual(loaded.sample?.latitude, 0)
            XCTAssertEqual(loaded.sample?.longitude, 0)
        default:
            XCTFail("Expected ready with (0,0) sample")
        }
    }
}
