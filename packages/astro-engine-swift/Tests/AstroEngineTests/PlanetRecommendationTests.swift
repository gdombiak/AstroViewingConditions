import XCTest
@testable import AstroEngine

final class PlanetRecommendationTests: XCTestCase {
    private let calibration = EngineCalibration.current.planetRecommendation

    // MARK: - Selection and windows

    func testNoVisibleSampleReturnsNil() {
        XCTAssertNil(evaluate(samples: [
            sample(hour: 20, altitude: -12),
            sample(hour: 22, altitude: 7.999_999_999),
        ]))
    }

    func testVisibleAltitudeThresholdIsInclusive() throws {
        let result = try XCTUnwrap(evaluate(samples: [sample(hour: 22, altitude: 8)]))

        XCTAssertEqual(result.window.maxAltitude, 8)
    }

    func testEmptySampleArrayReturnsNil() {
        XCTAssertNil(evaluate(samples: []))
    }

    func testWeightedTieKeepsTheEarliestSample() throws {
        let result = try XCTUnwrap(evaluate(samples: [
            sample(hour: 22, altitude: 40, azimuth: 90),
            sample(hour: 23, altitude: 40, azimuth: 270),
        ]))

        XCTAssertEqual(result.window.bestTime, Self.date(hour: 22))
        XCTAssertEqual(result.window.azimuth, 90)
    }

    func testBestSampleWeightingPrefersDarknessOverASlightlyHigherTwilightSample() throws {
        let result = try XCTUnwrap(evaluate(samples: [
            sample(hour: 17, altitude: 30, azimuth: 260),
            sample(hour: 22, altitude: 29, azimuth: 180),
        ]))

        XCTAssertEqual(result.window.bestTime, Self.date(hour: 22))
    }

    func testInteriorCrossingsInterpolateAgainstTheThreshold() throws {
        let result = try XCTUnwrap(evaluate(samples: [
            sample(hourMinutes: 20 * 60, altitude: 6),
            sample(hourMinutes: 20 * 60 + 15, altitude: 10),
            sample(hourMinutes: 20 * 60 + 30, altitude: 12),
            sample(hourMinutes: 20 * 60 + 45, altitude: 4),
        ]))

        XCTAssertEqual(result.window.start, Self.date(hour: 20).addingTimeInterval(7.5 * 60))
        XCTAssertEqual(result.window.end, Self.date(hour: 20).addingTimeInterval(37.5 * 60))
    }

    func testFinalSampleUsesTheFixedWindowExtensionNotTheCadence() throws {
        let result = try XCTUnwrap(evaluate(samples: [
            sample(hour: 27, altitude: 20),
            sample(hour: 28, altitude: 31),
        ]))

        XCTAssertEqual(result.window.end, Self.date(hour: 28).addingTimeInterval(900))
        XCTAssertEqual(calibration.visibility.window_extension_seconds, 900)
    }

    func testFlatSegmentInsideTheInterpolationEpsilonKeepsTheEarlierInstant() throws {
        let result = try XCTUnwrap(evaluate(samples: [
            sample(hour: 20, altitude: 7.999_95),
            sample(hour: 21, altitude: 8.000_04),
            sample(hour: 22, altitude: 30),
        ]))

        XCTAssertEqual(result.window.start, Self.date(hour: 20))
    }

    // MARK: - Scoring

    func testAltitudeQualitySaturatesAtTheNormalizationDegree() throws {
        let atNormalization = try XCTUnwrap(evaluate(samples: [sample(hour: 22, altitude: 70)]))
        let above = try XCTUnwrap(evaluate(samples: [sample(hour: 22, altitude: 80)]))

        XCTAssertEqual(atNormalization.score, above.score)
        XCTAssertEqual(atNormalization.breakdown.altitudeQuality, 1)
    }

