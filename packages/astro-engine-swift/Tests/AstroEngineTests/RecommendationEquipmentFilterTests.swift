import XCTest
@testable import AstroEngine

final class RecommendationEquipmentFilterTests: XCTestCase {
    func testThresholdTruthTable() {
        let levels = EquipmentFitLevel.allCases
        XCTAssertEqual(levels.filter(RecommendationEquipmentFitThreshold.any.includes), levels)
        XCTAssertEqual(
            levels.filter(RecommendationEquipmentFitThreshold.challengingOrBetter.includes),
            [.excellent, .good, .challenging]
        )
        XCTAssertEqual(
            levels.filter(RecommendationEquipmentFitThreshold.goodOrBetter.includes),
            [.excellent, .good]
        )
        XCTAssertEqual(
            levels.filter(RecommendationEquipmentFitThreshold.excellentOnly.includes),
            [.excellent]
        )
    }

    func testAnyAndEmptySavedInventoryBypassMissingFits() {
        let rows = [candidate("moon"), candidate("m77")]
        XCTAssertEqual(
            RecommendationEquipmentFilter.selected(
                candidates: rows,
                capabilities: [],
                hasSavedInventory: true,
                minimumFit: .any
            ).map(\.index),
            [0, 1]
        )
        XCTAssertEqual(
            RecommendationEquipmentFilter.selected(
                candidates: rows,
                capabilities: [],
                hasSavedInventory: false,
                minimumFit: .excellentOnly
            ).map(\.index),
            [0, 1]
        )
    }

    func testActiveFilterRejectsMissingFitAndNeverChangesOrderOrIdentity() {
        let rows = [candidate("m31"), candidate("m31"), candidate("jupiter", isPlanet: true)]
        XCTAssertTrue(RecommendationEquipmentFilter.selected(
            candidates: rows,
            capabilities: [],
            hasSavedInventory: true,
            minimumFit: .challengingOrBetter
        ).isEmpty)

        let nakedEye = EquipmentMatchCapability(
            key: "0", type: nil, apertureMillimeters: nil, magnification: nil
        )
        let selected = RecommendationEquipmentFilter.selected(
            candidates: rows,
            capabilities: [nakedEye],
            hasSavedInventory: true,
            minimumFit: .challengingOrBetter
        )
        XCTAssertEqual(selected.map(\.index), [0, 1, 2])
        XCTAssertEqual(selected.map(\.key), ["m31", "m31", "jupiter"])
    }

    func testSelectedCapabilityOrderDoesNotChangeBestFitFiltering() {
        let rows = [candidate("m45", requirement: Self.visualRequirement)]
        let modest = EquipmentMatchCapability(
            key: "1-modest", type: .visualTelescope,
            apertureMillimeters: 80, magnification: nil
        )
        let preferred = EquipmentMatchCapability(
            key: "1-preferred", type: .visualTelescope,
            apertureMillimeters: 120, magnification: nil
        )
        let first = RecommendationEquipmentFilter.selected(
            candidates: rows,
            capabilities: [modest, preferred],
            hasSavedInventory: true,
            minimumFit: .excellentOnly
        )
        let reversed = RecommendationEquipmentFilter.selected(
            candidates: rows,
            capabilities: [preferred, modest],
            hasSavedInventory: true,
            minimumFit: .excellentOnly
        )
        XCTAssertEqual(first, reversed)
        XCTAssertEqual(first.map(\.index), [0])
    }

    func testFilteringBeforeDisplayLimitCanReachLaterRankedRows() {
        let rejected = (0..<5).map { candidate("poor-\($0)", requirement: Self.unsupportedRequirement) }
        let survivor = candidate("sixth", requirement: Self.preferredNakedEyeRequirement)
        let selected = RecommendationEquipmentFilter.selected(
            candidates: rejected + [survivor],
            capabilities: [.init(key: "0", type: nil, apertureMillimeters: nil, magnification: nil)],
            hasSavedInventory: true,
            minimumFit: .goodOrBetter
        )
        XCTAssertEqual(Array(selected.prefix(5)).map(\.index), [5])
        XCTAssertTrue(RecommendationEquipmentFilter.selected(
            candidates: Array((rejected + [survivor]).prefix(5)),
            capabilities: [.init(key: "0", type: nil, apertureMillimeters: nil, magnification: nil)],
            hasSavedInventory: true,
            minimumFit: .goodOrBetter
        ).isEmpty)
    }

    func testContractFixtures() throws {
        let root = try ContractsRoot.resolve().appendingPathComponent(
            "fixtures/capabilities/filter-recommendations-by-equipment"
        )
        let fixtures = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ).sorted { $0.path < $1.path }
        XCTAssertEqual(fixtures.count, 12)

