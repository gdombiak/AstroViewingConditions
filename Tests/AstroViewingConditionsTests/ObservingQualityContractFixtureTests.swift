@testable import SharedCode
import XCTest

/// Additive F3 regression: existing XCTest bundle vs the OQ contract fixtures.
///
/// Does not generate or rewrite goldens. Production Swift still uses in-source literals.
final class ObservingQualityContractFixtureTests: XCTestCase {
    private let capabilityID = F3ObservingQualityContractSupport.capabilityID

    func testEngineSemverIs010() throws {
        XCTAssertEqual(try F3ObservingQualityContractSupport.engineSemver(), "0.1.0")
    }

    func testContractsRootAncestorWalkAndEnvOverride() throws {
        let walked = try F3ObservingQualityContractSupport.contractsDirectory(
            environment: [:],
            startingAt: URL(fileURLWithPath: #filePath)
        )
        XCTAssertEqual(
            try String(contentsOf: walked.appendingPathComponent("ENGINE_VERSION"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "0.1.0"
        )

        let viaEnv = try F3ObservingQualityContractSupport.contractsDirectory(
            environment: ["CONTRACTS_ROOT": walked.path]
        )
        XCTAssertEqual(
            viaEnv.resolvingSymlinksInPath().standardizedFileURL.path,
            walked.resolvingSymlinksInPath().standardizedFileURL.path
        )

        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("astro-f3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        XCTAssertThrowsError(
            try F3ObservingQualityContractSupport.contractsDirectory(
                environment: ["CONTRACTS_ROOT": emptyDir.path]
            )
        )
    }

    func testEngineSemverRangeHelper() throws {
        XCTAssertTrue(
            try F3ObservingQualityContractSupport.satisfies("0.1.0", range: ">=0.1.0 <2.0.0")
        )
        XCTAssertTrue(
            try F3ObservingQualityContractSupport.satisfies("1.9.9", range: ">=0.1.0 <2.0.0")
        )
        XCTAssertFalse(
            try F3ObservingQualityContractSupport.satisfies("2.0.0", range: ">=0.1.0 <2.0.0")
        )
        XCTAssertFalse(
            try F3ObservingQualityContractSupport.satisfies("0.0.9", range: ">=0.1.0 <2.0.0")
        )
    }

    func testF3HelperReadsOQPolicyFieldsFromContract() throws {
        let root = try F3ObservingQualityContractSupport.contractsDirectory()
        let oq = try F3ObservingQualityContractSupport.loadPolicyFields(
            "observing_quality",
            contractsRoot: root
        )
        XCTAssertEqual(oq["score"], "exact")
        XCTAssertEqual(oq["light_pollution"], "null_or_object")
        XCTAssertEqual(oq["light_pollution.base_penalty"], "abs_1e9")
        XCTAssertEqual(oq["light_pollution.applied_penalty"], "abs_1e9")

        let anchor = try F3ObservingQualityContractSupport.loadPolicyFields(
            "observing_quality_anchor",
            contractsRoot: root
        )
        XCTAssertEqual(anchor["light_pollution.base_penalty"], "abs_1e12")
        XCTAssertEqual(anchor["light_pollution.modeled_zenith_sky_brightness"], "exact")
    }

    func testCanonicalJSONAnchorsMatchSwiftLiterals() throws {
        let url = try F3ObservingQualityContractSupport.contractsDirectory()
            .appendingPathComponent(F3ObservingQualityContractSupport.calibrationRelativePath)
        let json = try F3ObservingQualityContractSupport.loadJSONObject(url)

        XCTAssertEqual(
            Set(json.keys),
            [
                "score_min",
                "score_max",
                "plausible_brightness",
                "base_penalty_anchors",
                "usability_weight_anchors",
            ]
        )
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonInt(json["score_min"]), 0)
        XCTAssertEqual(F3ObservingQualityContractSupport.jsonInt(json["score_max"]), 100)

        let plausible = try XCTUnwrap(
            F3ObservingQualityContractSupport.asObject(json["plausible_brightness"])
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(plausible["min"]),
            ModeledZenithBrightnessValidity.minimumPlausibleBrightness
        )
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonDouble(plausible["max"]),
            ModeledZenithBrightnessValidity.maximumPlausibleBrightness
        )
        XCTAssertEqual(plausible["unit"] as? String, "mag/arcsec2")

        let jsonBase = try XCTUnwrap(
            F3ObservingQualityContractSupport.asArray(json["base_penalty_anchors"])
        )
        let swiftBase = ObservingQualityCalculator.basePenaltyAnchors
        XCTAssertEqual(jsonBase.count, swiftBase.count, "base_penalty_anchors count drifted")
        for (rawAnchor, swiftAnchor) in zip(jsonBase, swiftBase) {
            let jsonAnchor = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(rawAnchor))
            XCTAssertEqual(
                F3ObservingQualityContractSupport.jsonDouble(jsonAnchor["brightness"]),
                swiftAnchor.brightness
            )
            XCTAssertEqual(
                F3ObservingQualityContractSupport.jsonDouble(jsonAnchor["penalty"]),
                swiftAnchor.penalty
            )
        }

        let jsonWeight = try XCTUnwrap(
            F3ObservingQualityContractSupport.asArray(json["usability_weight_anchors"])
        )
        let swiftWeight = ObservingQualityCalculator.usabilityWeightAnchors
        XCTAssertEqual(jsonWeight.count, swiftWeight.count, "usability_weight_anchors count drifted")
        for (rawAnchor, swiftAnchor) in zip(jsonWeight, swiftWeight) {
            let jsonAnchor = try XCTUnwrap(F3ObservingQualityContractSupport.asObject(rawAnchor))
            XCTAssertEqual(
                F3ObservingQualityContractSupport.jsonDouble(jsonAnchor["score"]),
                swiftAnchor.score
            )
            XCTAssertEqual(
                F3ObservingQualityContractSupport.jsonDouble(jsonAnchor["weight"]),
                swiftAnchor.weight
            )
        }
    }

