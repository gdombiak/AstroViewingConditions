import XCTest
import Foundation
@testable import AstroEngine

final class LocationCompositionTests: XCTestCase {
    func testCapabilityIDsAndTransportCaps() {
        XCTAssertEqual(LocationScoreComposition.capabilityID, "location.compose_scores")
        XCTAssertEqual(LocationScoreCompositionContract.capabilityID, LocationScoreComposition.capabilityID)
        XCTAssertEqual(LocationRecommendabilityFilter.capabilityID, "location.filter_recommendable")
        XCTAssertEqual(
            LocationRecommendabilityFilterContract.capabilityID,
            LocationRecommendabilityFilter.capabilityID
        )
        XCTAssertEqual(LocationScoreCompositionContract.maxCandidateCount, 885)
        XCTAssertEqual(LocationRecommendabilityFilterContract.maxCandidateCount, 885)
    }

    func testTypedCompositionPreservesScorableOrderAndSignedDeltas() throws {
        let result = try LocationScoreComposition.compose([
            candidate(night: 70, oq: 60),
            candidate(night: 99, oq: 99, hasRows: false, hasLP: false),
            candidate(isCenter: true, night: 74, oq: 66),
            candidate(night: 10, oq: 66),
        ])
        XCTAssertEqual(result.scoringMode, .observingQuality)
        XCTAssertEqual(result.candidates.map(\.inputIndex), [0, 2, 3])
        XCTAssertEqual(result.candidates.map(\.publicScore), [60, 66, 66])
        XCTAssertEqual(result.candidates.map(\.improvementOverCenter), [-6, 0, 0])
    }

    func testTypedCompositionFallsBackSearchWide() throws {
        let result = try LocationScoreComposition.compose([
            candidate(isCenter: true, night: 74, oq: 66),
            candidate(night: 80, oq: 90, hasLP: false),
        ])
        XCTAssertEqual(result.scoringMode, .nightConditionsFallback)
        XCTAssertEqual(result.candidates.map(\.publicScore), [74, 80])
        XCTAssertEqual(result.candidates.map(\.improvementOverCenter), [0, 6])
    }

    func testTypedCompositionAllowsNoCenter() throws {
        let result = try LocationScoreComposition.compose([
            candidate(night: 10, oq: 20),
        ])
        XCTAssertNil(result.candidates[0].improvementOverCenter)
    }

    func testContractsRejectOneRowOverTheSharedGridBound() {
        XCTAssertThrowsError(try LocationScoreCompositionContract.evaluate([
            "candidates": Array(repeating: NSNull(), count: 886),
        ])) { error in
            XCTAssertEqual(error as? LocationScoreCompositionError, .rowCap(maximum: 885))
        }
        XCTAssertThrowsError(try LocationRecommendabilityFilterContract.evaluate([
            "suitability": Array(repeating: NSNull(), count: 886),
        ])) { error in
            XCTAssertEqual(
                error as? LocationRecommendabilityFilterInputError,
                LocationRecommendabilityFilterInputError(rowCap: 885)
            )
        }
    }

    func testRichUnknownReasonsCollapseToRecommendable() {
        XCTAssertEqual(
            LocationRecommendabilityFilter.recommendableInputIndices(for: [
                .suitable,
                .unknown(reason: .notChecked),
                .unknown(reason: .geocodingFailed),
                .unknown(reason: .temporarilyUnavailable),
                .unchecked,
                .unsuitable(reason: "Water area"),
            ] as [LocationSuitabilityStatus]),
            [0, 1, 2, 3]
        )
    }

    func testNamedCompositionFixtures() throws {
        try assertFixtures(
            relative: "fixtures/capabilities/location-compose-scores",
            names: [
                "boolean-score-v1",
                "fractional-score-v1",
                "multiple-centers-v1",
                "no-scorable-locations-v1",
                "oq-mode-unscorable-lp-ignored-v1",
                "score-above-domain-v1",
                "search-wide-fallback-v1",
                "unknown-observing-quality-field-v1",
                "unscorable-center-boundary-scores-v1",
            ],
            evaluate: LocationScoreCompositionContract.evaluate
        )
    }

    func testNamedRecommendabilityFixtures() throws {
        try assertFixtures(
            relative: "fixtures/capabilities/location-filter-recommendable",
            names: ["empty-v1", "four-states-v1", "invalid-state-v1", "unknown-field-v1"],
            evaluate: LocationRecommendabilityFilterContract.evaluate
        )
    }

    private func candidate(
        isCenter: Bool = false,
        night: Int,
        oq: Int,
        hasRows: Bool = true,
        hasLP: Bool = true
    ) -> LocationScoreCompositionCandidate {
        LocationScoreCompositionCandidate(
            isCenter: isCenter,
            nightConditionsScore: night,
            hasNighttimeRows: hasRows,
            observingQuality: ObservingQualityCompositionInput(
                score: oq,
                hasValidLightPollution: hasLP
            )
        )
    }

    private func assertFixtures(
        relative: String,
        names expectedNames: [String],
        evaluate: ([String: Any]) throws -> [String: Any]
    ) throws {
        let root = try ContractsRoot.resolve()
        let directory = root.appendingPathComponent(relative)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        XCTAssertEqual(names, expectedNames)

        for name in names {
            let fixture = directory.appendingPathComponent(name)
            let input = try jsonObject(fixture.appendingPathComponent("input.json"))
            let expected = try jsonObject(fixture.appendingPathComponent("expected.json"))
            let injected = try XCTUnwrap(input["injected"] as? [String: Any])
            if expected["ok"] as? Bool == true {
                let actual = try evaluate(injected)
                let expectedResult = try XCTUnwrap(expected["result"] as? [String: Any])
                XCTAssertEqual(actual as NSDictionary, expectedResult as NSDictionary, name)
            } else {
                XCTAssertThrowsError(try evaluate(injected), name) { error in
                    let expectedError = expected["error"] as? [String: Any]
                    let code: String?
                    let message: String?
                    if let error = error as? LocationScoreCompositionError {
                        code = error.code
                        message = error.message
                    } else if let error = error as? LocationRecommendabilityFilterInputError {
                        code = error.code
                        message = error.message
                    } else {
                        code = nil
                        message = nil
                    }
                    XCTAssertEqual(code, expectedError?["code"] as? String, name)
                    XCTAssertEqual(message, expectedError?["message"] as? String, name)
                }
            }
        }
    }

    private func jsonObject(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(raw as? [String: Any])
    }
}