    func testLowAltitudePenaltyAppliesStrictlyBelowFifteenDegrees() throws {
        let below = try XCTUnwrap(evaluate(samples: [sample(hour: 22, altitude: 14.999_999_999)]))
        let at = try XCTUnwrap(evaluate(samples: [sample(hour: 22, altitude: 15)]))

        XCTAssertEqual(below.breakdown.lowAltitudePenalty, 18)
        XCTAssertEqual(at.breakdown.lowAltitudePenalty, 0)
    }

    func testScoreIsClampedAndRoundedHalfAwayFromZero() {
        XCTAssertEqual(
            PlanetRecommendation.score(altitude: 200, weatherQuality: 1, visibilityQuality: 1,
                                       convenience: 1, calibration: calibration),
            100
        )
        XCTAssertEqual(
            PlanetRecommendation.score(altitude: 0, weatherQuality: 0, visibilityQuality: 0,
                                       convenience: 0, calibration: calibration),
            0
        )
        // 45 * 0.5 + 0 + 0 + 0 = 22.5 rounds away from zero to 23.
        XCTAssertEqual(
            PlanetRecommendation.score(altitude: 35, weatherQuality: 0, visibilityQuality: 0,
                                       convenience: 0, calibration: calibration),
            23
        )
    }

    // MARK: - Weather and darkness

    func testNonOverlappingRatingsFallBackToCloudCover() throws {
        let result = try XCTUnwrap(evaluate(
            samples: [sample(hour: 22, altitude: 30)],
            cloudCoverScore: 40,
            ratings: [(Self.date(hour: 5), 2.0)]
        ))

        XCTAssertEqual(result.breakdown.weatherQuality, 0.6, accuracy: 1e-12)
    }

    func testHourlyRatingOverlapUsesAnOpenIntervalOnBothSides() {
        let window = PlanetRecommendation.Window(
            start: Self.date(hour: 22), end: Self.date(hour: 23),
            bestTime: Self.date(hour: 22), maxAltitude: 30, direction: "S", azimuth: 180
        )
        // A rating that ends exactly at the window start does not overlap.
        XCTAssertEqual(
            PlanetRecommendation.weatherQuality(
                in: window, cloudCoverScore: 100,
                hourlyRatings: [.init(time: Self.date(hour: 21), score: 0)],
                calibration: calibration
            ),
            0
        )
        // A rating starting exactly at the window end does not overlap either.
        XCTAssertEqual(
            PlanetRecommendation.weatherQuality(
                in: window, cloudCoverScore: 100,
                hourlyRatings: [.init(time: Self.date(hour: 23), score: 0)],
                calibration: calibration
            ),
            0
        )
    }

    func testDarknessOverlapIsAFractionOfTheWindowNotTheNight() {
        XCTAssertEqual(
            PlanetRecommendation.overlapFraction(
                windowStart: Self.date(hour: 18), windowEnd: Self.date(hour: 22),
                darknessStart: Self.date(hour: 20), darknessEnd: Self.date(hour: 29)
            ),
            0.5
        )
        XCTAssertEqual(
            PlanetRecommendation.overlapFraction(
                windowStart: Self.date(hour: 22), windowEnd: Self.date(hour: 22),
                darknessStart: Self.date(hour: 20), darknessEnd: Self.date(hour: 29)
            ),
            0
        )
    }

    // MARK: - Convenience

    func testConvenienceBandsAndTheirPrecedence() {
        func convenience(hour: Int) -> Double {
            PlanetRecommendation.convenienceScore(
                for: Self.date(hour: hour), nightStart: Self.date(hour: 20),
                nightEnd: Self.date(hour: 29), calibration: calibration
            )
        }

        XCTAssertEqual(convenience(hour: 18), 1)
        XCTAssertEqual(convenience(hour: 24), 1)
        XCTAssertEqual(convenience(hour: 25), 0.65)
        XCTAssertEqual(convenience(hour: 26), 0.35)
        XCTAssertEqual(convenience(hour: 17), 0.65)
        // A short night puts the evening band on top of the late-night band;
        // evening is tested first and wins.
        XCTAssertEqual(
            PlanetRecommendation.convenienceScore(
                for: Self.date(hour: 21), nightStart: Self.date(hour: 20),
                nightEnd: Self.date(hour: 22), calibration: calibration
            ),
            1
        )
    }

