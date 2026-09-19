import XCTest
@testable import AstroEngine

final class PlanetObservationTests: XCTestCase {
    private let sampler = LowPrecisionPlanetObservationSampler(sampleInterval: 2 * 3600)

    func testProductionCadenceAndSpanConstants() {
        XCTAssertEqual(LowPrecisionPlanetObservationSampler.defaultSampleInterval, 900)
        XCTAssertEqual(LowPrecisionPlanetObservationSampler.leadSeconds, 7200)
        XCTAssertEqual(LowPrecisionPlanetObservationSampler.trailSeconds, 3600)
    }

    func testEarthIsInTheModelButNotAPublicCandidate() {
        XCTAssertEqual(PlanetBody.recommendationCandidates, [.venus, .mars, .jupiter, .saturn])
        XCTAssertEqual(PlanetBody(rawValue: "earth"), .earth)
        XCTAssertEqual(PlanetObservationContract.supportedTargetIDs, ["venus", "mars", "jupiter", "saturn"])
        XCTAssertNil(PlanetBody(rawValue: "mercury"))
    }

    /// The pinned production regression: Jupiter over Cupertino on 2026-06-30.
    func testSchlyterDayNumberProducesTheProductionRegressionSample() throws {
        let nightStart = Self.instant("2026-06-30T03:26:00Z")
        let samples = try XCTUnwrap(sampler.samples(
            body: .jupiter,
            latitude: 37.323,
            longitude: -122.032,
            nightStart: nightStart,
            nightEnd: Self.instant("2026-06-30T11:26:00Z")
        ))

        XCTAssertEqual(samples[0].time, Self.instant("2026-06-30T01:26:00Z"))
        XCTAssertEqual(samples[0].altitude, 39.532_328_397_078_97, accuracy: 1e-12)
        XCTAssertEqual(samples[0].azimuth, 266.782_421_342_379_17, accuracy: 1e-12)
    }

    /// The lead endpoint is always sampled; the trailing endpoint only when the
    /// cadence lands on it. There is no explicit interval-end sample.
    func testSamplingAlwaysCoversTheLeadEndpointAndCanLandOnTheTrailingOne() throws {
        // A 12-hour sampling span lands exactly on the trailing endpoint.
        let nightStart = Self.instant("2026-03-01T04:00:00Z")
        let nightEnd = Self.instant("2026-03-01T13:00:00Z")
        let samples = try XCTUnwrap(sampler.samples(
            body: .mars, latitude: 40, longitude: -74,
            nightStart: nightStart, nightEnd: nightEnd
        ))

        XCTAssertEqual(samples.first?.time, nightStart.addingTimeInterval(-7200))
        XCTAssertEqual(samples.last?.time, nightEnd.addingTimeInterval(3600))
        XCTAssertEqual(samples.count, 7)
    }

    /// A span that is not a whole multiple of the cadence stops before the end.
    func testNonDivisibleSpanDoesNotAddAnEndpointSample() throws {
        let nightStart = Self.instant("2026-03-01T04:00:00Z")
        let samples = try XCTUnwrap(sampler.samples(
            body: .mars, latitude: 40, longitude: -74,
            nightStart: nightStart, nightEnd: Self.instant("2026-03-01T12:00:00Z")
        ))

        XCTAssertEqual(samples.last?.time, Self.instant("2026-03-01T12:00:00Z"))
        XCTAssertEqual(samples.count, 6)
    }

    func testInvertedIntervalWithinLeadAndTrailStillSamples() throws {
        let nightStart = Self.instant("2026-03-01T04:00:00Z")
        let samples = try XCTUnwrap(sampler.samples(
            body: .venus, latitude: 40, longitude: -74,
            nightStart: nightStart, nightEnd: nightStart.addingTimeInterval(-3 * 3600 + 1)
        ))

        XCTAssertEqual(samples.count, 1)
    }

    func testIntervalInvertedPastLeadAndTrailYieldsNoObservation() {
        let nightStart = Self.instant("2026-03-01T04:00:00Z")

        XCTAssertNil(sampler.samples(
            body: .venus, latitude: 40, longitude: -74,
            nightStart: nightStart, nightEnd: nightStart.addingTimeInterval(-3 * 3600)
        ))
    }

    func testSamplesAreHorizontalCoordinatesWithSolarElongation() throws {
        for body in PlanetBody.recommendationCandidates {
            let samples = try XCTUnwrap(sampler.samples(
                body: body, latitude: 37.323, longitude: -122.032,
                nightStart: Self.instant("2026-06-30T03:26:00Z"),
                nightEnd: Self.instant("2026-06-30T11:26:00Z")
            ))
            XCTAssertTrue(samples.allSatisfy {
                (-90...90).contains($0.altitude)
                    && (0..<360).contains($0.azimuth)
                    && (0...180).contains($0.solarElongation)
            }, body.rawValue)
        }
    }

