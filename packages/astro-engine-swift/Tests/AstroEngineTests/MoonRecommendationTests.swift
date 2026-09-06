import XCTest
@testable import AstroEngine

/// Edge semantics for the deterministic lunar recommendation and its transport.
final class MoonRecommendationEngineTests: XCTestCase {
    private let calibration = EngineCalibration.current.moonRecommendation
    private let start = Date(timeIntervalSince1970: 1_787_968_800)  // 2026-08-29T02:00:00Z

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func sample(_ minutes: Double, _ altitude: Double, _ azimuth: Double? = 90) -> MoonPositionSample {
        MoonPositionSample(time: at(minutes), altitude: altitude, azimuth: azimuth)
    }

    private func observation(
        phase: Double = 0.5,
        illumination: Int = 60,
        set: Date? = nil,
        alwaysDown: Bool = false,
        samples: [MoonPositionSample]? = nil
    ) -> MoonObservationData {
        MoonObservationData(
            phase: phase, phaseName: "", illumination: illumination,
            rise: nil, set: set, alwaysUp: false, alwaysDown: alwaysDown,
            positionSamples: samples ?? [sample(0, 10), sample(30, 20), sample(60, 5)]
        )
    }

    private func evaluate(
        _ observation: MoonObservationData,
        nightMinutes: ClosedRange<Double> = 0...120,
        bestWindow: (start: Date, end: Date)? = nil,
        cloudCoverScore: Double = 0,
        hourlyRatings: [MoonRecommendation.HourlyRating] = []
    ) -> MoonRecommendation.Result? {
        MoonRecommendation.evaluate(
            observation: observation,
            nightStart: at(nightMinutes.lowerBound),
            nightEnd: at(nightMinutes.upperBound),
            bestWindow: bestWindow,
            cloudCoverScore: cloudCoverScore,
            hourlyRatings: hourlyRatings,
            calibration: calibration
        )
    }

    func testHorizonThresholdIsStrict() {
        XCTAssertNil(evaluate(observation(samples: [sample(0, 0), sample(30, -0.0)])))
        let result = evaluate(observation(samples: [sample(0, 0), sample(30, .leastNonzeroMagnitude)]))
        XCTAssertEqual(result?.window.bestTime, at(30))
    }

    func testAltitudeTieKeepsTheEarliestSample() {
        let result = evaluate(observation(samples: [
            sample(0, 5, 10), sample(30, 20, 95), sample(60, 20, 250), sample(90, 5, 265),
        ]), nightMinutes: 0...90)
        XCTAssertEqual(result?.window.bestTime, at(30))
        XCTAssertEqual(result?.window.azimuth, 95)
        XCTAssertEqual(result?.window.direction, "E")
    }

    func testWindowExtensionIsAFixedLiteralClippedToTheUsefulEnd() {
        let single = evaluate(observation(samples: [sample(0, -1), sample(30, 6), sample(60, -1)]))
        XCTAssertEqual(single?.window.start, at(30))
        XCTAssertEqual(single?.window.end, at(60))

        let clipped = evaluate(observation(samples: [sample(0, 3), sample(30, 8)]), nightMinutes: 0...30)
        XCTAssertEqual(clipped?.window.end, at(30))
    }

    func testUsefulWindowComesFromTheInjectedBestWindowAndIsNotClippedToTheNight() {
        let disjoint = evaluate(observation(), bestWindow: (at(300), at(400)))
        XCTAssertNil(disjoint)

        let wider = evaluate(observation(), nightMinutes: 0...1, bestWindow: (at(0), at(120)))
        XCTAssertEqual(wider?.window.end, at(90))
    }

    func testVisibleFractionUsesTheUsefulWindowNotTheWholeNight() {
        let samples = [sample(0, -5), sample(30, -4), sample(60, 12), sample(90, 14)]
        let night = evaluate(observation(samples: samples), nightMinutes: 0...90)
        let clipped = evaluate(observation(samples: samples), nightMinutes: 0...90,
                               bestWindow: (at(60), at(90)))
        XCTAssertEqual(night?.reasons, [.moonVisibleUsefulWindow])
        XCTAssertGreaterThan(clipped!.score, night!.score)
    }