    // MARK: - Venus

    func testOnlyVenusEarnsTwilightVisibilityCredit() throws {
        let samples = [
            sample(hour: 18, altitude: 22, azimuth: 260, elongation: 46),
            sample(hour: 19, altitude: 12, azimuth: 270, elongation: 46),
            sample(hour: 20, altitude: 7.9, azimuth: 280, elongation: 46),
        ]
        let venus = try XCTUnwrap(evaluate(targetID: "venus", samples: samples))
        let jupiter = try XCTUnwrap(evaluate(targetID: "jupiter", samples: samples))

        XCTAssertGreaterThan(venus.breakdown.visibilityQuality, jupiter.breakdown.visibilityQuality)
        XCTAssertEqual(jupiter.breakdown.visibilityQuality, jupiter.breakdown.darknessOverlap)
        XCTAssertEqual(venus.breakdown.darknessOverlap, jupiter.breakdown.darknessOverlap)
    }

    func testVenusTargetIdentityIsCaseInsensitive() throws {
        let samples = [sample(hour: 18, altitude: 22, azimuth: 260, elongation: 46)]
        let lower = try XCTUnwrap(evaluate(targetID: "venus", samples: samples))
        let upper = try XCTUnwrap(evaluate(targetID: "VENUS", samples: samples))

        XCTAssertEqual(lower.score, upper.score)
    }

    func testVenusTwilightIsIneligibleOutsideTheTwoHourWindow() {
        let window = PlanetRecommendation.Window(
            start: Self.date(hour: 15), end: Self.date(hour: 17),
            bestTime: Self.date(hour: 16), maxAltitude: 30, direction: "W", azimuth: 265
        )

        XCTAssertEqual(
            PlanetRecommendation.venusTwilightSuitability(
                bestSample: sample(hour: 16, altitude: 30, azimuth: 265, elongation: 46),
                window: window, nightStart: Self.date(hour: 20), nightEnd: Self.date(hour: 29),
                calibration: calibration
            ),
            0
        )
    }

    func testVenusTwilightComponentsSaturateAtTheirProductionBounds() {
        let window = PlanetRecommendation.Window(
            start: Self.date(hour: 18), end: Self.date(hour: 19),
            bestTime: Self.date(hour: 18), maxAltitude: 20, direction: "W", azimuth: 265
        )
        // altitude 8 + 12 saturates, duration 3600 > 2700 saturates, elongation 45 saturates.
        XCTAssertEqual(
            PlanetRecommendation.venusTwilightSuitability(
                bestSample: sample(hour: 18, altitude: 20, azimuth: 265, elongation: 45),
                window: window, nightStart: Self.date(hour: 20), nightEnd: Self.date(hour: 29),
                calibration: calibration
            ),
            1,
            accuracy: 1e-12
        )
        // A missing elongation is read as zero, which floors that term.
        XCTAssertEqual(
            PlanetRecommendation.venusTwilightSuitability(
                bestSample: sample(hour: 18, altitude: 20, azimuth: 265, elongation: nil),
                window: window, nightStart: Self.date(hour: 20), nightEnd: Self.date(hour: 29),
                calibration: calibration
            ),
            0.75,
            accuracy: 1e-12
        )
    }

    // MARK: - Reasons

    func testReasonOrderAndAlwaysPresentMoonlightCode() throws {
        let result = try XCTUnwrap(evaluate(
            samples: [sample(hour: 22, altitude: 50)],
            cloudCoverScore: 0
        ))

        XCTAssertEqual(result.reasons, [
            .highAltitude, .astronomicalDarkness, .convenientPlanetWindow,
            .goodNightQuality, .planetMoonlightResistant,
        ])
    }

