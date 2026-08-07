@testable import SharedCode
import XCTest

/// Cross-checks against Python LPATLAS1 fixtures in Tools/LightPollution/fixtures/
/// and enforces decoder safety on malformed artifacts.
final class BinaryLightPollutionProviderTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AstroViewingConditionsTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    private var fixtureURL: URL {
        repoRoot.appendingPathComponent("Tools/LightPollution/fixtures/lpatlas1_tiny_constant.bin")
    }

    private var expectedURL: URL {
        repoRoot.appendingPathComponent("Tools/LightPollution/fixtures/lpatlas1_tiny_constant.lookups.json")
    }

    private var globalArtifactURL: URL {
        repoRoot.appendingPathComponent(
            "Tools/LightPollution/output/artifacts/light_pollution_global_v1.bin"
        )
    }

    private func loadFixtureBytes() throws -> Data {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixtureURL.path),
            "Checked-in fixture missing: \(fixtureURL.path)"
        )
        return try Data(contentsOf: fixtureURL)
    }

    private func fixtureMutating(_ body: (inout Data) -> Void) throws -> Data {
        var bytes = try loadFixtureBytes()
        body(&bytes)
        return bytes
    }

    private func writeU16(_ data: inout Data, _ offset: Int, _ value: UInt16) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private func writeU32(_ data: inout Data, _ offset: Int, _ value: UInt32) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeU64(_ data: inout Data, _ offset: Int, _ value: UInt64) {
        for i in 0..<8 {
            data[offset + i] = UInt8((value >> (8 * i)) & 0xFF)
        }
    }

    private func writeF64(_ data: inout Data, _ offset: Int, _ value: Double) {
        writeU64(&data, offset, value.bitPattern)
    }

    private func writeF32(_ data: inout Data, _ offset: Int, _ value: Float) {
        writeU32(&data, offset, value.bitPattern)
    }

    // MARK: - Fixture (mandatory)

    func testLoadFixtureAndLookupMatchesPythonManifest() throws {
        let provider = try BinaryLightPollutionProvider(fileURL: fixtureURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedURL.path),
            "Checked-in lookup JSON missing: \(expectedURL.path)"
        )
        let data = try Data(contentsOf: expectedURL)
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let lookups = try XCTUnwrap(obj["lookups"] as? [[String: Any]])
        XCTAssertFalse(lookups.isEmpty, "lookup manifest must not be empty")
        for row in lookups {
            let lat = try XCTUnwrap(row["lat"] as? Double)
            let lon = try XCTUnwrap(row["lon"] as? Double)
            let expected = row["value"] as? Double
            let got = provider.modeledZenithSkyBrightness(latitude: lat, longitude: lon)
            if expected == nil {
                XCTAssertNil(got, "lat \(lat) lon \(lon)")
            } else {
                let value = try XCTUnwrap(got, "lat \(lat) lon \(lon)")
                XCTAssertEqual(value, expected!, accuracy: 1e-5, "lat \(lat) lon \(lon)")
            }
        }
    }

    func testChildrenQuadrantsMatchPythonDequantizedValues() throws {
        let provider = try BinaryLightPollutionProvider(fileURL: fixtureURL)
        let cases: [(Double, Double, Double)] = [
            (74.9125, -179.9125, 18.016535541204018),
            (74.9125, -176.6625, 18.987952840609815),
            (71.6625, -179.9125, 19.996732343838907),
            (71.6625, -176.6625, 21.005511847068007),
        ]
        for (lat, lon, expected) in cases {
            let got = try XCTUnwrap(
                provider.modeledZenithSkyBrightness(latitude: lat, longitude: lon)
            )
            XCTAssertEqual(got, expected, accuracy: 1e-5)
        }
    }

    func testNonFiniteCoordinatesReturnNil() throws {
        let provider = try BinaryLightPollutionProvider(fileURL: fixtureURL)
        XCTAssertNil(provider.modeledZenithSkyBrightness(latitude: .nan, longitude: 0))
        XCTAssertNil(provider.modeledZenithSkyBrightness(latitude: 0, longitude: .infinity))
    }

    func testRepeatedLookupDeterministic() throws {
        let provider = try BinaryLightPollutionProvider(fileURL: fixtureURL)
        let data = try Data(contentsOf: expectedURL)
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let lookups = try XCTUnwrap(obj["lookups"] as? [[String: Any]])
        let first = try XCTUnwrap(lookups.first)
        let lat = try XCTUnwrap(first["lat"] as? Double)
        let lon = try XCTUnwrap(first["lon"] as? Double)
        let a = provider.modeledZenithSkyBrightness(latitude: lat, longitude: lon)
        let b = provider.modeledZenithSkyBrightness(latitude: lat, longitude: lon)
        XCTAssertEqual(a, b)
    }

    // MARK: - Basic rejections

    func testRejectsBadMagic() {
        var bytes = Data("BADMAGIC".utf8)
        bytes.append(Data(repeating: 0, count: 128))
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .badMagic)
        }
    }

    func testRejectsUnsupportedVersion() throws {
        let bytes = try fixtureMutating { data in
            writeU16(&data, 8, 99)
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .unsupportedVersion(99))
        }
    }

    func testRejectsTruncatedHeader() {
        let bytes = Data("LPATLAS1".utf8) + Data(repeating: 0, count: 10)
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .truncated)
        }
    }

    // MARK: - Header invariants

    func testRejectsRootCellsZero() throws {
        let bytes = try fixtureMutating { writeU16(&$0, 12, 0) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsPixelSizeZero() throws {
        let bytes = try fixtureMutating { writeF64(&$0, 40, 0.0) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsNonFinitePixelSize() throws {
        let bytes = try fixtureMutating { writeF64(&$0, 40, .nan) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsNonFiniteQuantization() throws {
        let bytes = try fixtureMutating { writeF32(&$0, 48, .nan) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsQMMaxNotGreaterThanQMMin() throws {
        let bytes = try fixtureMutating {
            writeF32(&$0, 48, 20.0)
            writeF32(&$0, 52, 20.0)
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsPristineOutsideQuantRange() throws {
        let bytes = try fixtureMutating { writeF32(&$0, 56, 30.0) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsZeroWidth() throws {
        let bytes = try fixtureMutating { writeU32(&$0, 16, 0) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsInconsistentNRootCols() throws {
        let bytes = try fixtureMutating { writeU16(&$0, 62, 1) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsRootIndexOffsetInsideHeader() throws {
        let bytes = try fixtureMutating { writeU32(&$0, 68, 64) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsRootDataOffsetInsideIndex() throws {
        let bytes = try fixtureMutating { writeU32(&$0, 72, 128) }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsDeclaredFileSizeSmallerThanActual() throws {
        let bytes = try fixtureMutating {
            let smaller = UInt32($0.count - 1)
            writeU32(&$0, 76, smaller)
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    func testRejectsDeclaredFileSizeLargerThanActual() throws {
        let bytes = try fixtureMutating {
            writeU32(&$0, 76, UInt32($0.count + 100))
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidHeader)
        }
    }

    // MARK: - Root index

    func testRejectsUInt64RootOffsetGreaterThanIntMax() throws {
        let bytes = try fixtureMutating {
            // First root index entry at 128: offset = UInt64.max
            writeU64(&$0, 128, UInt64.max)
            writeU32(&$0, 136, 1)
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidRootIndex)
        }
    }

    func testRejectsRootOffsetPlusLengthOutOfBounds() throws {
        let bytes = try fixtureMutating {
            // Keep offset valid-ish but claim huge length
            let off = readU64($0, 128)
            writeU64(&$0, 128, off)
            writeU32(&$0, 136, UInt32($0.count)) // almost surely OOB
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            let e = err as? BinaryLightPollutionProvider.Error
            XCTAssertTrue(e == .invalidRootIndex || e == .invalidNode)
        }
    }

    func testRejectsZeroLengthRootBlob() throws {
        let bytes = try fixtureMutating {
            writeU32(&$0, 136, 0)
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidRootIndex)
        }
    }

    func testRejectsRootBlobPointingIntoHeader() throws {
        let bytes = try fixtureMutating {
            writeU64(&$0, 128, 0)
            writeU32(&$0, 136, 1)
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidRootIndex)
        }
    }

    // MARK: - Node structure (eager at init)

    func testRejectsInvalidNodeTag() throws {
        let bytes = try fixtureMutating {
            // First root blob offset/length at 128
            let off = Int(readU64($0, 128))
            let len = Int(readU32($0, 136))
            XCTAssertGreaterThan(len, 0)
            XCTAssertLessThan(off, $0.count)
            $0[off] = 99 // invalid tag
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidNode)
        }
    }

    func testRejectsTruncatedRootBlob() throws {
        let bytes = try fixtureMutating {
            let off = Int(readU64($0, 128))
            // Claim length 1 but first root in fixture is children tree (longer).
            // Truncate by setting length to 1 while leaving only first byte (invalid incomplete tree).
            writeU32(&$0, 136, 1)
            // Ensure single byte is an incomplete children tag or constant without payload
            if off < $0.count {
                $0[off] = 3 // TAG_CONSTANT without code byte
            }
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            let e = err as? BinaryLightPollutionProvider.Error
            XCTAssertTrue(e == .invalidNode || e == .invalidRootIndex)
        }
    }

    func testRejectsCoarseFactorZero() throws {
        // Build a minimal valid shell from fixture: replace first root blob with coarse factor 0.
        let bytes = try fixtureMutating {
            let off = Int(readU64($0, 128))
            let len = Int(readU32($0, 136))
            // TAG_COARSE=5, factor u16 LE = 0, then would need grid — length short → invalidNode
            let payload = Data([5, 0, 0])
            // Keep same length by padding if needed, or shrink length to 3
            writeU32(&$0, 136, 3)
            for i in 0..<3 {
                if off + i < $0.count {
                    $0[off + i] = payload[i]
                }
            }
            // If original length was larger, shortening is fine as long as fileSize still matches
            // and other roots still valid. Shortening one blob leaves trailing orphan bytes in the
            // file that are not referenced — allowed by v1 (unreferenced padding).
            _ = len
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidNode)
        }
    }

    func testRejectsTruncatedMaskPayload() throws {
        let bytes = try fixtureMutating {
            let off = Int(readU64($0, 128))
            // TAG_DEFAULT_MASK=2 with only one mask byte (needs ceil(768*768/8))
            writeU32(&$0, 136, 2)
            if off < $0.count { $0[off] = 2 }
            if off + 1 < $0.count { $0[off + 1] = 0 }
        }
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bytes)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidNode)
        }
    }

    /// Proves malformed node data fails initialization (not silent NoData at lookup).
    func testMalformedNodeFailsInitializationNotLookupNil() throws {
        let good = try BinaryLightPollutionProvider(fileURL: fixtureURL)
        let goodVal = good.modeledZenithSkyBrightness(latitude: 74.9125, longitude: -179.9125)
        XCTAssertNotNil(goodVal, "precondition: fixture has data at TL quadrant")

        let bad = try fixtureMutating {
            let off = Int(readU64($0, 128))
            $0[off] = 99
        }
        // Must throw at init — must not construct a provider that returns nil as if NoData.
        XCTAssertThrowsError(try BinaryLightPollutionProvider(data: bad)) { err in
            XCTAssertEqual(err as? BinaryLightPollutionProvider.Error, .invalidNode)
        }
    }

    // MARK: - Optional global artifact

    /// Optional local cross-check against generated production artifact (gitignored).
    func testGlobalArtifactHomeAndStubMatchPython() throws {
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: globalArtifactURL.path),
            "Global artifact not present at \(globalArtifactURL.path)"
        )
        let t0 = CFAbsoluteTimeGetCurrent()
        let provider = try BinaryLightPollutionProvider(fileURL: globalArtifactURL)
        let initSec = CFAbsoluteTimeGetCurrent() - t0

        let home = try XCTUnwrap(
            provider.modeledZenithSkyBrightness(latitude: 45.45, longitude: -122.75)
        )
        let stub = try XCTUnwrap(
            provider.modeledZenithSkyBrightness(latitude: 45.736, longitude: -123.192)
        )
        XCTAssertEqual(home, 18.539606394730214, accuracy: 1e-6)
        XCTAssertEqual(stub, 21.341771681477702, accuracy: 1e-6)

        XCTAssertNil(provider.modeledZenithSkyBrightness(latitude: 80.0, longitude: 0.0))
        XCTAssertNil(provider.modeledZenithSkyBrightness(latitude: -70.0, longitude: 0.0))

        var lats = [Double]()
        var lons = [Double]()
        var seed: UInt64 = 70
        for _ in 0..<2000 {
            seed = seed &* 6364136223846793005 &+ 1
            let u1 = Double(seed % 10_000) / 10_000.0
            seed = seed &* 6364136223846793005 &+ 1
            let u2 = Double(seed % 10_000) / 10_000.0
            lats.append(-64.9 + u1 * (74.9 - (-64.9)))
            lons.append(-180.0 + u2 * 359.999)
        }
        let tCold = CFAbsoluteTimeGetCurrent()
        for i in 0..<lats.count {
            _ = provider.modeledZenithSkyBrightness(latitude: lats[i], longitude: lons[i])
        }
        let coldSec = CFAbsoluteTimeGetCurrent() - tCold
        let tWarm = CFAbsoluteTimeGetCurrent()
        for _ in 0..<5 {
            for i in 0..<lats.count {
                _ = provider.modeledZenithSkyBrightness(latitude: lats[i], longitude: lons[i])
            }
        }
        let warmSec = (CFAbsoluteTimeGetCurrent() - tWarm) / 5.0
        print(
            String(
                format: "LPATLAS1 Swift init=%.3fs cold_us=%.1f warm_us=%.1f file=%@",
                initSec,
                coldSec / Double(lats.count) * 1e6,
                warmSec / Double(lats.count) * 1e6,
                globalArtifactURL.lastPathComponent
            )
        )
        XCTAssertLessThan(warmSec / Double(lats.count), 0.002)
    }

    // MARK: - LE helpers for tests

    private func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(data[offset + i]) << (8 * i)
        }
        return v
    }
}
