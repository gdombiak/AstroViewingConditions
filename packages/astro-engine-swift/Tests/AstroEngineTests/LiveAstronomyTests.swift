import XCTest
import Foundation
@testable import AstroEngine

final class LiveAstronomyTests: XCTestCase {
    private let sunFields = ["sunset", "civil_twilight_end", "nautical_twilight_end", "astronomical_twilight_end",
                             "astronomical_twilight_begin", "nautical_twilight_begin", "civil_twilight_begin", "sunrise"]
    private func cases() throws -> [[String: Any]] {
        let path = try ContractsRoot.resolve().appendingPathComponent("fixtures/astronomy/cases.json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [[String: Any]]
    }
    func testSunEventSemanticCases() throws {
        for row in try cases() where row["capability"] as? String == "astronomy.sun_events" {
            let input = (row["input"] as! [String: Any])["injected"] as! [String: Any]
            let result = try LiveAstronomy.evaluate("astronomy.sun_events", input: input)
            let name = row["id"] as! String
            XCTAssertEqual(Set(result.keys), Set(sunFields + ["start", "end", "astronomical_night_start", "astronomical_night_end"]), name)
            XCTAssertEqual(result["start"] as? String, input["start"] as? String, name)
            XCTAssertEqual(result["end"] as? String, input["end"] as? String, name)
            XCTAssertEqual(result["astronomical_night_start"] as? String, result["astronomical_twilight_end"] as? String, name)
            XCTAssertEqual(result["astronomical_night_end"] as? String, result["astronomical_twilight_begin"] as? String, name)
            for key in sunFields {
                if let time = result[key] as? String {
                    XCTAssertGreaterThanOrEqual(time, input["start"] as! String, name)
                    XCTAssertLessThan(time, input["end"] as! String, name)
                }
            }
            switch row["semantics"] as! String {
            case "complete_night":
                let times = try sunFields.map { try XCTUnwrap(result[$0] as? String, name) }
                XCTAssertEqual(times, times.sorted(), name)
            case "no_events": XCTAssertTrue(sunFields.allSatisfy { result[$0] is NSNull }, name)
            case "no_visual":
                XCTAssertTrue(result["sunrise"] is NSNull && result["sunset"] is NSNull, name)
                XCTAssertNotNil(result["civil_twilight_begin"] as? String, name)
            case "no_astronomical":
                XCTAssertTrue(result["astronomical_night_start"] is NSNull && result["astronomical_night_end"] is NSNull, name)
            default: XCTFail(name)
            }
        }
    }

    func testMoonInfoAndSeriesSemanticCases() throws {
        // `astronomy.moon_observation` is a different capability with its own
        // night-scoped shape; MoonObservationTests covers it.
        let covered: Set<String> = ["astronomy.moon_info", "astronomy.moon_series"]
        for row in try cases() where covered.contains(row["capability"] as! String) {
            let capability = row["capability"] as! String
            let input = (row["input"] as! [String: Any])["injected"] as! [String: Any]
            let result = try LiveAstronomy.evaluate(capability, input: input)
            let samples = capability == "astronomy.moon_info" ? [result] : result["samples"] as! [[String: Any]]
            let times = input["times"] as? [String] ?? [input["time"] as! String]
            XCTAssertEqual(samples.map { $0["time"] as! String }, times)
            for sample in samples {
                XCTAssertEqual(Set(sample.keys), ["time", "altitude", "illumination"])
                XCTAssertTrue((-90...90.01).contains(sample["altitude"] as! Double))
                XCTAssertTrue((0...100).contains(sample["illumination"] as! Int))
            }
            let semantic = row["semantics"] as! String
            if semantic.hasPrefix("high") {
                XCTAssertGreaterThanOrEqual(result["illumination"] as! Int, 98)
                XCTAssertEqual((result["altitude"] as! Double) > 0, semantic.hasSuffix("above"))
            }
            if semantic == "low" { XCTAssertLessThanOrEqual(result["illumination"] as! Int, 1) }
            if semantic == "mid" {
                XCTAssertTrue((45...55).contains(result["illumination"] as! Int))
            }
            if semantic == "crosses_horizon" {
                XCTAssertLessThan(samples.map { $0["altitude"] as! Double }.min()!, 0)
                XCTAssertGreaterThan(samples.map { $0["altitude"] as! Double }.max()!, 0)
            }
        }
    }

    func testStrictInputValidationBeforeSampling() throws {
        let base: [String: Any] = ["latitude": 0, "longitude": 0, "time": "2024-01-01T00:00:00Z"]
        for time: Any in ["2024-02-30T00:00:00Z", "2023-02-29T00:00:00Z", "2024-01-01T24:00:00Z",
                         "2024-01-01T00:00:60Z", "2024-01-01T00:00:00+00:00", "2024-01-01T00:00:00.0Z",
                         "1999-12-31T23:59:59Z", "2050-01-01T00:00:00Z", NSNull(), true] {
            var input = base; input["time"] = time
            XCTAssertThrowsError(try LiveAstronomy.evaluate("astronomy.moon_info", input: input, moonSampler: UnavailableMoon())) {
                XCTAssertTrue($0 is AstronomyInputError)
            }
        }
        for (key, value): (String, Any) in [("latitude", true), ("latitude", 91), ("longitude", -181),
                                            ("latitude", Double.nan), ("longitude", Double.infinity),
                                            ("time_zone", "UTC"), ("elevation", 1)] {
            var input = base; input[key] = value
            XCTAssertThrowsError(try LiveAstronomy.evaluate("astronomy.moon_info", input: input))
        }
        for times in [["2024-01-01T00:00:00Z", "2024-01-01T00:00:00Z"],
                      ["2024-01-02T00:00:00Z", "2024-01-01T00:00:00Z"],
                      ["2024-01-01T00:00:00Z", "2024-01-03T00:00:01Z"],
                      Array(repeating: "2024-01-01T00:00:00Z", count: 50)] {
            XCTAssertThrowsError(try LiveAstronomy.evaluate("astronomy.moon_series", input: ["latitude": 0, "longitude": 0, "times": times]))
        }
    }

    func testHalfOpenSunBoundaryAndNoFallback() throws {
        let start = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let input: [String: Any] = ["latitude": 0, "longitude": 0, "start": LiveAstronomy.utc(start),
                                   "end": LiveAstronomy.utc(start.addingTimeInterval(3600))]
        let result = try LiveAstronomy.evaluate("astronomy.sun_events", input: input, sunSampler: BoundarySun(start: start))
        XCTAssertEqual(result["sunrise"] as? String, input["start"] as? String)
        XCTAssertTrue(result["sunset"] is NSNull)
        var invalid = input; invalid["end"] = input["start"]
        XCTAssertThrowsError(try LiveAstronomy.evaluate("astronomy.sun_events", input: invalid))
        invalid["end"] = "2024-01-02T02:00:01Z"
        XCTAssertThrowsError(try LiveAstronomy.evaluate("astronomy.sun_events", input: invalid))
    }

    func testMoonPreservesExplicitSamplesAndTruncation() throws {
        let times = ["2024-11-03T05:00:00Z", "2024-11-03T06:00:00Z"]
        let result = try LiveAstronomy.evaluate("astronomy.moon_series", input: ["latitude": 0, "longitude": 0, "times": times], moonSampler: FixedMoon())
        let samples = result["samples"] as! [[String: Any]]
        XCTAssertEqual(samples.map { $0["time"] as! String }, times)
        XCTAssertEqual(samples.map { $0["illumination"] as! Int }, [49, 49])
        XCTAssertEqual(samples.map { $0["altitude"] as! Double }, [-2, -2])
        XCTAssertThrowsError(try LiveAstronomy.evaluate("astronomy.moon_info", input: ["latitude": 0, "longitude": 0, "time": times[0]], moonSampler: UnavailableMoon()))
    }

    func testDeterministicScoringCallGraphHasNoLiveAstronomy() throws {
        let source = try ContractsRoot.resolve().deletingLastPathComponent().appendingPathComponent("packages/astro-engine-swift/Sources/AstroEngine")
        let analyzer = try String(contentsOf: source.appendingPathComponent("Scoring/NightQualityAnalyzer.swift"), encoding: .utf8)
        // The deterministic overload and its shared assessor take sample closures,
        // not a default live sampler. Audit all subsequent helper bodies too.
        let body = analyzer.components(separatedBy: "    /// Deterministic contract analysis:")[1]
            .components(separatedBy: "    public static func analyzeNight(")[1]
        for forbidden in ["SunCalc", "MoonCalculationCache", "NightForecastFilter", "LiveAstronomy"] {
            XCTAssertFalse(body.contains(forbidden), forbidden)
            for file in ["Scoring/TargetScoring.swift", "Scoring/NightConditionsScoring.swift", "Scoring/Phase15Contracts.swift"] {
                XCTAssertFalse(try String(contentsOf: source.appendingPathComponent(file), encoding: .utf8).contains(forbidden), file)
            }
        }
        let start = Date(timeIntervalSince1970: 0)
        let result = try NightQualityAnalyzer.analyzeNight(forecasts: [], nightWindow: NightWindow(start: start, end: start.addingTimeInterval(3600)), moonSeries: [])
        XCTAssertEqual(result.nightStart, start)
    }
}

private struct FixedMoon: MoonSampling {
    func illumination(at time: Date) throws -> MoonIlluminationSample { .init(fraction: 0.499, phaseDegrees: 0) }
    func position(latitude: Double, longitude: Double, at time: Date) throws -> MoonHorizontalCoordinates { .init(altitude: -2, azimuth: 0) }
}
private struct UnavailableMoon: MoonSampling {
    struct Failure: Error {}
    func illumination(at time: Date) throws -> MoonIlluminationSample { throw Failure() }
    func position(latitude: Double, longitude: Double, at time: Date) throws -> MoonHorizontalCoordinates { throw Failure() }
}
private struct BoundarySun: SunEventsSampling {
    let start: Date
    func sunTimes(latitude: Double, longitude: Double, on date: Date, twilight: SunTwilightKind) throws -> SampledRiseSet {
        .init(rise: start, set: start.addingTimeInterval(3600))
    }
}
