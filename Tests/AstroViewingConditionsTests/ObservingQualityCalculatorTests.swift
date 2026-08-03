@testable import SharedCode
import XCTest

/// Scoring-only prototype tests for light-pollution-adjusted observing quality.
///
/// Real atlas samples (coordinates are documentation only; tests pass brightness directly):
/// - Home: 45.45°N, 122.75°W → 18.5896816253662 mag/arcsec²
/// - Stub Stewart State Park ≈ 45.736°N, 123.192°W → 21.3461055755615 mag/arcsec²
///
/// Home calibration was sanity-checked against a successful ~47-minute Seestar S30 Pro image of M57
/// from the backyard on a clear night. This calculator does **not** encode telescope, target, or image logic.
final class ObservingQualityCalculatorTests: XCTestCase {

    // MARK: - Fixtures

    /// Home (Beaverton area) modeled zenith sky brightness.
    private let homeBrightness = 18.5896816253662
    /// Stub Stewart State Park modeled zenith sky brightness.
    private let stubStewartBrightness = 21.3461055755615

    private var homeBasePenalty: Double {
        ObservingQualityCalculator.baseLightPollutionPenalty(
            modeledZenithSkyBrightness: homeBrightness
        )!
    }

    private var stubBasePenalty: Double {
        ObservingQualityCalculator.baseLightPollutionPenalty(
            modeledZenithSkyBrightness: stubStewartBrightness
        )!
    }

    // MARK: - Calibration anchors

    func testHomeAndStubStewartBasePenalties() {
        // Expected: home ≈ 6.82, stub ≈ 0.90 (piecewise-linear between anchors).
        XCTAssertEqual(homeBasePenalty, 6.820636749267599, accuracy: 1e-9)
        XCTAssertEqual(stubBasePenalty, 0.8975431654188935, accuracy: 1e-9)
    }

    func testExactAnchorPenalties() {
        let anchors: [(Double, Double)] = [
            (17.5, 8.0), (18.5, 7.0), (19.5, 5.0), (20.5, 3.0), (21.3, 1.0), (21.75, 0.0),
        ]
        for (brightness, expected) in anchors {
            let penalty = ObservingQualityCalculator.baseLightPollutionPenalty(
                modeledZenithSkyBrightness: brightness
            )
            XCTAssertEqual(penalty!, expected, accuracy: 1e-12, "brightness \(brightness)")
        }
    }

    func testPenaltyClampsOutsideRange() {
        XCTAssertEqual(
            ObservingQualityCalculator.baseLightPollutionPenalty(modeledZenithSkyBrightness: 16.0)!,
            8.0,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            ObservingQualityCalculator.baseLightPollutionPenalty(modeledZenithSkyBrightness: 22.5)!,
            0.0,
            accuracy: 1e-12
        )
    }

    func testBasePenaltyReturnsNilForNonFiniteBrightness() {
        for b: Double in [.nan, .infinity, -.infinity] {
            XCTAssertNil(
                ObservingQualityCalculator.baseLightPollutionPenalty(modeledZenithSkyBrightness: b),
                "expected nil for \(b)"
            )
        }
    }

    func testUsabilityWeightAnchorsAndExamples() {
        let cases: [(Int, Double)] = [
            (30, 0.0),
            (35, 0.0),
            (45, 0.25),
            (50, 0.375),
            (60, 0.625),
            (65, 0.75),
            (75, 0.9166666666666666),
            (80, 1.0),
            (90, 1.0),
        ]
        for (score, expected) in cases {
            let w = ObservingQualityCalculator.usabilityWeight(nightConditionsScore: score)
            XCTAssertEqual(w, expected, accuracy: 1e-12, "score \(score)")
        }
    }

    func testInterpolationContinuousNearPenaltyAnchors() {
        let anchors = [17.5, 18.5, 19.5, 20.5, 21.3, 21.75]
        let eps = 1e-6
        for a in anchors {
            let at = ObservingQualityCalculator.baseLightPollutionPenalty(modeledZenithSkyBrightness: a)!
            let before = ObservingQualityCalculator.baseLightPollutionPenalty(modeledZenithSkyBrightness: a - eps)!
            let after = ObservingQualityCalculator.baseLightPollutionPenalty(modeledZenithSkyBrightness: a + eps)!
            // Continuous from the interior; clamp region is one-sided at endpoints.
            if a > 17.5 {
                XCTAssertEqual(before, at, accuracy: 1e-4, "before \(a)")
            }
            if a < 21.75 {
                XCTAssertEqual(after, at, accuracy: 1e-4, "after \(a)")
            }
        }
    }