    func testNearNewMoonCapAndBoundaries() {
        let capped = evaluate(observation(phase: 0.5, illumination: 8))
        XCTAssertEqual(capped?.score, 35)
        XCTAssertEqual(capped?.reasons, [.newMoonDarkSky])
        XCTAssertGreaterThan(evaluate(observation(phase: 0.5, illumination: 9))!.score, 35)
        XCTAssertEqual(evaluate(observation(phase: 0.04, illumination: 60))?.reasons, [.newMoonDarkSky])
        XCTAssertEqual(evaluate(observation(phase: 0.96, illumination: 60))?.reasons, [.newMoonDarkSky])
    }

    func testPhaseQualityBranches() {
        // 0.17 and the adjacent double below it straddle the 0.08 quarter band.
        XCTAssertEqual(MoonRecommendation.phaseQuality(observation: observation(phase: 0.17, illumination: 60),
                                                       calibration: calibration), 1.0)
        XCTAssertEqual(MoonRecommendation.phaseQuality(observation: observation(phase: 0.16999999999999998, illumination: 60),
                                                       calibration: calibration), 0.68)
        XCTAssertEqual(MoonRecommendation.phaseQuality(observation: observation(phase: 0.15, illumination: 45),
                                                       calibration: calibration), 0.82)
        XCTAssertEqual(MoonRecommendation.phaseQuality(observation: observation(phase: 0.5, illumination: 90),
                                                       calibration: calibration), 0.70)
    }

    func testAlwaysDownForcesTheBelowUsefulWindowReason() {
        let result = evaluate(observation(alwaysDown: true))
        XCTAssertEqual(result?.reasons, [.moonBelowUsefulWindow, .moonVisibleUsefulWindow])
    }

    func testMoonSetsEarlyBoundaryIsStrict() {
        let inside = evaluate(observation(illumination: 40, set: at(60)), nightMinutes: 0...600)
        XCTAssertTrue(inside!.reasons.contains(.moonSetsEarlyDarkSkyLater))
        let boundary = evaluate(observation(illumination: 40, set: at(60)), nightMinutes: 0...180)
        XCTAssertFalse(boundary!.reasons.contains(.moonSetsEarlyDarkSkyLater))
        let dim = evaluate(observation(illumination: 39, set: at(60)), nightMinutes: 0...600)
        XCTAssertFalse(dim!.reasons.contains(.moonSetsEarlyDarkSkyLater))
    }

    func testWeatherFallsBackToCloudCoverWhenNoRatingOverlaps() {
        let window = MoonRecommendation.Window(start: at(60), end: at(120), bestTime: at(60),
                                               maxAltitude: 10, direction: "E", azimuth: 90)
        XCTAssertEqual(
            MoonRecommendation.weatherQuality(in: window, cloudCoverScore: 100,
                                              hourlyRatings: [.init(time: at(0), score: 0)],
                                              calibration: calibration),
            0
        )
        XCTAssertEqual(
            MoonRecommendation.weatherQuality(in: window, cloudCoverScore: 100,
                                              hourlyRatings: [.init(time: at(120), score: 0)],
                                              calibration: calibration),
            0
        )
        XCTAssertEqual(
            MoonRecommendation.weatherQuality(in: window, cloudCoverScore: 100,
                                              hourlyRatings: [.init(time: at(1), score: 0)],
                                              calibration: calibration),
            1
        )
    }

    func testCompassIsSixteenPointAndRoundsHalfAwayFromZero() {
        XCTAssertEqual(MoonRecommendation.compassDirection(forAzimuth: 348.75), "N")
        XCTAssertEqual(MoonRecommendation.compassDirection(forAzimuth: 348.74), "NNW")
        XCTAssertEqual(MoonRecommendation.compassDirection(forAzimuth: 22.5), "NNE")
        XCTAssertEqual(MoonRecommendation.compassDirection(forAzimuth: -90), "W")
        XCTAssertEqual(MoonRecommendation.compassDirection(forAzimuth: 720.5), "N")
    }

    func testNullAzimuthYieldsNoDirection() {
        let result = evaluate(observation(samples: [sample(0, 5, 80), sample(30, 25, nil)]),
                              nightMinutes: 0...30)
        XCTAssertNil(result?.window.azimuth)
        XCTAssertNil(result?.window.direction)
        XCTAssertEqual(result?.window.maxAltitude, 25)
    }
}