    /// Every optional reason branch can be off at once; the moonlight code is
    /// still appended, so the list is never empty and needs no fallback.
    func testReasonListCanContainOnlyTheMoonlightCode() throws {
        let result = try XCTUnwrap(evaluate(
            samples: [sample(hour: 17, altitude: 30)],
            cloudCoverScore: 45
        ))

        XCTAssertEqual(result.reasons, [.planetMoonlightResistant])
    }

    func testAstronomicalDarknessReasonUsesTheOverlapNotTheVenusVisibilityQuality() throws {
        let result = try XCTUnwrap(evaluate(
            targetID: "venus",
            samples: [
                sample(hour: 18, altitude: 22, azimuth: 260, elongation: 46),
                sample(hour: 19, altitude: 12, azimuth: 270, elongation: 46),
                sample(hour: 20, altitude: 7.9, azimuth: 280, elongation: 46),
            ]
        ))

        XCTAssertGreaterThanOrEqual(result.breakdown.visibilityQuality, 0.45)
        XCTAssertLessThan(result.breakdown.darknessOverlap, 0.45)
        XCTAssertFalse(result.reasons.contains(.astronomicalDarkness))
    }

    func testCompassIsSixteenPointAndRoundsHalfAwayFromZero() {
        XCTAssertEqual(PlanetRecommendation.compassDirection(forAzimuth: 0), "N")
        XCTAssertEqual(PlanetRecommendation.compassDirection(forAzimuth: 11.25), "NNE")
        XCTAssertEqual(PlanetRecommendation.compassDirection(forAzimuth: 11.249_999), "N")
        XCTAssertEqual(PlanetRecommendation.compassDirection(forAzimuth: 348.75), "N")
        XCTAssertEqual(PlanetRecommendation.compassDirection(forAzimuth: 360), "N")
        XCTAssertEqual(PlanetRecommendation.compassDirection(forAzimuth: -1), "N")
        XCTAssertEqual(PlanetRecommendation.compassDirection(forAzimuth: 181), "S")
    }

    // MARK: - Contract

    func testContractEmitsTheObjectiveResult() throws {
        let result = try PlanetRecommendationContract.evaluate(Self.input())
        let recommendation = try XCTUnwrap(result["recommendation"] as? [String: Any])
        let window = try XCTUnwrap(recommendation["visibility_window"] as? [String: Any])

        XCTAssertEqual(window["direction"] as? String, "S")
        XCTAssertEqual(window["max_altitude"] as? Double, 40)
        XCTAssertEqual(recommendation["reasons"] as? [String],
                       ["astronomicalDarkness", "convenientPlanetWindow", "goodNightQuality",
                        "planetMoonlightResistant"])
    }

    func testContractReturnsNullWhenNothingIsVisible() throws {
        var input = Self.input()
        input["samples"] = [Self.row(time: "2026-03-01T22:00:00Z", altitude: 1)]

        XCTAssertTrue(try PlanetRecommendationContract.evaluate(input)["recommendation"] is NSNull)
    }