    // MARK: A. Individual location matrices

    func testHomeAcceptanceMatrix() {
        let matrix: [(night: Int, expected: Int)] = [
            (96, 89), (93, 86), (90, 83), (85, 78), (80, 73),
            (75, 69), (65, 60), (50, 47), (30, 30),
        ]
        for row in matrix {
            let result = ObservingQualityCalculator.assess(
                nightConditionsScore: row.night,
                modeledZenithSkyBrightness: homeBrightness
            )
            XCTAssertEqual(
                result.score,
                row.expected,
                "Home night \(row.night): got \(result.score), expected \(row.expected); "
                    + "base=\(homeBasePenalty) applied=\(result.lightPollution?.appliedPenalty ?? -1)"
            )
            XCTAssertEqual(result.nightConditionsScore, row.night)
            XCTAssertNotNil(result.lightPollution)
        }
    }

    func testStubStewartAcceptanceMatrix() {
        let matrix: [(night: Int, expected: Int)] = [
            (96, 95), (93, 92), (90, 89), (85, 84), (80, 79),
            (75, 74), (65, 64), (50, 50), (30, 30),
        ]
        for row in matrix {
            let result = ObservingQualityCalculator.assess(
                nightConditionsScore: row.night,
                modeledZenithSkyBrightness: stubStewartBrightness
            )
            XCTAssertEqual(
                result.score,
                row.expected,
                "Stub night \(row.night): got \(result.score), expected \(row.expected); "
                    + "base=\(stubBasePenalty) applied=\(result.lightPollution?.appliedPenalty ?? -1)"
            )
        }
    }

    // MARK: B. Home versus Stub Stewart comparisons

    func testHomeVersusStubStewartComparisons() {
        // (homeNight, stubNight, expectation)
        enum Expectation {
            case stubClearlyHigher
            case stubSlightlyHigher
            case approximatelyTied  // |diff| <= 1
            case homeHigher
        }

        let cases: [(home: Int, stub: Int, Expectation)] = [
            (93, 93, .stubClearlyHigher),
            (90, 85, .stubSlightlyHigher),
            (90, 83, .approximatelyTied),
            (90, 80, .homeHigher),
            (85, 80, .stubSlightlyHigher),
            (85, 78, .approximatelyTied),
            (85, 75, .homeHigher),
            (80, 75, .stubSlightlyHigher),
            (80, 72, .homeHigher),
            // Calculator: home 75→69, stub 70→69 (rounded) → tied, not stub higher.
            (75, 70, .approximatelyTied),
            (75, 65, .homeHigher),
        ]

        for item in cases {
            let home = ObservingQualityCalculator.assess(
                nightConditionsScore: item.home,
                modeledZenithSkyBrightness: homeBrightness
            ).score
            let stub = ObservingQualityCalculator.assess(
                nightConditionsScore: item.stub,
                modeledZenithSkyBrightness: stubStewartBrightness
            ).score
            let diff = stub - home

            switch item.2 {
            case .stubClearlyHigher:
                XCTAssertGreaterThan(diff, 2, "home \(item.home)->\(home) stub \(item.stub)->\(stub)")
            case .stubSlightlyHigher:
                XCTAssertGreaterThanOrEqual(diff, 1, "home \(item.home)->\(home) stub \(item.stub)->\(stub)")
                XCTAssertLessThanOrEqual(diff, 3, "home \(item.home)->\(home) stub \(item.stub)->\(stub)")
            case .approximatelyTied:
                XCTAssertLessThanOrEqual(abs(diff), 1, "home \(item.home)->\(home) stub \(item.stub)->\(stub)")
            case .homeHigher:
                XCTAssertGreaterThan(home, stub, "home \(item.home)->\(home) stub \(item.stub)->\(stub)")
            }
        }
    }

    // MARK: C. Invariants