    func testAllObservingQualityContractFixtures() throws {
        let fixtures = try F3ObservingQualityContractSupport.loadAllFixtures()
        XCTAssertEqual(fixtures.count, 14, "expected 14 OQ contract fixtures")

        let version = try F3ObservingQualityContractSupport.engineSemver()
        XCTAssertEqual(version, "0.1.0")
        let contractsRoot = try F3ObservingQualityContractSupport.contractsDirectory()

        var failures: [String] = []
        for fixture in fixtures {
            do {
                try assertFixture(fixture, engineVersion: version, contractsRoot: contractsRoot)
            } catch {
                failures.append("\(fixture.id): \(error)")
            }
        }
        if !failures.isEmpty {
            XCTFail(failures.joined(separator: "\n"))
        }
    }

    private func assertFixture(
        _ fixture: F3ObservingQualityContractSupport.Fixture,
        engineVersion: String,
        contractsRoot: URL
    ) throws {
        XCTAssertEqual(fixture.capability, capabilityID, fixture.id)
        XCTAssertEqual(fixture.origin, "manual", fixture.id)
        XCTAssertTrue(fixture.hosts.contains("swift"), "\(fixture.id) hosts: \(fixture.hosts)")
        XCTAssertTrue(
            try F3ObservingQualityContractSupport.satisfies(
                engineVersion,
                range: fixture.engineSemverRange
            ),
            "\(fixture.id): runtime \(engineVersion) does not satisfy \(fixture.engineSemverRange)"
        )

        XCTAssertNil(fixture.expected["engine_semver"], "\(fixture.id): expected.json must not pin engine_semver")
        XCTAssertEqual(
            F3ObservingQualityContractSupport.jsonBool(fixture.expected["ok"]),
            true,
            fixture.id
        )
        XCTAssertEqual(fixture.expected["capability"] as? String, capabilityID, fixture.id)
        XCTAssertEqual(fixture.input["capability"] as? String, capabilityID, fixture.id)

        let expectedResult = try XCTUnwrap(
            F3ObservingQualityContractSupport.asObject(fixture.expected["result"]),
            "\(fixture.id): expected.json missing result"
        )
        let injected = try F3ObservingQualityContractSupport.injectedInputs(from: fixture)
        let assessment = ObservingQualityCalculator.assess(
            nightConditionsScore: injected.night,
            modeledZenithSkyBrightness: injected.brightness
        )
        let actual = F3ObservingQualityContractSupport.contractResult(from: assessment)
        try F3ObservingQualityContractSupport.compareObservingQualityResult(
            actual,
            expected: expectedResult,
            policyID: fixture.equality,
            contractsRoot: contractsRoot
        )
    }
}