    func testContractFailsClosedOnPathologicalInputs() {
        let mutations: [(String, [String: Any])] = [
            ("unknown field", ["extra": 1]),
            ("unsupported target", ["target_id": "earth"]),
            ("boolean cloud cover", ["cloud_cover_score": true]),
            ("string cloud cover", ["cloud_cover_score": "5"]),
            ("instant out of range", ["night_start": "1999-12-31T23:59:59Z"]),
            ("samples not an array", ["samples": ["time": "2026-03-01T22:00:00Z"]]),
            ("ratings not an array", ["hourly_ratings": 3]),
            ("unsorted samples", ["samples": [
                Self.row(time: "2026-03-01T23:00:00Z", altitude: 40),
                Self.row(time: "2026-03-01T22:00:00Z", altitude: 40),
            ]]),
            ("duplicate sample time", ["samples": [
                Self.row(time: "2026-03-01T22:00:00Z", altitude: 40),
                Self.row(time: "2026-03-01T22:00:00Z", altitude: 41),
            ]]),
            ("unknown sample field", ["samples": [[
                "time": "2026-03-01T22:00:00Z", "altitude": 40.0, "azimuth": 180.0,
                "solar_elongation": 45.0, "extra": 1,
            ]]]),
            ("null azimuth", ["samples": [[
                "time": "2026-03-01T22:00:00Z", "altitude": 40.0,
                "azimuth": NSNull(), "solar_elongation": 45.0,
            ]]]),
            ("unknown rating field", ["hourly_ratings": [[
                "time": "2026-03-01T22:00:00Z", "score": 1.0, "extra": 1,
            ]]]),
        ]

        for (label, mutation) in mutations {
            var input = Self.input()
            for (key, value) in mutation { input[key] = value }
            XCTAssertThrowsError(try PlanetRecommendationContract.evaluate(input), label) { error in
                XCTAssertEqual((error as? PlanetRecommendationInputError)?.code, "validation", label)
            }
        }
    }

    func testMissingRequiredFieldsFailClosed() {
        for key in ["target_id", "night_start", "night_end", "samples", "cloud_cover_score",
                    "hourly_ratings"] {
            var input = Self.input()
            input.removeValue(forKey: key)
            XCTAssertThrowsError(try PlanetRecommendationContract.evaluate(input), key)
        }
    }

    func testRowCapsAreEnforcedOnBothInjectedArrays() {
        let rows = (0...1440).map { index in
            Self.row(time: Self.timestamp(offsetMinutes: index), altitude: 40)
        }
        var samplesInput = Self.input()
        samplesInput["samples"] = rows
        var ratingsInput = Self.input()
        ratingsInput["hourly_ratings"] = (0...1440).map { index in
            ["time": Self.timestamp(offsetMinutes: index), "score": 1.0] as [String: Any]
        }

        for input in [samplesInput, ratingsInput] {
            XCTAssertThrowsError(try PlanetRecommendationContract.evaluate(input)) { error in
                let failure = error as? PlanetRecommendationInputError
                XCTAssertEqual(failure?.code, "sample_cap")
                XCTAssertEqual(
                    failure?.message,
                    "targets.planet_recommendation exceeds the 1.0 row cap (1440 rows)"
                )
            }
        }
    }

    // MARK: - Bounded spill

    func testSpillBoundsAreDerivedFromProductionSamplingAndScoring() {
        XCTAssertEqual(PlanetRecommendationContract.sampleSpillBeforeSeconds,
                       LowPrecisionPlanetObservationSampler.leadSeconds)
        XCTAssertEqual(PlanetRecommendationContract.sampleSpillAfterSeconds,
                       LowPrecisionPlanetObservationSampler.trailSeconds)
        XCTAssertEqual(PlanetRecommendationContract.windowSpillAfterSeconds,
                       LowPrecisionPlanetObservationSampler.trailSeconds
                           + calibration.visibility.window_extension_seconds)
        XCTAssertEqual(PlanetRecommendationContract.ratingSpillBeforeSeconds,
                       LowPrecisionPlanetObservationSampler.leadSeconds
                           + calibration.weather.hourly_rating_seconds)
        XCTAssertEqual(Self.text(PlanetRecommendationContract.earliestSampleInstant),
                       "1999-12-31T22:00:00Z")
        XCTAssertEqual(Self.text(PlanetRecommendationContract.latestSampleInstant),
                       "2500-01-01T00:59:59Z")
        XCTAssertEqual(Self.text(PlanetRecommendationContract.earliestRatingInstant),
                       "1999-12-31T21:00:00Z")
        XCTAssertEqual(Self.text(PlanetRecommendationContract.latestRatingInstant),
                       "2500-01-01T01:14:59Z")
        XCTAssertEqual(Self.text(PlanetRecommendationContract.latestWindowInstant),
                       "2500-01-01T01:14:59Z")
    }