    func testDarkerSkyNeverLowersScoreForFixedNightConditions() {
        let night = 80
        let brightnesses = stride(from: 17.0, through: 22.0, by: 0.1).map { $0 }
        var previous = ObservingQualityCalculator.assess(
            nightConditionsScore: night,
            modeledZenithSkyBrightness: brightnesses[0]
        ).score
        for b in brightnesses.dropFirst() {
            let next = ObservingQualityCalculator.assess(
                nightConditionsScore: night,
                modeledZenithSkyBrightness: b
            ).score
            XCTAssertGreaterThanOrEqual(next, previous, "brightness \(b): \(next) < \(previous)")
            previous = next
        }
    }

    func testHigherNightConditionsNeverLowersScoreForFixedBrightness() {
        for brightness in [homeBrightness, stubStewartBrightness, 20.0] {
            var previous = ObservingQualityCalculator.assess(
                nightConditionsScore: 0,
                modeledZenithSkyBrightness: brightness
            ).score
            for night in 1...100 {
                let next = ObservingQualityCalculator.assess(
                    nightConditionsScore: night,
                    modeledZenithSkyBrightness: brightness
                ).score
                XCTAssertGreaterThanOrEqual(next, previous, "night \(night) b \(brightness)")
                previous = next
            }
        }
    }

    func testScoreAlwaysInZeroToOneHundred() {
        for night in [-10, 0, 50, 100, 150] {
            for b: Double? in [nil, 16.0, homeBrightness, stubStewartBrightness, 22.0, .nan, .infinity] {
                let s = ObservingQualityCalculator.assess(
                    nightConditionsScore: night,
                    modeledZenithSkyBrightness: b
                ).score
                XCTAssertGreaterThanOrEqual(s, 0)
                XCTAssertLessThanOrEqual(s, 100)
            }
        }
    }

    func testMissingBrightnessReturnsNightConditionsExactly() {
        for night in [0, 30, 50, 75, 93, 100] {
            let result = ObservingQualityCalculator.assess(
                nightConditionsScore: night,
                modeledZenithSkyBrightness: nil
            )
            XCTAssertEqual(result.score, night)
            XCTAssertEqual(result.nightConditionsScore, night)
            XCTAssertNil(result.lightPollution)
            XCTAssertTrue(result.lightPollutionDataUnavailable)
        }
    }

    func testNonFiniteBrightnessTreatedAsUnavailable() {
        // Must not treat NaN/±inf as pristine (0 penalty); helper returns nil and assess drops light pollution.
        for b: Double in [.nan, .infinity, -.infinity] {
            XCTAssertNil(ObservingQualityCalculator.baseLightPollutionPenalty(modeledZenithSkyBrightness: b))
            let result = ObservingQualityCalculator.assess(
                nightConditionsScore: 90,
                modeledZenithSkyBrightness: b
            )
            XCTAssertEqual(result.score, 90)
            XCTAssertEqual(result.nightConditionsScore, 90)
            XCTAssertNil(result.lightPollution)
            XCTAssertTrue(result.lightPollutionDataUnavailable)
        }
    }

    func testPoorNightNoFurtherLightPollutionReduction() {
        for night in [0, 20, 35] {
            let home = ObservingQualityCalculator.assess(
                nightConditionsScore: night,
                modeledZenithSkyBrightness: homeBrightness
            )
            XCTAssertEqual(home.score, night)
            XCTAssertEqual(home.lightPollution?.appliedPenalty ?? -1, 0, accuracy: 1e-12)
        }
    }

    func testExcellentNightAppliesFullBasePenalty() {
        for night in [80, 90, 100] {
            let home = ObservingQualityCalculator.assess(
                nightConditionsScore: night,
                modeledZenithSkyBrightness: homeBrightness
            )
            XCTAssertEqual(home.lightPollution?.appliedPenalty ?? -1, homeBasePenalty, accuracy: 1e-12)
            XCTAssertEqual(
                home.score,
                ObservingQualityCalculator.clampScore(
                    Int((Double(night) - homeBasePenalty).rounded())
                )
            )
        }
    }

