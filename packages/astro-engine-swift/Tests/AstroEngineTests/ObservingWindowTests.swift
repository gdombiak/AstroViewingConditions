import XCTest
import Foundation
@testable import AstroEngine

final class ObservingWindowTests: XCTestCase {
    func testManualFixtures() throws { try checkFixtures("observing-window", evaluate: ObservingWindowContract.evaluate) }

    private func checkFixtures(_ name: String, evaluate: ([String: Any]) throws -> [String: Any]) throws {
        let root = try ContractsRoot.resolve().appendingPathComponent("fixtures/capabilities/\(name)")
        let fixtures = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            let input = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("input.json"))) as! [String: Any]
            let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("expected.json"))) as! [String: Any]
            let injected = input["injected"] as! [String: Any]
            if expected["ok"] as? Bool == true {
                let actual = try evaluate(injected)
                XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]),
                    try JSONSerialization.data(withJSONObject: expected["result"]!, options: [.sortedKeys]), fixture.lastPathComponent)
            } else {
                XCTAssertThrowsError(try evaluate(injected), fixture.lastPathComponent) { error in
                    XCTAssertEqual((error as? ObservingWindowInputError)?.message,
                        (expected["error"] as? [String: Any])?["message"] as? String, fixture.lastPathComponent)
                }
            }
        }
    }

    func testAnalyzerPreservesIncludedEndpointsAndRowCountRuns() throws {
        let base = ISO8601DateFormatter().date(from: "2026-09-06T00:00:00Z")!
        func date(_ hour: Int) -> Date { base.addingTimeInterval(Double(hour) * 3600) }
        // Clear rows score zero; cloud-floor rows score >= the default threshold.
        for (clouds, expectedStart, expectedEnd) in [
            ([80, 0, 0, 80], 1, 8), // Half qualify: included endpoints, not bounds.
            ([80, 0, 0, 80, 80], 2, 4), // Gapped two-row run still lasts 7200 s.
        ] {
            let times = [1, 2, 6, 8, 9]
            let forecasts = clouds.enumerated().map { index, cloud in
                HourlyForecast(time: date(times[index]), cloudCover: cloud,
                    humidity: 0, windSpeed: 3, windDirection: 0, temperature: 15)
            }
            let moon = forecasts.map { MoonSample(time: $0.time, altitudeDegrees: -10, illuminationPercent: 0) }
            let assessment = try NightQualityAnalyzer.analyzeNight(
                forecasts: forecasts.reversed(), nightWindow: NightWindow(start: date(0), end: date(10)),
                moonSeries: moon)
            XCTAssertEqual(assessment.bestWindow?.start, date(expectedStart))
            XCTAssertEqual(assessment.bestWindow?.end, date(expectedEnd))
            XCTAssertEqual(assessment.nightStart, date(1))
            XCTAssertEqual(assessment.nightEnd, forecasts.last?.time)
        }
    }

    func testRejectsNonfiniteNumbers() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try ObservingWindowContract.evaluate([
                "hourly_ratings": [["time": "2026-09-06T01:00:00Z", "score": value]]
            ]))
            XCTAssertThrowsError(try ObservingWindowContract.evaluate([
                "hourly_ratings": [], "good_rating_threshold": value
            ]))
        }
    }
}
