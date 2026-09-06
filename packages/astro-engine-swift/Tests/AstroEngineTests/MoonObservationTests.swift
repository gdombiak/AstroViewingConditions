import XCTest
@testable import AstroEngine

/// Structure and transport semantics for `astronomy.moon_observation`.
final class MoonObservationTests: XCTestCase {
    private let latitude = 37.7749
    private let longitude = -122.4194
    private let start = Date(timeIntervalSince1970: 1_711_339_200)  // 2024-03-25T04:00:00Z

    private func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        try MoonObservationContract.evaluate(input)
    }

    private func base(_ changes: [String: Any?] = [:]) -> [String: Any] {
        var input: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "night_start": "2024-03-25T04:00:00Z",
            "night_end": "2024-03-25T12:00:00Z",
        ]
        for (key, value) in changes {
            if let value { input[key] = value } else { input.removeValue(forKey: key) }
        }
        return input
    }

    // MARK: - Sampling structure

    func testSamplesUseRepeatedAdditionPlusAnExplicitIntervalEnd() throws {
        let sampler = SunCalcMoonObservationSampler()
        let observation = try sampler.observation(
            latitude: latitude,
            longitude: longitude,
            nightStart: start,
            nightEnd: start.addingTimeInterval(3600 + 600)
        )
        XCTAssertEqual(
            observation.positionSamples.map { $0.time.timeIntervalSince(start) },
            [0, 1800, 3600, 4200]
        )
    }

    func testIntervalShorterThanTheCadenceStillReportsBothEndpoints() throws {
        let observation = try SunCalcMoonObservationSampler().observation(
            latitude: latitude, longitude: longitude,
            nightStart: start, nightEnd: start.addingTimeInterval(600)
        )
        XCTAssertEqual(observation.positionSamples.map { $0.time.timeIntervalSince(start) }, [0, 600])
    }

    func testZeroLengthIntervalReportsOneSampleAndAnInvertedIntervalReportsNone() throws {
        let sampler = SunCalcMoonObservationSampler()
        let zero = try sampler.observation(latitude: latitude, longitude: longitude,
                                           nightStart: start, nightEnd: start)
        XCTAssertEqual(zero.positionSamples.count, 1)
        let inverted = try sampler.observation(latitude: latitude, longitude: longitude,
                                               nightStart: start,
                                               nightEnd: start.addingTimeInterval(-3600))
        XCTAssertTrue(inverted.positionSamples.isEmpty)
    }

    func testPhaseAndIlluminationComeFromTheIntervalMidpoint() throws {
        let end = start.addingTimeInterval(8 * 3600)
        let observation = try SunCalcMoonObservationSampler().observation(
            latitude: latitude, longitude: longitude, nightStart: start, nightEnd: end
        )
        let midpoint = start.addingTimeInterval(4 * 3600)
        let facts = try SunCalcMoonSampler().facts(
            latitude: latitude, longitude: longitude, at: midpoint
        )
        XCTAssertEqual(observation.illumination, facts.illumination.illuminationPercent)
        XCTAssertEqual(observation.phase, (facts.illumination.phaseDegrees + 180) / 360, accuracy: 1e-12)
    }

    func testInvertedIntervalEvaluatesPhaseAtTheStart() throws {
        let sampler = SunCalcMoonObservationSampler()
        let inverted = try sampler.observation(latitude: latitude, longitude: longitude,
                                               nightStart: start,
                                               nightEnd: start.addingTimeInterval(-7200))
        let atStart = try sampler.observation(latitude: latitude, longitude: longitude,
                                              nightStart: start, nightEnd: start)
        XCTAssertEqual(inverted.phase, atStart.phase)
        XCTAssertEqual(inverted.illumination, atStart.illumination)
    }

    func testHostFallbackVariantKeepsTheExistingSignature() {
        let fallback = MoonInfo(phase: 0.25, phaseName: "First Quarter", altitude: 10,
                                illumination: 50, emoji: "🌓")
        let observation = SunCalcMoonObservationSampler().observation(
            latitude: latitude, longitude: longitude,
            nightStart: start, nightEnd: start.addingTimeInterval(3600),
            fallback: fallback
        )
        XCTAssertEqual(observation.positionSamples.count, 3)
        XCTAssertFalse(observation.phaseName.isEmpty)
    }

    // MARK: - Transport

    func testResultShapeAndEchoedInterval() throws {
        let result = try evaluate(base())
        XCTAssertEqual(Set(result.keys), [
            "night_start", "night_end", "phase", "illumination", "rise", "set",
            "always_up", "always_down", "samples",
        ])
        XCTAssertEqual(result["night_start"] as? String, "2024-03-25T04:00:00Z")
        XCTAssertEqual(result["night_end"] as? String, "2024-03-25T12:00:00Z")
        let samples = try XCTUnwrap(result["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 17)
        XCTAssertEqual(Set(samples[0].keys), ["time", "altitude", "azimuth"])
        let azimuth = try XCTUnwrap(samples[0]["azimuth"] as? Double)
        XCTAssertTrue(azimuth >= 0 && azimuth < 360)
    }

    func testCustomCadenceIsHonored() throws {
        let result = try evaluate(base(["sample_interval_seconds": 3600]))
        XCTAssertEqual((result["samples"] as? [[String: Any]])?.count, 9)
    }

    func testInvalidInputsFailClosed() {
        let cases: [[String: Any]] = [
            base(["latitude": true]),
            base(["latitude": 91]),
            base(["longitude": -181]),
            base(["night_start": nil]),
            base(["night_start": "2024-03-25T04:00:00+00:00"]),
            base(["night_start": "1999-12-31T23:59:59Z"]),
            base(["night_end": "2050-01-01T00:00:00Z"]),
            base(["sample_interval_seconds": 0]),
            base(["sample_interval_seconds": -1]),
            base(["sample_interval_seconds": true]),
            base(["sample_interval_seconds": 93_601]),
            base(["sample_interval_seconds": 1e308]),
            base(["sample_interval_seconds": 1800.5]),
            base(["sample_interval_seconds": 0.5, "night_end": "2024-03-25T04:00:01Z"]),
            base(["minimum_altitude": 15]),
            base(["night_end": "2024-03-26T07:00:00Z"]),
        ]
        for input in cases {
            XCTAssertThrowsError(try evaluate(input)) { error in
                let failure = error as? MoonObservationInputError
                XCTAssertEqual(failure?.code, "validation")
                XCTAssertEqual(failure?.message, "invalid astronomy.moon_observation input")
            }
        }
    }

    func testSpanOfExactlyTwentySixHoursIsAccepted() throws {
        let result = try evaluate(base([
            "night_end": "2024-03-26T06:00:00Z", "sample_interval_seconds": 3600,
        ]))
        XCTAssertEqual((result["samples"] as? [[String: Any]])?.count, 27)
    }

    func testSampleCapIsCheckedBeforeIterating() {
        for interval in [1.0, 1e-12, 65.0] {
            XCTAssertThrowsError(try evaluate(base([
                "night_end": "2024-03-26T06:00:00Z", "sample_interval_seconds": interval,
            ]))) { error in
                let failure = error as? MoonObservationInputError
                XCTAssertEqual(failure?.code, "sample_cap")
                XCTAssertEqual(
                    failure?.message,
                    "astronomy.moon_observation exceeds the 1.0 sample cap (1440 samples)"
                )
            }
        }
    }

    func testProcessTimeZoneDoesNotChangeTheResult() throws {
        let original = getenv("TZ").map { String(cString: $0) }
        defer {
            if let original { setenv("TZ", original, 1) } else { unsetenv("TZ") }
            tzset()
        }
        var rendered: [String] = []
        for zone in ["UTC", "Pacific/Kiritimati", "America/Los_Angeles"] {
            setenv("TZ", zone, 1)
            tzset()
            let result = try evaluate(base())
            rendered.append(String(describing: result["phase"]) + String(describing: result["rise"]))
        }
        XCTAssertEqual(Set(rendered).count, 1)
    }

    func testCapIncludesExplicitEndAndAcceptsExactly1440Rows() throws {
        XCTAssertThrowsError(try evaluate(base([
            "sample_interval_seconds": 60, "night_end": "2024-03-26T03:59:30Z",
        ]))) { error in
            XCTAssertEqual((error as? MoonObservationInputError)?.code, "sample_cap")
        }
        let result = try evaluate(base([
            "sample_interval_seconds": 60, "night_end": "2024-03-26T03:59:00Z",
        ]))
        XCTAssertEqual((result["samples"] as? [[String: Any]])?.count, 1440)
        var moon = result
        moon.removeValue(forKey: "night_start")
        moon.removeValue(forKey: "night_end")
        _ = try MoonRecommendationContract.evaluate([
            "night_start": result["night_start"]!, "night_end": result["night_end"]!,
            "moon": moon, "cloud_cover_score": 0, "hourly_ratings": [],
        ])
    }
}