    /// The central invariant: the earliest supported night's observation samples
    /// start two hours before the night-instant floor and must still be accepted.
    func testSamplesFromTheObservationLeadAreAcceptedAndCanOpenTheWindow() throws {
        var input = Self.input()
        input["night_start"] = "2000-01-01T00:00:00Z"
        input["night_end"] = "2000-01-01T08:00:00Z"
        input["samples"] = [Self.row(time: "1999-12-31T22:00:00Z", altitude: 30)]
        let recommendation = try XCTUnwrap(
            try PlanetRecommendationContract.evaluate(input)["recommendation"] as? [String: Any]
        )
        let window = try XCTUnwrap(recommendation["visibility_window"] as? [String: Any])

        XCTAssertEqual(window["start"] as? String, "1999-12-31T22:00:00Z")
        XCTAssertEqual(window["best_time"] as? String, "1999-12-31T22:00:00Z")
        XCTAssertEqual(window["end"] as? String, "1999-12-31T22:15:00Z")
    }

    /// The trail plus the fixed final-sample extension is the latest emittable
    /// instant, and the transport must be able to format it.
    func testTheLatestWindowEndIsEmittable() throws {
        var input = Self.input()
        input["night_start"] = "2499-12-31T15:00:00Z"
        input["night_end"] = "2499-12-31T23:59:59Z"
        input["samples"] = [Self.row(time: "2500-01-01T00:59:59Z", altitude: 30)]
        let recommendation = try XCTUnwrap(
            try PlanetRecommendationContract.evaluate(input)["recommendation"] as? [String: Any]
        )
        let window = try XCTUnwrap(recommendation["visibility_window"] as? [String: Any])

        XCTAssertEqual(window["end"] as? String, "2500-01-01T01:14:59Z")
    }

    func testRatingsMayReachOneHourBeforeTheEarliestWindowStart() throws {
        var input = Self.input()
        input["night_start"] = "2000-01-01T00:00:00Z"
        input["night_end"] = "2000-01-01T08:00:00Z"
        input["samples"] = [Self.row(time: "1999-12-31T22:00:00Z", altitude: 30)]
        input["cloud_cover_score"] = 100.0

        // One second inside the rating floor: the hour ends after the window start.
        input["hourly_ratings"] = [["time": "1999-12-31T21:00:01Z", "score": 0.0] as [String: Any]]
        var recommendation = try XCTUnwrap(
            try PlanetRecommendationContract.evaluate(input)["recommendation"] as? [String: Any]
        )
        XCTAssertTrue((recommendation["reasons"] as? [String])?.contains("goodNightQuality") == true)

        // Exactly on the floor: accepted, but the strict overlap test excludes it
        // and the cloud-cover fallback applies.
        input["hourly_ratings"] = [["time": "1999-12-31T21:00:00Z", "score": 0.0] as [String: Any]]
        recommendation = try XCTUnwrap(
            try PlanetRecommendationContract.evaluate(input)["recommendation"] as? [String: Any]
        )
        XCTAssertTrue((recommendation["reasons"] as? [String])?.contains("poorWeather") == true)
    }