    // MARK: - Contract

    func testContractEchoesIntervalAndSamplingSpan() throws {
        let result = try PlanetObservationContract.evaluate(Self.input())
        let observation = try XCTUnwrap(result["observation"] as? [String: Any])

        XCTAssertEqual(result["target_id"] as? String, "venus")
        XCTAssertEqual(result["night_start"] as? String, "2026-03-01T04:00:00Z")
        XCTAssertEqual(result["night_end"] as? String, "2026-03-01T12:00:00Z")
        XCTAssertEqual(observation["sample_start"] as? String, "2026-03-01T02:00:00Z")
        XCTAssertEqual(observation["sample_end"] as? String, "2026-03-01T13:00:00Z")
        let samples = try XCTUnwrap(observation["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 45)
        XCTAssertEqual(Set(samples[0].keys), ["time", "altitude", "azimuth", "solar_elongation"])
    }

    func testContractReportsANullObservationForAnInvertedNight() throws {
        var input = Self.input()
        input["night_end"] = "2026-03-01T01:00:00Z"
        let result = try PlanetObservationContract.evaluate(input)

        XCTAssertTrue(result["observation"] is NSNull)
    }

    func testContractRejectsUnsupportedTargetIDsIncludingEarth() {
        for identifier in ["earth", "mercury", "Venus", "moon", ""] {
            var input = Self.input()
            input["target_id"] = identifier
            XCTAssertThrowsError(try PlanetObservationContract.evaluate(input), identifier) { error in
                XCTAssertEqual((error as? PlanetObservationInputError)?.code, "validation")
            }
        }
    }

    func testContractFailsClosedOnPathologicalInputs() {
        let mutations: [(String, [String: Any])] = [
            ("span", ["night_end": "2026-03-02T07:00:00Z"]),
            ("boolean latitude", ["latitude": true]),
            ("boolean cadence", ["sample_interval_seconds": true]),
            ("zero cadence", ["sample_interval_seconds": 0]),
            ("negative cadence", ["sample_interval_seconds": -900]),
            ("huge cadence", ["sample_interval_seconds": 93601]),
            ("fractional cadence", ["sample_interval_seconds": 900.5]),
            ("latitude range", ["latitude": 90.1]),
            ("longitude range", ["longitude": -180.1]),
            ("instant below range", ["night_start": "1999-12-31T23:59:59Z"]),
            ("instant above range", ["night_end": "2050-01-01T00:00:00Z"]),
            ("malformed instant", ["night_start": "2026-02-30T00:00:00Z"]),
            ("unknown field", ["extra": 1]),
        ]

        for (label, mutation) in mutations {
            var input = Self.input()
            for (key, value) in mutation { input[key] = value }
            XCTAssertThrowsError(try PlanetObservationContract.evaluate(input), label) { error in
                XCTAssertEqual((error as? PlanetObservationInputError)?.code, "validation", label)
            }
        }
    }

    func testMissingRequiredFieldsFailClosed() {
        for key in ["target_id", "latitude", "longitude", "night_start", "night_end"] {
            var input = Self.input()
            input.removeValue(forKey: key)
            XCTAssertThrowsError(try PlanetObservationContract.evaluate(input), key)
        }
    }

    func testSampleCapIsEnforcedBeforeSampling() {
        for cadence in [1.0, 1e-12] {
            var input = Self.input()
            input["sample_interval_seconds"] = cadence
            XCTAssertThrowsError(try PlanetObservationContract.evaluate(input)) { error in
                let failure = error as? PlanetObservationInputError
                XCTAssertEqual(failure?.code, "sample_cap")
                XCTAssertEqual(
                    failure?.message,
                    "astronomy.planet_observation exceeds the 1.0 sample cap (1440 samples)"
                )
            }
        }
    }

    func testDefaultCadenceIsTheProductionFifteenMinutes() throws {
        var input = Self.input()
        input.removeValue(forKey: "sample_interval_seconds")
        let observation = try XCTUnwrap(
            try PlanetObservationContract.evaluate(input)["observation"] as? [String: Any]
        )
        let samples = try XCTUnwrap(observation["samples"] as? [[String: Any]])

        XCTAssertEqual(samples.count, 45)
    }

    private static func input() -> [String: Any] {
        [
            "target_id": "venus",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "night_start": "2026-03-01T04:00:00Z",
            "night_end": "2026-03-01T12:00:00Z",
            "sample_interval_seconds": 900,
        ]
    }

    private static func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)!
    }
}