    func testDeterministicRepeatedCalls() {
        for _ in 0..<20 {
            let a = ObservingQualityCalculator.assess(
                nightConditionsScore: 85,
                modeledZenithSkyBrightness: homeBrightness
            )
            let b = ObservingQualityCalculator.assess(
                nightConditionsScore: 85,
                modeledZenithSkyBrightness: homeBrightness
            )
            XCTAssertEqual(a, b)
        }
    }

    func testDarkerSiteCannotRescuePoorNightConditions() {
        let home = ObservingQualityCalculator.assess(
            nightConditionsScore: 30,
            modeledZenithSkyBrightness: homeBrightness
        )
        let stub = ObservingQualityCalculator.assess(
            nightConditionsScore: 30,
            modeledZenithSkyBrightness: stubStewartBrightness
        )
        XCTAssertEqual(home.score, 30)
        XCTAssertEqual(stub.score, 30)
    }

    func testNightConditionsScoreClamped() {
        let high = ObservingQualityCalculator.assess(
            nightConditionsScore: 150,
            modeledZenithSkyBrightness: nil
        )
        XCTAssertEqual(high.score, 100)
        XCTAssertEqual(high.nightConditionsScore, 100)

        let low = ObservingQualityCalculator.assess(
            nightConditionsScore: -5,
            modeledZenithSkyBrightness: homeBrightness
        )
        XCTAssertEqual(low.nightConditionsScore, 0)
        XCTAssertEqual(low.score, 0)
    }

    // MARK: D. Named product acceptance

    /// Home with nightConditionsScore 93 should remain approximately 86 (encouraging).
    /// Sanity-checked against a successful backyard Seestar session on a clear night (context only).
    func testExcellentNightAtHomeRemainsEncouraging() {
        let result = ObservingQualityCalculator.assess(
            nightConditionsScore: 93,
            modeledZenithSkyBrightness: homeBrightness
        )
        XCTAssertEqual(result.score, 86)
    }

    /// Home with nightConditionsScore 75 should remain approximately 69 (still worth observing).
    func testUsableNightAtHomeRemainsWorthObserving() {
        let result = ObservingQualityCalculator.assess(
            nightConditionsScore: 75,
            modeledZenithSkyBrightness: homeBrightness
        )
        XCTAssertEqual(result.score, 69)
    }

    func testStubStewartWinsWhenConditionsAreEqual() {
        let home = ObservingQualityCalculator.assess(
            nightConditionsScore: 93,
            modeledZenithSkyBrightness: homeBrightness
        ).score
        let stub = ObservingQualityCalculator.assess(
            nightConditionsScore: 93,
            modeledZenithSkyBrightness: stubStewartBrightness
        ).score
        XCTAssertGreaterThan(stub, home)
        XCTAssertEqual(home, 86)
        XCTAssertEqual(stub, 92)
    }

    func testStubStewartCanOvercomeModestConditionsDisadvantage() {
        // Stub 85 vs Home 90 → Stub slightly higher (84 vs 83)
        let home = ObservingQualityCalculator.assess(
            nightConditionsScore: 90,
            modeledZenithSkyBrightness: homeBrightness
        ).score
        let stub = ObservingQualityCalculator.assess(
            nightConditionsScore: 85,
            modeledZenithSkyBrightness: stubStewartBrightness
        ).score
        XCTAssertGreaterThan(stub, home)
    }

    func testStubStewartCannotOvercomeLargeConditionsDisadvantage() {
        // Stub 80 vs Home 90 → Home higher (83 vs 79)
        let home = ObservingQualityCalculator.assess(
            nightConditionsScore: 90,
            modeledZenithSkyBrightness: homeBrightness
        ).score
        let stub = ObservingQualityCalculator.assess(
            nightConditionsScore: 80,
            modeledZenithSkyBrightness: stubStewartBrightness
        ).score
        XCTAssertGreaterThan(home, stub)
    }

    func testPoorWeatherDominatesAtBothLocations() {
        let home = ObservingQualityCalculator.assess(
            nightConditionsScore: 30,
            modeledZenithSkyBrightness: homeBrightness
        ).score
        let stub = ObservingQualityCalculator.assess(
            nightConditionsScore: 30,
            modeledZenithSkyBrightness: stubStewartBrightness
        ).score
        XCTAssertEqual(home, 30)
        XCTAssertEqual(stub, 30)
    }
}
