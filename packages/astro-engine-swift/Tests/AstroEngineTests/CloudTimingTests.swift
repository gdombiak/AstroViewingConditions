import Foundation
import XCTest
@testable import AstroEngine

final class CloudTimingTests: XCTestCase {
    private static let base = Date(timeIntervalSince1970: 1_772_496_000)  // 2026-03-03T00:00:00Z

    private static func row(
        _ offsetSeconds: TimeInterval,
        _ score: Double,
        _ cloudCover: Int
    ) -> CloudTimingClassifier.HourlyRow {
        .init(time: base.addingTimeInterval(offsetSeconds), score: score, cloudCover: cloudCover)
    }

    private static func rating(
        _ offsetSeconds: TimeInterval,
        _ score: Double,
        _ cloudCover: Int
    ) -> NightQualityAssessment.HourlyRating {
        .init(
            time: base.addingTimeInterval(offsetSeconds),
            score: score,
            cloudCover: cloudCover,
            fogScore: 0,
            moonIllumination: 0,
            moonAltitude: 0,
            windSpeed: 0
        )
    }

    // MARK: - Calibration ownership

    func testThresholdsComeFromSharedNightQualityCalibration() {
        let night = EngineCalibration.current.nightQuality
        XCTAssertEqual(night.cloudFloor.cloudCoverMin, 80)
        XCTAssertEqual(night.ratingThresholds.fairMax, 1.0)
        XCTAssertEqual(NightQualityAssessment.Rating.Thresholds.fairMax, night.ratingThresholds.fairMax)
    }

    func testTransportRawValuesAreTheSemanticDomain() {
        XCTAssertEqual(
            CloudTimingClassifier.Classification.allCases.map(\.rawValue),
            ["none", "early_heavy", "late_heavy", "intermittent_heavy"]
        )
    }

    // MARK: - The four verdicts

    func testEmptyInputIsNone() {
        XCTAssertEqual(CloudTimingClassifier.classify([]), .none)
    }