        for fixture in fixtures {
            let inputDocument = try JSONSerialization.jsonObject(
                with: Data(contentsOf: fixture.appendingPathComponent("input.json"))
            ) as! [String: Any]
            let expected = try JSONSerialization.jsonObject(
                with: Data(contentsOf: fixture.appendingPathComponent("expected.json"))
            ) as! [String: Any]
            let input = inputDocument["injected"] as! [String: Any]
            if expected["ok"] as? Bool == true {
                let actual = try RecommendationEquipmentFilterContract.evaluate(input)
                XCTAssertEqual(
                    try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
                    try JSONSerialization.data(withJSONObject: expected["result"]!, options: [.sortedKeys]),
                    fixture.lastPathComponent
                )
            } else {
                XCTAssertThrowsError(
                    try RecommendationEquipmentFilterContract.evaluate(input),
                    fixture.lastPathComponent
                ) { error in
                    let actual = error as? RecommendationEquipmentFilterInputError
                    let expectedError = expected["error"] as? [String: Any]
                    XCTAssertEqual(actual?.code, expectedError?["code"] as? String)
                    XCTAssertEqual(actual?.message, expectedError?["message"] as? String)
                }
            }
        }
    }

    func testContractChecksBothCapsBeforeIteration() {
        let valid = contractCandidate("row")
        let tooManyCandidates = Array(
            repeating: valid,
            count: RecommendationEquipmentFilterContract.maxCandidateCount + 1
        )
        XCTAssertThrowsError(try RecommendationEquipmentFilterContract.evaluate([
            "has_saved_inventory": false,
            "minimum_fit": "any",
            "capabilities": [],
            "candidates": tooManyCandidates,
        ])) { error in
            XCTAssertEqual((error as? RecommendationEquipmentFilterInputError)?.code, "sample_cap")
        }

        let capability: [String: Any] = [
            "key": "duplicate", "type": "nakedEye",
            "aperture_mm": NSNull(), "magnification": NSNull(),
        ]
        XCTAssertThrowsError(try RecommendationEquipmentFilterContract.evaluate([
            "has_saved_inventory": false,
            "minimum_fit": "any",
            "capabilities": Array(
                repeating: capability,
                count: RecommendationEquipmentFilterContract.maxCapabilityCount + 1
            ),
            "candidates": [],
        ])) { error in
            XCTAssertEqual((error as? RecommendationEquipmentFilterInputError)?.code, "sample_cap")
        }
    }

    func testContractRejectsUnknownFieldsWrongBooleansAndNonfiniteNumbers() {
        let base: [String: Any] = [
            "has_saved_inventory": true,
            "minimum_fit": "any",
            "capabilities": [],
            "candidates": [contractCandidate("moon")],
        ]
        var unknownTop = base
        unknownTop["limit"] = 5
        XCTAssertThrowsError(try RecommendationEquipmentFilterContract.evaluate(unknownTop))

        var candidate = contractCandidate("moon")
        candidate["score"] = 90
        var unknownCandidate = base
        unknownCandidate["candidates"] = [candidate]
        XCTAssertThrowsError(try RecommendationEquipmentFilterContract.evaluate(unknownCandidate))

        var requirement = candidate["requirement"] as! [String: Any]
        requirement["display_name"] = "Moon"
        candidate.removeValue(forKey: "score")
        candidate["requirement"] = requirement
        var unknownRequirement = base
        unknownRequirement["candidates"] = [candidate]
        XCTAssertThrowsError(try RecommendationEquipmentFilterContract.evaluate(unknownRequirement))

        var wrongBoolean = base
        var wrongBooleanCandidate = contractCandidate("moon")
        wrongBooleanCandidate["is_planet"] = 1
        wrongBoolean["candidates"] = [wrongBooleanCandidate]
        XCTAssertThrowsError(try RecommendationEquipmentFilterContract.evaluate(wrongBoolean))

        var nonfinite = base
        nonfinite["capabilities"] = [[
            "key": "scope", "type": "visualTelescope",
            "aperture_mm": Double.nan, "magnification": NSNull(),
        ] as [String: Any]]
        XCTAssertThrowsError(try RecommendationEquipmentFilterContract.evaluate(nonfinite))
    }

    private func candidate(
        _ key: String,
        isPlanet: Bool = false,
        requirement: TargetEquipmentRequirement = preferredNakedEyeRequirement
    ) -> RecommendationEquipmentFilter.Candidate {
        .init(key: key, isPlanet: isPlanet, requirement: requirement)
    }

    private static let preferredNakedEyeRequirement = TargetEquipmentRequirement(
        nakedEyeSuitability: .preferred
    )
    private static let unsupportedRequirement = TargetEquipmentRequirement()
    private static let visualRequirement = TargetEquipmentRequirement(
        practicalVisualApertureMillimeters: 75,
        preferredVisualApertureMillimeters: 100,
        framing: .compact
    )

    private func contractCandidate(_ key: String) -> [String: Any] {
        [
            "key": key,
            "is_planet": false,
            "requirement": [
                "naked_eye_suitability": "unsupported",
                "binocular_suitability": "unsuitable",
                "preferred_binocular_magnification": NSNull(),
                "practical_binocular_aperture_mm": NSNull(),
                "preferred_binocular_aperture_mm": NSNull(),
                "practical_visual_aperture_mm": NSNull(),
                "preferred_visual_aperture_mm": NSNull(),
                "practical_smart_eaa_aperture_mm": NSNull(),
                "preferred_smart_eaa_aperture_mm": NSNull(),
                "framing": "medium",
                "magnification_benefit": false,
                "smart_eaa_suitability": "poorMatch",
            ] as [String: Any],
        ]
    }
}
