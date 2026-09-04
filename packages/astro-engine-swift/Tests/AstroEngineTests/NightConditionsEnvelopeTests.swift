import XCTest
import Foundation
@testable import AstroEngine

final class NightConditionsEnvelopeTests: XCTestCase {
    func testMissingClockIsValidationError() {
        XCTAssertThrowsError(
            try NightConditionsEnvelope.requireClockAndTimeZone(["time_zone": "UTC"])
        ) { error in
            let analysisError = error as? NightConditionsAnalysisError
            XCTAssertEqual(analysisError, .invalidClock)
            XCTAssertEqual(analysisError?.message, "clock is required")
        }
    }

    func testMissingTimeZoneIsValidationError() {
        XCTAssertThrowsError(
            try NightConditionsEnvelope.requireClockAndTimeZone(["clock": "2026-03-01T12:00:00Z"])
        ) { error in
            let analysisError = error as? NightConditionsAnalysisError
            XCTAssertEqual(analysisError, .invalidTimeZone)
            XCTAssertEqual(analysisError?.message, "time_zone is required")
        }
    }

    func testOffsetClockIsRejectedAsInvalidClock() {
        XCTAssertThrowsError(
            try NightConditionsEnvelope.requireClockAndTimeZone([
                "clock": "2026-03-01T12:00:00-08:00",
                "time_zone": "UTC",
            ])
        ) { error in
            XCTAssertEqual(error as? NightConditionsAnalysisError, .invalidClock)
        }
    }

    func testInvalidTimeZoneIsValidationError() {
        XCTAssertThrowsError(
            try NightConditionsEnvelope.requireClockAndTimeZone([
                "clock": "2026-03-01T12:00:00Z",
                "time_zone": "Not/AZone",
            ])
        ) { error in
            let analysisError = error as? NightConditionsAnalysisError
            XCTAssertEqual(analysisError, .invalidTimeZone)
        }
    }

    func testEmptyAndNonStringTimeZoneAreValidationErrors() {
        XCTAssertThrowsError(
            try NightConditionsEnvelope.requireClockAndTimeZone([
                "clock": "2026-03-01T12:00:00Z",
                "time_zone": "",
            ])
        )
        XCTAssertThrowsError(
            try NightConditionsEnvelope.requireClockAndTimeZone([
                "clock": "2026-03-01T12:00:00Z",
                "time_zone": 1,
            ])
        )
    }

    func testExistingNightConditionFixturesRemainValid() throws {
        let root = try ContractsRoot.resolve()
        for fixture in ["four-clear-hours-v1", "empty-night-v1"] {
            let url = root
                .appendingPathComponent("fixtures/capabilities/night-conditions/\(fixture)/input.json")
            let data = try Data(contentsOf: url)
            let raw = try JSONSerialization.jsonObject(with: data)
            let document = try XCTUnwrap(raw as? [String: Any])
            XCTAssertNoThrow(try NightConditionsEnvelope.requireClockAndTimeZone(document), fixture)
        }
    }
}