    func testInstantsOutsideTheJustifiedSpillFailClosed() {
        let mutations: [(String, [String: Any])] = [
            ("sample below floor", [
                "night_start": "2000-01-01T00:00:00Z", "night_end": "2000-01-01T08:00:00Z",
                "samples": [Self.row(time: "1999-12-31T21:59:59Z", altitude: 30)],
            ]),
            ("sample above ceiling", [
                "night_start": "2499-12-31T15:00:00Z", "night_end": "2499-12-31T23:59:59Z",
                "samples": [Self.row(time: "2500-01-01T01:00:00Z", altitude: 30)],
            ]),
            ("rating below floor", [
                "night_start": "2000-01-01T00:00:00Z", "night_end": "2000-01-01T08:00:00Z",
                "samples": [Self.row(time: "1999-12-31T22:00:00Z", altitude: 30)],
                "hourly_ratings": [["time": "1999-12-31T20:59:59Z", "score": 0.0] as [String: Any]],
            ]),
            ("rating above ceiling", [
                "night_start": "2499-12-31T15:00:00Z", "night_end": "2499-12-31T23:59:59Z",
                "samples": [Self.row(time: "2500-01-01T00:00:00Z", altitude: 30)],
                "hourly_ratings": [["time": "2500-01-01T01:15:00Z", "score": 0.0] as [String: Any]],
            ]),
        ]

        for (label, mutation) in mutations {
            var input = Self.input()
            for (key, value) in mutation { input[key] = value }
            XCTAssertThrowsError(try PlanetRecommendationContract.evaluate(input), label) { error in
                XCTAssertEqual((error as? PlanetRecommendationInputError)?.code, "validation", label)
            }
        }
    }

    /// The spill applies to provider-derived instants, not to the night interval.
    func testNightInstantsKeepTheUnspilledRange() {
        for (field, value) in [("night_start", "1999-12-31T23:00:00Z"),
                               ("night_end", "2500-01-01T00:00:00Z")] {
            var input = Self.input()
            input[field] = value
            XCTAssertThrowsError(try PlanetRecommendationContract.evaluate(input), field)
        }
    }

    func testSolarElongationMayBeNull() throws {
        var input = Self.input()
        input["samples"] = [[
            "time": "2026-03-01T22:00:00Z", "altitude": 40.0, "azimuth": 180.0,
            "solar_elongation": NSNull(),
        ]]

        XCTAssertNotNil(try PlanetRecommendationContract.evaluate(input)["recommendation"])
    }

    // MARK: - Helpers

    private func evaluate(
        targetID: String = "jupiter",
        samples: [PlanetRecommendation.Sample],
        cloudCoverScore: Double = 0,
        ratings: [(Date, Double)] = []
    ) -> PlanetRecommendation.Result? {
        PlanetRecommendation.evaluate(
            targetID: targetID,
            samples: samples,
            nightStart: Self.date(hour: 20),
            nightEnd: Self.date(hour: 29),
            cloudCoverScore: cloudCoverScore,
            hourlyRatings: ratings.map { .init(time: $0.0, score: $0.1) },
            calibration: calibration
        )
    }

    private func sample(
        hour: Int,
        altitude: Double,
        azimuth: Double = 180,
        elongation: Double? = 45
    ) -> PlanetRecommendation.Sample {
        sample(hourMinutes: hour * 60, altitude: altitude, azimuth: azimuth, elongation: elongation)
    }

    private func sample(
        hourMinutes: Int,
        altitude: Double,
        azimuth: Double = 180,
        elongation: Double? = 45
    ) -> PlanetRecommendation.Sample {
        PlanetRecommendation.Sample(
            time: Self.date(hour: 0).addingTimeInterval(Double(hourMinutes) * 60),
            altitude: altitude,
            azimuth: azimuth,
            solarElongation: elongation
        )
    }

    private static func input() -> [String: Any] {
        [
            "target_id": "jupiter",
            "night_start": "2026-03-01T20:00:00Z",
            "night_end": "2026-03-02T05:00:00Z",
            "samples": [row(time: "2026-03-01T22:00:00Z", altitude: 40)],
            "cloud_cover_score": 0.0,
            "hourly_ratings": [],
        ]
    }

    private static func row(time: String, altitude: Double) -> [String: Any] {
        ["time": time, "altitude": altitude, "azimuth": 180.0, "solar_elongation": 45.0]
    }

    private static func text(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func timestamp(offsetMinutes: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(
            from: date(hour: 0).addingTimeInterval(Double(offsetMinutes) * 60)
        )
    }

    private static func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1 + hour / 24
        components.hour = hour % 24
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
