import AstroEngine
import Foundation
import XCTest

/// Focused tests for `targets.compose_recommendations`: the ordering rule, the
/// limit semantics and the strict transport.
final class RecommendationCompositionTests: XCTestCase {
    private func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)!
    }

    private func candidate(_ key: String, _ score: Int, _ time: String) -> RecommendationComposition.Candidate {
        RecommendationComposition.Candidate(key: key, score: score, bestTime: instant(time))
    }

    // MARK: - Ordering

    func testScoreDescendingIsThePrimaryKey() {
        let selected = RecommendationComposition.selected(candidates: [
            candidate("m31", 61, "2026-03-01T22:00:00Z"),
            candidate("moon", 84, "2026-03-01T21:00:00Z"),
            candidate("jupiter", 73, "2026-03-01T23:00:00Z"),
        ], limit: 5)

        XCTAssertEqual(selected.map(\.key), ["moon", "jupiter", "m31"])
        XCTAssertEqual(selected.map(\.index), [1, 2, 0])
    }

    func testEqualScoresBreakOnEarlierBestTime() {
        let selected = RecommendationComposition.selected(candidates: [
            candidate("saturn", 70, "2026-03-01T23:45:00Z"),
            candidate("m42", 70, "2026-03-01T20:15:00Z"),
            candidate("moon", 70, "2026-03-01T22:00:00Z"),
        ], limit: 5)

        XCTAssertEqual(selected.map(\.key), ["m42", "moon", "saturn"])
    }

    func testCompleteTiePreservesInputOrder() {
        let rows = ["venus", "m45", "moon", "mars"].map {
            candidate($0, 66, "2026-03-01T21:00:00Z")
        }

        XCTAssertEqual(
            RecommendationComposition.selected(candidates: rows, limit: 10).map(\.index),
            [0, 1, 2, 3]
        )
    }

    func testNoTargetTypeHasPriorityIndependentOfScoreAndBestTime() {
        // The Moon row is last in the input, has the lowest score and the latest
        // best time. Any type priority, id ordering or specialized tie breaker
        // would move it.
        let selected = RecommendationComposition.selected(candidates: [
            candidate("m31", 61, "2026-03-01T20:00:00Z"),
            candidate("jupiter", 61, "2026-03-01T21:00:00Z"),
            candidate("moon", 60, "2026-03-01T23:00:00Z"),
        ], limit: 5)

        XCTAssertEqual(selected.map(\.key), ["m31", "jupiter", "moon"])
    }

    func testDuplicateKeysArePreservedAndDisambiguatedByIndex() {
        let selected = RecommendationComposition.selected(candidates: [
            candidate("m31", 50, "2026-03-01T22:00:00Z"),
            candidate("m31", 70, "2026-03-01T22:00:00Z"),
            candidate("m31", 50, "2026-03-01T21:00:00Z"),
        ], limit: 5)

        XCTAssertEqual(selected.map(\.key), ["m31", "m31", "m31"])
        XCTAssertEqual(selected.map(\.index), [1, 2, 0])
    }

    func testCompositionMatchesTheSharedRankingPrimitive() {
        let rows = [
            candidate("a", 40, "2026-03-01T22:00:00Z"),
            candidate("b", 91, "2026-03-01T19:00:00Z"),
            candidate("c", 40, "2026-03-01T21:00:00Z"),
            candidate("d", 91, "2026-03-01T19:00:00Z"),
        ]

        XCTAssertEqual(
            RecommendationComposition.selected(candidates: rows, limit: 3).map(\.index),
            TargetScoring.rankedIndices(
                scores: rows.map(\.score), bestTimes: rows.map(\.bestTime), limit: 3)
        )
    }

    // MARK: - Limit

    func testLimitTruncatesAfterOrdering() {
        let selected = RecommendationComposition.selected(candidates: [
            candidate("m13", 55, "2026-03-01T20:30:00Z"),
            candidate("moon", 84, "2026-03-01T21:00:00Z"),
            candidate("jupiter", 73, "2026-03-01T23:00:00Z"),
        ], limit: 2)

        XCTAssertEqual(selected.map(\.key), ["moon", "jupiter"])
    }

    func testZeroAndNegativeLimitSelectNothing() {
        let rows = [candidate("moon", 84, "2026-03-01T21:00:00Z")]

        XCTAssertTrue(RecommendationComposition.selected(candidates: rows, limit: 0).isEmpty)
        XCTAssertTrue(RecommendationComposition.selected(candidates: rows, limit: -3).isEmpty)
    }

    func testLimitAboveCandidateCountReturnsEverything() {
        let rows = [
            candidate("moon", 84, "2026-03-01T21:00:00Z"),
            candidate("m31", 61, "2026-03-01T22:00:00Z"),
        ]

        XCTAssertEqual(RecommendationComposition.selected(candidates: rows, limit: 50).count, 2)
    }

    func testEmptyCandidatesComposeToNothing() {
        XCTAssertTrue(RecommendationComposition.selected(candidates: [], limit: 5).isEmpty)
        XCTAssertTrue(RecommendationComposition.selected(candidates: [], limit: -1).isEmpty)
    }

    // MARK: - Transport

    private func row(_ key: Any, _ score: Any, _ time: Any) -> [String: Any] {
        ["key": key, "score": score, "best_time": time]
    }

    private func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        try RecommendationCompositionContract.evaluate(input)
    }

    private func assertInvalid(
        _ input: [String: Any], code: String = "validation",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try evaluate(input), file: file, line: line) { error in
            guard let error = error as? RecommendationCompositionInputError else {
                return XCTFail("unexpected error \(error)", file: file, line: line)
            }
            XCTAssertEqual(error.code, code, file: file, line: line)
        }
    }

    func testTransportEmitsIndexAndKeyInProductionOrder() throws {
        let result = try evaluate([
            "candidates": [
                row("m31-w1", 61, "2026-03-01T22:00:00Z"),
                row("moon", 84, "2026-03-01T21:00:00Z"),
            ],
            "limit": 5,
        ])

        let selected = try XCTUnwrap(result["selected"] as? [[String: Any]])
        XCTAssertEqual(selected.map { $0["key"] as? String }, ["moon", "m31-w1"])
        XCTAssertEqual(selected.map { $0["index"] as? Int }, [1, 0])
    }

    func testTransportAcceptsIntegralFloats() throws {
        let result = try evaluate([
            "candidates": [row("moon", 84.0, "2026-03-01T21:00:00Z")],
            "limit": 1.0,
        ])
        XCTAssertEqual((result["selected"] as? [[String: Any]])?.count, 1)
    }

    func testTransportRejectsUnknownAndMissingFields() {
        assertInvalid(["candidates": [], "limit": 5, "tie_breaker": "type"])
        assertInvalid(["candidates": []])
        assertInvalid(["limit": 5])
        assertInvalid([
            "candidates": [["key": "moon", "score": 84,
                            "best_time": "2026-03-01T21:00:00Z", "type": "moon"]],
            "limit": 5,
        ])
        assertInvalid(["candidates": [["key": "moon", "score": 84]], "limit": 5])
    }

    func testTransportRejectsBooleansAsNumbers() {
        assertInvalid(["candidates": [row("moon", true, "2026-03-01T21:00:00Z")], "limit": 5])
        assertInvalid(["candidates": [], "limit": true])
    }

    func testTransportRejectsNonIntegralAndOutOfDomainScores() {
        assertInvalid(["candidates": [row("moon", 84.5, "2026-03-01T21:00:00Z")], "limit": 5])
        assertInvalid(["candidates": [row("moon", -1, "2026-03-01T21:00:00Z")], "limit": 5])
        assertInvalid(["candidates": [row("moon", 101, "2026-03-01T21:00:00Z")], "limit": 5])
        assertInvalid(["candidates": [row("moon", "84", "2026-03-01T21:00:00Z")], "limit": 5])
    }

    func testTransportRejectsEmptyKeyAndNonArrayCandidates() {
        assertInvalid(["candidates": [row("", 84, "2026-03-01T21:00:00Z")], "limit": 5])
        assertInvalid(["candidates": ["moon"], "limit": 5])
        assertInvalid(["candidates": ["key": "moon"], "limit": 5])
    }

    /// `limit` has no semantic bound: the row cap already bounds the work, so a
    /// limit far above it simply selects every candidate and a far negative one
    /// selects nothing. Only the shared integer-transport magnitude applies.
    func testLargeLimitsCarryNoSemanticBound() throws {
        let rows = [
            row("moon", 84, "2026-03-01T21:00:00Z"),
            row("m31", 61, "2026-03-01T22:00:00Z"),
        ]
        for limit in [1_441, 100_000, RecommendationCompositionContract.integerMagnitudeLimit] {
            XCTAssertEqual(
                try (evaluate(["candidates": rows, "limit": limit])["selected"] as? [[String: Any]])?
                    .map { $0["key"] as? String },
                ["moon", "m31"],
                "limit \(limit) must select every available candidate"
            )
        }
        for limit in [-1_441, -100_000, -RecommendationCompositionContract.integerMagnitudeLimit] {
            XCTAssertEqual(
                (try evaluate(["candidates": rows, "limit": limit])["selected"] as? [[String: Any]])?.count,
                0,
                "limit \(limit) must select nothing"
            )
        }
        XCTAssertEqual(
            (try evaluate(["candidates": rows, "limit": 0])["selected"] as? [[String: Any]])?.count, 0)
    }

    func testTransportRejectsUnsafeAndNonIntegralLimits() {
        assertInvalid(["candidates": [],
                       "limit": RecommendationCompositionContract.integerMagnitudeLimit + 1])
        assertInvalid(["candidates": [],
                       "limit": -RecommendationCompositionContract.integerMagnitudeLimit - 1])
        assertInvalid(["candidates": [], "limit": 2.5])
        assertInvalid(["candidates": [], "limit": Double.infinity])
        assertInvalid(["candidates": [], "limit": Double.nan])
        assertInvalid(["candidates": [], "limit": "5"])
    }

    func testTransportBoundsBestTimeToTheEmittedWindowRange() throws {
        XCTAssertEqual(try (evaluate([
            "candidates": [row("venus", 40, "1999-12-31T22:00:00Z"),
                           row("mars", 40, "2500-01-01T01:14:59Z")],
            "limit": 5,
        ])["selected"] as? [[String: Any]])?.count, 2)
        assertInvalid(["candidates": [row("moon", 84, "1999-12-31T21:59:59Z")], "limit": 5])
        assertInvalid(["candidates": [row("moon", 84, "2500-01-01T01:15:00Z")], "limit": 5])
        assertInvalid(["candidates": [row("moon", 84, "2026-03-01T21:00:00+00:00")], "limit": 5])
        assertInvalid(["candidates": [row("moon", 84, "2026-03-01 21:00:00")], "limit": 5])
    }

    func testTransportCapsRowsBeforeIterating() {
        let rows = (0...RecommendationCompositionContract.maxRowCount).map {
            row("t\($0)", 50, "2026-03-01T21:00:00Z")
        }
        assertInvalid(["candidates": rows, "limit": 5], code: "sample_cap")

        XCTAssertNoThrow(try evaluate([
            "candidates": Array(rows.prefix(RecommendationCompositionContract.maxRowCount)),
            "limit": 5,
        ]))
    }
}
