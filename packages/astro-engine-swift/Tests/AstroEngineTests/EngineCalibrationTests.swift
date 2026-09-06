import XCTest
import Foundation
@testable import AstroEngine

final class EngineCalibrationTests: XCTestCase {
    func testLoadFromContractsRootDecodesProductionDomains() throws {
        let calibration = try EngineCalibration.loadFromContractsRoot()
        XCTAssertEqual(calibration.observingQuality.basePenaltyAnchors.count, 6)
        XCTAssertEqual(calibration.observingQuality.usabilityWeightAnchors.count, 4)
        XCTAssertEqual(calibration.nightQuality.weightRegimes.neither.cloud, 0.55)
        XCTAssertEqual(calibration.fog.humidity.minPercent, 80)
        XCTAssertEqual(calibration.seeing.temperatureDeltaCelsius.count, 5)
        XCTAssertEqual(calibration.transparency.layerWeights.low, 0.50)
        XCTAssertEqual(EngineCalibration.current, calibration)
    }

    #if os(macOS)
    func testLoadResolvedOnMacOSIgnoresBundledCalibration() throws {
        let contracts = try EngineCalibration.loadFromContractsRoot()
        guard let bundledRoot = EngineCalibration.findBundledDataDirectory() else {
            XCTAssertEqual(try EngineCalibration.loadResolved(), contracts)
            return
        }

        let planted = bundledRoot.appendingPathComponent("calibration/observing-quality.json")
        XCTAssertTrue(
            FileManager.default.isReadableFile(atPath: planted.path),
            "bundled data directory must contain observing-quality.json"
        )
        let original = try Data(contentsOf: planted)
        defer { try? original.write(to: planted) }

        var json = try F3ObservingQualityContractSupport.loadJSONObject(planted)
        json["score_min"] = 7
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: planted)

