import XCTest
import Foundation
@testable import AstroEngine

final class Phase15Tests: XCTestCase {
    func testTargetsFixtures() throws { try checkFixtures("targets-recommend", evaluate: Phase15Contracts.targets) }
    func testEquipmentFixtures() throws { try checkFixtures("equipment-match", evaluate: Phase15Contracts.equipment) }

    private func checkFixtures(_ name: String, evaluate: ([String: Any]) throws -> [String: Any]) throws {
        let root = try ContractsRoot.resolve().appendingPathComponent("fixtures/capabilities/\(name)")
        let fixtures = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            let input = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("input.json"))) as! [String: Any]
            let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("expected.json"))) as! [String: Any]
            let injected = input["injected"] as! [String: Any]
            if expected["ok"] as? Bool == true {
                let actual = try evaluate(injected)
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
                    try JSONSerialization.data(withJSONObject: expected["result"]!, options: [.sortedKeys]), fixture.lastPathComponent)
            } else {
                XCTAssertThrowsError(try evaluate(injected), fixture.lastPathComponent) { error in
                    XCTAssertEqual((error as? Phase15InputError)?.message,
                        (expected["error"] as? [String: Any])?["message"] as? String, fixture.lastPathComponent)
                }
            }
        }
    }

    func testInvalidNonfiniteTypedJSONFacts() throws {
        for invalid in [Double.nan, Double.infinity, -Double.infinity, 1e100] {
            XCTAssertThrowsError(try Phase15Contracts.equipment([
                "requirement": [:], "capabilities": [["key": "scope", "type": "visualTelescope", "aperture_mm": invalid]]
            ]))
        }
    }
}
