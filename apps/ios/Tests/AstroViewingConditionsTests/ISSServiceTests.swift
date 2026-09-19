import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class ISSServiceTests: XCTestCase {

    private func n2yoFixture(_ name: String) throws -> Data {
        try Data(contentsOf: FixtureRoot.url("providers/n2yo/visualpasses/\(name).json"))
    }

    private func decodeN2YO(_ name: String) throws -> N2YOResponse {
        try JSONDecoder().decode(N2YOResponse.self, from: n2yoFixture(name))
    }

    func testVisualPassesURLEncodesAPIKey() throws {
        let url = try XCTUnwrap(ISSService.visualPassesURL(
            latitude: 45.5,
            longitude: -122.7,
            altitude: 12.9,
            days: 5,
            minVisibility: 120,
            apiKey: "abc+123/==&space key"
        ))

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.n2yo.com")
        XCTAssertEqual(url.path, "/rest/v1/satellite/visualpasses/25544/45.5/-122.7/12/5/120")
        XCTAssertTrue(url.absoluteString.contains("apiKey=abc%2B123%2F%3D%3D%26space%20key"))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "abc+123/==&space key")
    }

    func testISSPassParsing() throws {
        let response = try decodeN2YO("two-passes")

        XCTAssertEqual(response.info.satid, 25544)
        XCTAssertEqual(response.info.satname, "ISS (ZARYA)")
        XCTAssertEqual(response.passes?.count, 2)

        let passes = N2YOPassDecoder.passes(from: response)
        XCTAssertEqual(passes.count, 2)
        XCTAssertEqual(passes[0].riseTime, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(passes[0].duration, 300)
        XCTAssertEqual(passes[0].maxElevation, 45.0)
        XCTAssertEqual(passes[0].maxTime, Date(timeIntervalSince1970: 1_700_000_300))
        XCTAssertEqual(passes[0].endTime, Date(timeIntervalSince1970: 1_700_000_600))
        XCTAssertEqual(passes[0].startDirection, "NE")
        XCTAssertEqual(passes[0].maxDirection, "E")
        XCTAssertEqual(passes[0].endDirection, "SE")
        XCTAssertEqual(passes[0].startElevation, 10)
        XCTAssertEqual(passes[0].endElevation, 10)
    }

    func testISSPassFields() throws {
        let response = try decodeN2YO("two-passes")

        guard let passes = response.passes, let firstPass = passes.first else {
            XCTFail("No passes found")
            return
        }

        XCTAssertEqual(firstPass.startAz, 45.0)
        XCTAssertEqual(firstPass.startAzCompass, "NE")
        XCTAssertEqual(firstPass.startEl, 10)
        XCTAssertEqual(firstPass.maxEl, 45.0)
        XCTAssertEqual(firstPass.duration, 300)
    }

    func testISSPassSetTimeCalculation() {
        let riseTime = Date(timeIntervalSince1970: TimeInterval(1700000000))
        let duration: TimeInterval = 300

        let pass = ISSPass(
            riseTime: riseTime,
            duration: duration,
            maxElevation: 45.0
        )

        let expectedSetTime = riseTime.addingTimeInterval(duration)

        XCTAssertEqual(pass.setTime, expectedSetTime)
    }

    func testISSPassUsesExactN2YOEndTimeWhenAvailable() {
        let riseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let exactEndTime = riseTime.addingTimeInterval(600)
        let pass = ISSPass(
            riseTime: riseTime,
            duration: 300,
            maxElevation: 65,
            maxTime: riseTime.addingTimeInterval(300),
            endTime: exactEndTime,
            startDirection: "NW",
            maxDirection: "E",
            endDirection: "SE",
            startElevation: 10,
            endElevation: 10
        )

        XCTAssertEqual(pass.setTime, exactEndTime)
        XCTAssertEqual(pass.startDirection, "NW")
        XCTAssertEqual(pass.maxDirection, "E")
        XCTAssertEqual(pass.endDirection, "SE")
    }

    func testVisiblePassesIncludeActiveAndFutureButExcludeFinishedPasses() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let finished = ISSPass(
            riseTime: now.addingTimeInterval(-600),
            duration: 300,
            maxElevation: 20
        )
        let active = ISSPass(
            riseTime: now.addingTimeInterval(-60),
            duration: 300,
            maxElevation: 40
        )
        let future = ISSPass(
            riseTime: now.addingTimeInterval(600),
            duration: 300,
            maxElevation: 60
        )

        XCTAssertEqual(
            ISSCard.visiblePasses([future, finished, active], at: now).map(\.id),
            [active.id, future.id]
        )
    }

    func testCrossMidnightPassTimeRangeUsesTimesWithoutDates() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 7,
            day: 5,
            hour: 23,
            minute: 59
        )))
        let end = start.addingTimeInterval(10 * 60)

        let range = DateFormatters.formatTimeRange(from: start, to: end, in: timeZone)
        XCTAssertTrue(range.contains("11:59"))
        XCTAssertTrue(range.contains("12:09"))
        XCTAssertFalse(range.contains("2026"))
        XCTAssertFalse(range.contains("7/5"))
        XCTAssertFalse(range.contains("7/6"))
    }

    func testISSPassIdGeneration() {
        let riseTime = Date(timeIntervalSince1970: 1_700_000_000)
        let pass1 = ISSPass(
            riseTime: riseTime,
            duration: 300,
            maxElevation: 45.0
        )

        let pass2 = ISSPass(
            riseTime: riseTime,
            duration: 300,
            maxElevation: 45.0
        )

        XCTAssertEqual(pass1.id, pass2.id, "The same N2YO event should retain its SwiftUI identity")

        let laterPass = ISSPass(
            riseTime: riseTime.addingTimeInterval(60),
            duration: 300,
            maxElevation: 45.0
        )
        XCTAssertNotEqual(pass1.id, laterPass.id)
    }

    // MARK: - Empty Response

    func testISSPassWithNoPasses() throws {
        let response = try decodeN2YO("empty-passes-array")
        XCTAssertTrue(response.passes?.isEmpty ?? true)
        XCTAssertTrue(N2YOPassDecoder.passes(from: response).isEmpty)
    }

    func testISSPassWithNilPasses() throws {
        let response = try decodeN2YO("nil-passes")
        XCTAssertNil(response.passes)
        XCTAssertTrue(N2YOPassDecoder.passes(from: response).isEmpty)
    }

    // MARK: - Error Handling

    func testISSErrorInvalidURL() {
        let error = ISSError.invalidURL

        XCTAssertNotNil(error.localizedDescription)
    }

    func testISSErrorInvalidResponse() {
        let error = ISSError.invalidResponse

        XCTAssertNotNil(error.localizedDescription)
    }

    func testISSErrorApiError() {
        let error = ISSError.apiError(statusCode: 403, message: "Test error message")

        XCTAssertEqual(error.localizedDescription, "Test error message")
    }

    func testISSErrorExplainsCommonHTTPFailures() {
        XCTAssertTrue(
            ISSError.apiError(statusCode: 403, message: nil)
                .localizedDescription.contains("API key")
        )
        XCTAssertTrue(
            ISSError.apiError(statusCode: 429, message: nil)
                .localizedDescription.contains("request limit")
        )
    }
}
