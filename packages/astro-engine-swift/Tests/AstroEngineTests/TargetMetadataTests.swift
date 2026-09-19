import XCTest
import Foundation
@testable import AstroEngine

final class TargetMetadataTests: XCTestCase {
    func testManualFixtures() throws { try checkFixtures("target-metadata") }

    private func checkFixtures(_ name: String) throws {
        let root = try ContractsRoot.resolve().appendingPathComponent("fixtures/capabilities/\(name)")
        let fixtures = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            let input = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("input.json"))) as! [String: Any]
            let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("expected.json"))) as! [String: Any]
            let injected = input["injected"] as! [String: Any]
            let evaluate: ([String: Any]) throws -> [String: Any] = { try TargetMetadataContract.evaluate(input["capability"] as! String, input: $0) }
            if expected["ok"] as? Bool == true {
                let actual = try evaluate(injected)
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
                    try JSONSerialization.data(withJSONObject: expected["result"]!, options: [.sortedKeys]), fixture.lastPathComponent)
            } else {
                XCTAssertThrowsError(try evaluate(injected), fixture.lastPathComponent) { error in
                    XCTAssertEqual((error as? TargetMetadataInputError)?.message,
                        (expected["error"] as? [String: Any])?["message"] as? String, fixture.lastPathComponent)
                }
            }
        }
    }


    func testM77ComposesWithEquipmentEvaluator() throws {
        for (aperture, level) in [(30.0, EquipmentFitLevel.good), (50.0, .excellent)] {
            let matches = EquipmentMatchingRules().ranked(isPlanet: false,
                requirement: TargetMetadata.requirement(id: "m77", type: .deepSky, objectType: .galaxy),
                capabilities: [.init(key: "smart", type: .smartTelescope, apertureMillimeters: aperture, magnification: nil)])
            XCTAssertEqual(matches.first?.level, level)
            XCTAssertEqual(matches.first?.mode, .electronicallyAssisted)
        }
    }

    func testCanonicalRequirementsAllComposeWithExistingContract() throws {
        let root = try ContractsRoot.resolve().appendingPathComponent("data/catalog/target-requirements.json")
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: root)) as! [String: Any]
        let overrides = data["overrides"] as! [String: [String: Any]]
        let fallbacks = data["fallbacks"] as! [String: [String: Any]]
        XCTAssertEqual(overrides.count, 20)
        for row in [data["default"] as! [String: Any]] + Array(overrides.values) + Array(fallbacks.values) {
            let match = try Phase15Contracts.equipment(["requirement": row, "capabilities": []])
            XCTAssertTrue(match["match"] is NSNull)
        }
    }

    func testNonfiniteSensitivityIsRejectedEvenForNonNebula() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try TargetMetadataContract.evaluate("targets.moon_sensitivity",
                input: ["object_type": "galaxy", "surface_brightness": value]))
        }
    }
}