        let resolved = try EngineCalibration.loadResolved()
        XCTAssertEqual(resolved, contracts)
        XCTAssertEqual(resolved.observingQuality.scoreMin, contracts.observingQuality.scoreMin)
        XCTAssertNotEqual(resolved.observingQuality.scoreMin, 7)
    }
    #endif

    func testFogJSONMatchesRuntimeModel() throws {
        let json = try loadCalibrationJSON("fog.json")
        let fog = try EngineCalibration.loadFromContractsRoot().fog
        let humidity = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["humidity"]))
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonInt(humidity["min_percent"]), fog.humidity.minPercent)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(humidity["span_percent"]), fog.humidity.spanPercent)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(humidity["max_points"]), fog.humidity.maxPoints)
        let dew = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["dew_spread"]))
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(dew["max_celsius"]), fog.dewSpread.maxCelsius)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(dew["max_points"]), fog.dewSpread.maxPoints)
        let visibility = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["visibility"]))
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(visibility["max_meters"]), fog.visibility.maxMeters)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(visibility["max_points"]), fog.visibility.maxPoints)
        let lowCloud = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["low_cloud"]))
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonInt(lowCloud["min_percent"]), fog.lowCloud.minPercent)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(lowCloud["span_percent"]), fog.lowCloud.spanPercent)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(lowCloud["max_points"]), fog.lowCloud.maxPoints)
        let wind = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["wind"]))
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(wind["max_meters_per_second"]),
            fog.wind.maxMetersPerSecond
        )
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(wind["max_points"]), fog.wind.maxPoints)
    }

    func testSeeingAndTransparencyJSONMatchRuntimeModel() throws {
        let seeingJSON = try loadCalibrationJSON("seeing.json")
        let seeing = try EngineCalibration.loadFromContractsRoot().seeing
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(seeingJSON["penalty_min"]), seeing.penaltyMin)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(seeingJSON["penalty_max"]), seeing.penaltyMax)
        try assertUpperBoundTable(
            F3ObservingQualityContractSupport.asArray(seeingJSON["temperature_delta_celsius"]),
            seeing.temperatureDeltaCelsius
        )
        try assertUpperBoundTable(
            F3ObservingQualityContractSupport.asArray(seeingJSON["upper_wind_200hpa"]),
            seeing.upperWind200hpa
        )

        let transparencyJSON = try loadCalibrationJSON("transparency.json")
        let transparency = try EngineCalibration.loadFromContractsRoot().transparency
        let layers = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(transparencyJSON["layer_weights"]))
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(layers["low"]), transparency.layerWeights.low)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(layers["mid"]), transparency.layerWeights.mid)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(layers["high"]), transparency.layerWeights.high)
        let combine = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(transparencyJSON["combine_weights"]))
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(combine["cloud"]), transparency.combineWeights.cloud)
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(combine["visibility"]),
            transparency.combineWeights.visibility
        )
        try assertUpperBoundTable(
            F3ObservingQualityContractSupport.asArray(transparencyJSON["cloud_cover"]),
            transparency.cloudCover
        )
        let visTable = try XCTUnwrap(F3ObservingQualityContractSupport.asArray(transparencyJSON["visibility_meters"]))
        XCTAssertEqual(visTable.count, transparency.visibilityMeters.count)
        for (raw, bucket) in zip(visTable, transparency.visibilityMeters) {
            let obj = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(raw))
            if F3ObservingQualityContractSupport.isNull(obj["min"]) {
                XCTAssertNil(bucket.min)
            } else {
                XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["min"]), bucket.min)
            }
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["score"]), bucket.score)
        }
    }

    func testNightQualityWeightRegimesMatchRuntimeModel() throws {
        let json = try loadCalibrationJSON("night-quality.json")
        let night = try EngineCalibration.loadFromContractsRoot().nightQuality
        let regimes = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(json["weight_regimes"]))
        try assertRegime(
            F3ObservingQualityContractSupport.asObject(regimes["transparency_and_seeing"]),
            night.weightRegimes.transparencyAndSeeing
        )
        try assertRegime(
            F3ObservingQualityContractSupport.asObject(regimes["transparency_only"]),
            night.weightRegimes.transparencyOnly
        )
        try assertRegime(
            F3ObservingQualityContractSupport.asObject(regimes["seeing_only"]),
            night.weightRegimes.seeingOnly
        )
        try assertRegime(
            F3ObservingQualityContractSupport.asObject(regimes["neither"]),
            night.weightRegimes.neither
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(json["fog_penalty_divisor"]),
            night.fogPenaltyDivisor
        )
        let cloudTable = try XCTUnwrap(F3ObservingQualityContractSupport.asArray(json["cloud_cover_score_table"]))
        XCTAssertEqual(cloudTable.count, night.cloudCoverScoreTable.count)
        for (raw, bucket) in zip(cloudTable, night.cloudCoverScoreTable) {
            let obj = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(raw))
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonInt(obj["max"]), bucket.max)
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["score"]), bucket.score)
        }
    }

    func testCanonicalFilesAreLoadedWithoutGeneratedCopy() throws {
        let contracts = try F3ObservingQualityContractSupport.contractsDirectory()
        let calibration = try EngineCalibration.load(
            fromDataDirectory: contracts.appendingPathComponent("data")
        )
        XCTAssertEqual(calibration.fog.wind.maxPoints, 15)
        XCTAssertEqual(calibration.seeing.penaltyMax, 2.0)
        XCTAssertEqual(calibration.transparency.combineWeights.cloud, 0.75)
    }

    func testMissingRequiredFileFails() throws {
        let temp = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let calibrationDir = temp.appendingPathComponent("calibration", isDirectory: true)
        try FileManager.default.createDirectory(at: calibrationDir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try EngineCalibration.load(fromDataDirectory: temp)) { error in
            guard let typed = error as? EngineCalibrationError,
                  case .missingFile = typed else {
                return XCTFail("expected missingFile, got \(error)")
            }
        }
    }

    func testMalformedJSONFails() throws {
        let temp = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try copyCanonicalCalibration(to: temp)
        let fog = temp.appendingPathComponent("calibration/fog.json")
        try Data("{".utf8).write(to: fog)
        XCTAssertThrowsError(try EngineCalibration.load(fromDataDirectory: temp)) { error in
            guard let typed = error as? EngineCalibrationError,
                  case .decode = typed else {
                return XCTFail("expected decode, got \(error)")
            }
        }
    }

    func testMissingRequiredKeyFails() throws {
        let temp = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try copyCanonicalCalibration(to: temp)
        let fog = temp.appendingPathComponent("calibration/fog.json")
        try Data(#"{"score_min":0,"score_max":100}"#.utf8).write(to: fog)
        XCTAssertThrowsError(try EngineCalibration.load(fromDataDirectory: temp)) { error in
            guard let typed = error as? EngineCalibrationError,
                  case .decode = typed else {
                return XCTFail("expected decode, got \(error)")
            }
        }
    }

    func testUnsortedObservingQualityAnchorsFailValidation() throws {
        let temp = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        try copyCanonicalCalibration(to: temp)
        let url = temp.appendingPathComponent("calibration/observing-quality.json")
        var json = try F3ObservingQualityContractSupport.loadJSONObject(url)
        json["base_penalty_anchors"] = [
            ["brightness": 18.5, "penalty": 7.0],
            ["brightness": 17.5, "penalty": 8.0],
        ]
        try writeJSON(json, to: url)
        XCTAssertThrowsError(try EngineCalibration.load(fromDataDirectory: temp)) { error in
            guard let typed = error as? EngineCalibrationError,
                  case .invalid = typed else {
                return XCTFail("expected invalid, got \(error)")
            }
        }
    }

    func testIntegerJSONNumbersPreserveArithmeticTypes() throws {
        let fog = try EngineCalibration.loadFromContractsRoot().fog
        XCTAssertEqual(fog.humidity.minPercent, 80)
        XCTAssertEqual(fog.humidity.spanPercent, 20)
        XCTAssertEqual(fog.humidity.maxPoints, 40)
        let score = Int((Double(96) - Double(fog.humidity.minPercent)) / fog.humidity.spanPercent * fog.humidity.maxPoints)
        XCTAssertEqual(score, 32)
    }

    func testTargetScoringIsBoundInProductionSnapshot() throws {
        let contracts = try F3ObservingQualityContractSupport.contractsDirectory()
        let target = contracts.appendingPathComponent("data/calibration/target-scoring.json")
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: target.path))
        let snapshot = try EngineCalibration.loadFromContractsRoot()
        XCTAssertEqual(snapshot.targetScoring.altitude.weight, 30)
        XCTAssertEqual(snapshot.equipmentMatching.preferences.visual_preferred, 85)
    }

    func testBundleEngineDataCopiesCanonicalFilesAndRemovesStale() throws {
        let contracts = try F3ObservingQualityContractSupport.contractsDirectory()
        let repo = contracts.deletingLastPathComponent()
        let script = repo.appendingPathComponent("scripts/bundle-engine-data")
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: script.path), script.path)

        let dest = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dest) }

        try runBundleScript(script, repoRoot: repo, destination: dest)
        try assertCopiedBytesMatchCanonical(contracts: contracts, dest: dest)

        let stale = dest.appendingPathComponent("calibration/obsolete.json")
        try Data("stale".utf8).write(to: stale)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.path))
        let staleCatalog = dest.appendingPathComponent("catalog/equipment-limits.json")
        try Data("stale".utf8).write(to: staleCatalog)

        try runBundleScript(script, repoRoot: repo, destination: dest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "stale generated files must be removed")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staleCatalog.path),
            "stale generated catalog files must be removed"
        )
        try assertCopiedBytesMatchCanonical(contracts: contracts, dest: dest)

        let first = try contentsByName(in: dest.appendingPathComponent("calibration"))
        try runBundleScript(script, repoRoot: repo, destination: dest)
        let second = try contentsByName(in: dest.appendingPathComponent("calibration"))
        XCTAssertEqual(first, second)

        let git = try runGit(in: repo, arguments: ["check-ignore", "-q", "packages/astro-engine-swift/Sources/AstroEngine/Resources/data/calibration/fog.json"])
        XCTAssertEqual(git, 0, "generated calibration JSON must be gitignored")
        XCTAssertEqual(
            try runGit(in: repo, arguments: [
                "check-ignore", "-q",
                "packages/astro-engine-swift/Sources/AstroEngine/Resources/data/catalog/deep-sky.json",
            ]),
            0,
            "generated catalog JSON must be gitignored"
        )
    }

    func testBundleEngineDataPreservesDestinationPathsWithSpaces() throws {
        let contracts = try F3ObservingQualityContractSupport.contractsDirectory()
        let repo = contracts.deletingLastPathComponent()
        let script = repo.appendingPathComponent("scripts/bundle-engine-data")
        let parent = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let dest = parent.appendingPathComponent("engine data dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        try runBundleScript(script, repoRoot: repo, destination: dest)
        try assertCopiedBytesMatchCanonical(contracts: contracts, dest: dest)
    }

    func testGeneratedCalibrationPathIsIgnoredAndPackageSourceIsNot() throws {
        let contracts = try F3ObservingQualityContractSupport.contractsDirectory()
        let repo = contracts.deletingLastPathComponent()
        XCTAssertEqual(
            try runGit(in: repo, arguments: [
                "check-ignore", "-q",
                "packages/astro-engine-swift/Sources/AstroEngine/Resources/data/calibration/fog.json",
            ]),
            0
        )
        XCTAssertEqual(
            try runGit(in: repo, arguments: [
                "check-ignore", "-q",
                "packages/astro-engine-swift/Sources/AstroEngine/Scoring/FogCalculator.swift",
            ]),
            1
        )
        XCTAssertEqual(
            try runGit(in: repo, arguments: [
                "check-ignore", "-q",
                "contracts/data/calibration/fog.json",
            ]),
            1
        )
        XCTAssertEqual(
            try runGit(in: repo, arguments: [
                "check-ignore", "-q",
                "packages/astro-engine-swift/Sources/AstroEngine/Resources/data/catalog/deep-sky.json",
            ]),
            0
        )
        XCTAssertEqual(
            try runGit(in: repo, arguments: [
                "check-ignore", "-q",
                "contracts/data/catalog/deep-sky.json",
            ]),
            1
        )
    }

    private func loadCalibrationJSON(_ name: String) throws -> [String: Any] {
        let url = try F3ObservingQualityContractSupport.contractsDirectory()
            .appendingPathComponent("data/calibration/\(name)")
        return try F3ObservingQualityContractSupport.loadJSONObject(url)
    }

    private func assertUpperBoundTable(
        _ raw: [Any]?,
        _ buckets: [UpperBoundScoreBucket]
    ) throws {
        let json = try XCTUnwrap(raw)
        XCTAssertEqual(json.count, buckets.count)
        for (item, bucket) in zip(json, buckets) {
            let obj = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(item))
            if F3ObservingQualityContractSupport.isNull(obj["max"]) {
                XCTAssertNil(bucket.max)
            } else {
                XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["max"]), bucket.max)
            }
            XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(obj["score"]), bucket.score)
        }
    }

    private func assertRegime(
        _ raw: [String: Any]?,
        _ components: NightQualityCalibration.WeightedComponents
    ) throws {
        let json = try XCTUnwrap(raw)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(json["transparency"]), components.transparency)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(json["seeing"]), components.seeing)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(json["cloud"]), components.cloud)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(json["fog"]), components.fog)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(json["moon"]), components.moon)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonDouble(json["wind"]), components.wind)
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("astro-engine-cal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func copyCanonicalCalibration(to dataRoot: URL) throws {
        let source = try F3ObservingQualityContractSupport.contractsDirectory()
            .appendingPathComponent("data/calibration")
        let dest = dataRoot.appendingPathComponent("calibration", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in [
            "fog.json",
            "night-quality.json",
            "observing-quality.json",
            "seeing.json",
            "transparency.json",
            "target-scoring.json",
            "equipment-matching.json",
        ] {
            try FileManager.default.copyItem(
                at: source.appendingPathComponent(name),
                to: dest.appendingPathComponent(name)
            )
        }
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
    }

    private func runBundleScript(_ script: URL, repoRoot: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            "--repo-root", repoRoot.path,
            "--destination", destination.path,
        ]
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func assertCopiedBytesMatchCanonical(contracts: URL, dest: URL) throws {
        let canonical = contracts.appendingPathComponent("data/calibration")
        for name in [
            "fog.json",
            "night-quality.json",
            "observing-quality.json",
            "seeing.json",
            "transparency.json",
            "target-scoring.json",
            "equipment-matching.json",
        ] {
            let expected = try Data(contentsOf: canonical.appendingPathComponent(name))
            let actual = try Data(contentsOf: dest.appendingPathComponent("calibration").appendingPathComponent(name))
            XCTAssertEqual(actual, expected, name)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dest.appendingPathComponent("calibration/obsolete.json").path
            )
        )
        let catalogExpected = try Data(
            contentsOf: contracts.appendingPathComponent("data/catalog/deep-sky.json")
        )
        let catalogActual = try Data(
            contentsOf: dest.appendingPathComponent("catalog/deep-sky.json")
        )
        XCTAssertEqual(catalogActual, catalogExpected)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dest.appendingPathComponent("catalog/equipment-limits.json").path
            )
        )
    }

    private func contentsByName(in directory: URL) throws -> [String: Data] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        var result: [String: Data] = [:]
        for file in files where file.pathExtension == "json" {
            result[file.lastPathComponent] = try Data(contentsOf: file)
        }
        return result
    }

    private func runGit(in repo: URL, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repo
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