    func testEarlyHeavyRequiresUsableHoursOnlyAfterTheRun() {
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 1.2, 90), Self.row(3600, 1.2, 90), Self.row(7200, 0.2, 10),
            ]),
            .earlyHeavy
        )
    }

    func testLateHeavyRequiresUsableHoursOnlyBeforeTheRun() {
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10), Self.row(3600, 1.2, 90), Self.row(7200, 1.2, 90),
            ]),
            .lateHeavy
        )
    }

    func testIntermittentHeavyRequiresUsableHoursOnBothSides() {
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10), Self.row(3600, 1.2, 90),
                Self.row(7200, 1.2, 90), Self.row(10800, 0.2, 10),
            ]),
            .intermittentHeavy
        )
    }

    func testWholeNightOfHeavyCloudHasNoUsableHourOnEitherSide() {
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 1.5, 100), Self.row(3600, 1.5, 100), Self.row(7200, 1.5, 100),
            ]),
            .none
        )
    }

    // MARK: - Run size

    func testOneRowNeverFormsARun() {
        XCTAssertEqual(CloudTimingClassifier.classify([Self.row(0, 1.5, 100)]), .none)
    }

    func testLoneHeavyHourBetweenUsableHoursIsNotSustained() {
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10), Self.row(3600, 1.5, 100), Self.row(7200, 0.2, 10),
            ]),
            .none
        )
    }

    func testTwoContiguousHeavyRowsAreTheMinimumRun() {
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10), Self.row(3600, 1.5, 100), Self.row(7200, 1.5, 100),
            ]),
            .lateHeavy
        )
    }

    // MARK: - Threshold inclusivity

    func testHeavyCloudThresholdIsInclusiveAndUsableScoreIsStrict() {
        // 80 is heavy, 79 is not.
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10), Self.row(3600, 1.2, 80), Self.row(7200, 1.2, 80),
            ]),
            .lateHeavy
        )
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10), Self.row(3600, 1.2, 79), Self.row(7200, 1.2, 79),
            ]),
            .none
        )
        // A score exactly at fairMax is not usable; just under it is.
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 1.0, 10), Self.row(3600, 1.2, 90), Self.row(7200, 1.2, 90),
            ]),
            .none
        )
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.999, 10), Self.row(3600, 1.2, 90), Self.row(7200, 1.2, 90),
            ]),
            .lateHeavy
        )
    }

    // MARK: - Timestamp spacing

    func testAdjacencyIsExactlyOneHour() {
        for step in [3599.0, 3601.0, 0.0, -3600.0, 7200.0] {
            XCTAssertEqual(
                CloudTimingClassifier.classify([
                    Self.row(0, 0.2, 10), Self.row(3600, 1.2, 90), Self.row(3600 + step, 1.2, 90),
                ]),
                .none,
                "step \(step) must break the run"
            )
        }
    }

    func testRowsAreNeverSorted() {
        // The same three heavy hours are contiguous once sorted, but supplied out
        // of order every step is a non-3600 delta, so no run exists.
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10),
                Self.row(7200, 1.2, 90), Self.row(3600, 1.2, 90), Self.row(10800, 1.2, 90),
            ]),
            .none
        )
    }

    // MARK: - Eligibility and ranking

    func testUsableHoursAreFoundAnywhereBeforeTheRunNotOnlyAdjacent() {
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.2, 10),
                Self.row(3600, 1.5, 50), Self.row(7200, 1.5, 50), Self.row(10800, 1.5, 50),
                Self.row(14400, 1.5, 95), Self.row(18000, 1.5, 95),
            ]),
            .lateHeavy
        )
    }

    func testIneligibleRunsAreFilteredBeforeRanking() {
        // The three-hour run has no usable score outside it and is dropped; the
        // shorter run survives because the dropped run's own rows are usable.
        // Ranking first would have produced `.none`.
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 0.5, 100), Self.row(3600, 0.5, 100), Self.row(7200, 0.5, 100),
                Self.row(10800, 1.5, 10),
                Self.row(14400, 1.5, 90), Self.row(18000, 1.5, 90),
            ]),
            .lateHeavy
        )
    }

    func testPreferenceIsLongestThenCloudiestThenEarliestStart() {
        // Longest wins even though the earlier run is cloudier.
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 1.2, 100), Self.row(3600, 1.2, 100),
                Self.row(7200, 0.2, 10),
                Self.row(10800, 1.2, 85), Self.row(14400, 1.2, 85), Self.row(18000, 1.2, 85),
            ]),
            .lateHeavy
        )
        // Equal length: greater average cloud wins, flipping the verdict.
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 1.2, 100), Self.row(3600, 1.2, 100),
                Self.row(7200, 0.2, 10),
                Self.row(10800, 1.2, 85), Self.row(14400, 1.2, 85),
                Self.row(21600, 0.2, 10),
            ]),
            .earlyHeavy
        )
        // Equal length and equal average cloud: earliest start index wins.
        XCTAssertEqual(
            CloudTimingClassifier.classify([
                Self.row(0, 1.2, 90), Self.row(3600, 1.2, 90),
                Self.row(7200, 0.2, 10),
                Self.row(10800, 1.2, 90), Self.row(14400, 1.2, 90),
                Self.row(21600, 0.2, 10),
            ]),
            .earlyHeavy
        )
    }

    // MARK: - Production delegation

    func testProductionRulesEntryPointDelegatesAndKeepsItsPresentationAlias() {
        XCTAssertEqual(
            NightQualityAnalysisRules.cloudTiming(in: [
                Self.rating(0, 0.2, 10), Self.rating(3600, 1.2, 90),
                Self.rating(7200, 1.2, 90), Self.rating(10800, 0.2, 10),
            ]),
            .intermittentHeavy
        )
        XCTAssertEqual(
            NightQualityAnalysisRules.CloudTiming.intermittentHeavy.summaryText,
            "A period of heavy clouds may interrupt otherwise better conditions."
        )
        XCTAssertNil(NightQualityAnalysisRules.CloudTiming.none.summaryText)
    }

    // MARK: - Strict transport

    private func evaluate(_ input: [String: Any]) -> Result<[String: Any], CloudTimingInputError> {
        do {
            return .success(try CloudTimingContract.evaluate(input))
        } catch let error as CloudTimingInputError {
            return .failure(error)
        } catch {
            XCTFail("unexpected error \(error)")
            return .failure(CloudTimingInputError())
        }
    }

    private func assertRejected(_ input: [String: Any], code: String = "validation") {
        switch evaluate(input) {
        case .success(let value): XCTFail("expected rejection, got \(value)")
        case .failure(let error):
            XCTAssertEqual(error.code, code)
            if code == "validation" {
                XCTAssertEqual(
                    error.message,
                    "invalid night_conditions.classify_cloud_timing input"
                )
            }
        }
    }

    func testContractReturnsTheSemanticVerdictOnly() throws {
        let result = try CloudTimingContract.evaluate([
            "hourly_ratings": [
                ["time": "2026-03-03T00:00:00Z", "score": 0.2, "cloud_cover": 10],
                ["time": "2026-03-03T01:00:00Z", "score": 1.2, "cloud_cover": 90],
                ["time": "2026-03-03T02:00:00Z", "score": 1.2, "cloud_cover": 90],
            ],
        ])
        XCTAssertEqual(result as? [String: String], ["cloud_timing": "late_heavy"])
    }

    func testContractRejectsShapeAndValueDefects() {
        assertRejected([:])
        assertRejected(["hourly_ratings": [], "good_rating_threshold": 1.0])
        assertRejected(["hourly_ratings": [String: Any]()])
        assertRejected(["hourly_ratings": [["time": "2026-03-03T00:00:00Z", "score": 0.2]]])
        assertRejected(["hourly_ratings": [[
            "time": "2026-03-03T00:00:00Z", "score": 0.2, "cloud_cover": 10, "fog_score": 0,
        ]]])
        assertRejected(["hourly_ratings": [[
            "time": "2026-03-03T00:00:00Z", "score": 0.2, "cloud_cover": 10.5,
        ]]])
        assertRejected(["hourly_ratings": [[
            "time": "2026-03-03T00:00:00Z", "score": true, "cloud_cover": 10,
        ]]])
        assertRejected(["hourly_ratings": [[
            "time": "2026-03-03T00:00:00Z", "score": "0.2", "cloud_cover": 10,
        ]]])
        assertRejected(["hourly_ratings": [[
            "time": "2026-03-03T00:00:00+00:00", "score": 0.2, "cloud_cover": 10,
        ]]])
        assertRejected(["hourly_ratings": [[
            "time": "2026-02-30T00:00:00Z", "score": 0.2, "cloud_cover": 10,
        ]]])
        assertRejected(["hourly_ratings": [[
            "time": "0000-01-01T00:00:00Z", "score": 0.2, "cloud_cover": 10,
        ]]])
    }

    func testContractRowCapIsItsOwnErrorCode() {
        let rows = (0...CloudTimingContract.maxRowCount).map { _ in
            ["time": "2026-03-03T00:00:00Z", "score": 0.2, "cloud_cover": 10] as [String: Any]
        }
        switch evaluate(["hourly_ratings": rows]) {
        case .success(let value): XCTFail("expected rejection, got \(value)")
        case .failure(let error):
            XCTAssertEqual(error.code, "sample_cap")
            XCTAssertEqual(
                error.message,
                "night_conditions.classify_cloud_timing exceeds the 1.0 row cap (1440 rows)"
            )
        }
    }
}