/// Strict transport checks for `targets.moon_recommendation`.
final class MoonRecommendationContractTests: XCTestCase {
    private func moon(_ changes: [String: Any?] = [:]) -> [String: Any] {
        var value: [String: Any] = [
            "phase": 0.5, "illumination": 60, "rise": NSNull(), "set": NSNull(),
            "always_up": false, "always_down": false,
            "samples": [["time": "2026-08-29T03:00:00Z", "altitude": 10.0, "azimuth": 90.0]],
        ]
        for (key, change) in changes {
            if let change { value[key] = change } else { value.removeValue(forKey: key) }
        }
        return value
    }

    private func base(_ changes: [String: Any?] = [:]) -> [String: Any] {
        var input: [String: Any] = [
            "night_start": "2026-08-29T02:00:00Z",
            "night_end": "2026-08-29T06:00:00Z",
            "moon": moon(),
            "cloud_cover_score": 0.0,
            "hourly_ratings": [],
        ]
        for (key, change) in changes {
            if let change { input[key] = change } else { input.removeValue(forKey: key) }
        }
        return input
    }

    func testOmittedAndNullBestWindowAgree() throws {
        let omitted = try MoonRecommendationContract.evaluate(base())
        let explicit = try MoonRecommendationContract.evaluate(base(["best_window": NSNull()]))
        XCTAssertEqual(
            NSDictionary(dictionary: omitted),
            NSDictionary(dictionary: explicit)
        )
    }

    func testInvalidInputsFailClosed() {
        let cases: [[String: Any]] = [
            base(["limit": 5]),
            base(["night_end": nil]),
            base(["cloud_cover_score": true]),
            base(["cloud_cover_score": "20"]),
            base(["best_window": ["start": "2026-08-29T02:00:00Z"]]),
            base(["best_window": []]),
            base(["hourly_ratings": [:]]),
            base(["hourly_ratings": [["time": "2026-08-29T02:00:00Z", "score": 1.0, "cloud": 1]]]),
            base(["moon": moon(["rise": nil])]),
            base(["moon": moon(["always_up": 1])]),
            base(["moon": moon(["illumination": 50.5])]),
            base(["moon": moon(["samples": [
                ["time": "2026-08-29T03:00:00Z", "altitude": 1.0, "azimuth": 1.0],
                ["time": "2026-08-29T03:00:00Z", "altitude": 2.0, "azimuth": 1.0],
            ]])]),
            base(["moon": moon(["samples": [
                ["time": "2026-08-29T04:00:00Z", "altitude": 1.0, "azimuth": 1.0],
                ["time": "2026-08-29T03:00:00Z", "altitude": 2.0, "azimuth": 1.0],
            ]])]),
            base(["night_start": "1999-12-31T23:59:59Z"]),
            base(["night_end": "2500-01-01T00:00:00Z"]),
            base(["night_start": "2026-08-29T02:00:00+00:00"]),
        ]
        for input in cases {
            XCTAssertThrowsError(try MoonRecommendationContract.evaluate(input)) { error in
                let failure = error as? MoonRecommendationInputError
                XCTAssertEqual(failure?.code, "validation")
                XCTAssertEqual(failure?.message, "invalid targets.moon_recommendation input")
            }
        }
    }

    func testRowCapsAreCheckedBeforeIterating() {
        let rows = (0..<1441).map { index -> [String: Any] in
            ["time": String(format: "2026-08-29T02:%02d:%02dZ", index / 60 % 60, index % 60),
             "score": 1.0]
        }
        let samples = (0..<1441).map { index -> [String: Any] in
            ["time": String(format: "2026-08-29T02:%02d:%02dZ", index / 60 % 60, index % 60),
             "altitude": 1.0, "azimuth": 1.0]
        }
        for input in [base(["hourly_ratings": rows]), base(["moon": moon(["samples": samples])])] {
            XCTAssertThrowsError(try MoonRecommendationContract.evaluate(input)) { error in
                let failure = error as? MoonRecommendationInputError
                XCTAssertEqual(failure?.code, "sample_cap")
                XCTAssertEqual(
                    failure?.message,
                    "targets.moon_recommendation exceeds the 1.0 row cap (1440 rows)"
                )
            }
        }
    }

    func testNullRecommendationShape() throws {
        let result = try MoonRecommendationContract.evaluate(
            base(["moon": moon(["samples": [["time": "2026-08-29T03:00:00Z",
                                             "altitude": -1.0, "azimuth": 90.0]]])])
        )
        XCTAssertEqual(Array(result.keys), ["recommendation"])
        XCTAssertTrue(result["recommendation"] is NSNull)
    }
}
