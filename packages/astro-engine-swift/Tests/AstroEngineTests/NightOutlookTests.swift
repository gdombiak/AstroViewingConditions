import XCTest
@testable import AstroEngine

/// Focused tests for `observing_night.compose_outlook` and
/// `observing_night.select_best`.
final class NightOutlookTests: XCTestCase {

    // MARK: - Fixtures

    private static func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)!
    }

    private static func day(_ begin: String, _ end: String) -> ObservingNightSelector.DailySunEvents {
        ObservingNightSelector.DailySunEvents(
            astronomicalTwilightEnd: instant(end),
            astronomicalTwilightBegin: instant(begin)
        )
    }

    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    /// Five July days, evening twilight 22:18 local and morning 04:37 local.
    private static let july = (25...29).map { number -> ObservingNightSelector.DailySunEvents in
        let day = String(format: "%02d", number)
        let next = String(format: "%02d", number + 1)
        return NightOutlookTests.day("2026-07-\(day)T11:37:00Z", "2026-07-\(next)T05:18:00Z")
    }

    /// Hourly rows on the hour, starting at local midnight on July 25.
    private static func hourly(count: Int, step: TimeInterval = 3_600) -> [Date] {
        let base = instant("2026-07-25T07:00:00Z")
        return (0..<count).map { base.addingTimeInterval(Double($0) * step) }
    }

    private func compose(
        _ reference: String,
        zone: TimeZone = NightOutlookTests.losAngeles,
        forecastStart: Date? = NightOutlookTests.hourly(count: 1).first,
        days: [ObservingNightSelector.DailySunEvents] = NightOutlookTests.july,
        moonCount: Int = 5,
        hourly: [Date] = NightOutlookTests.hourly(count: 5 * 24)
    ) -> NightOutlook {
        NightOutlookComposer.compose(
            referenceDate: Self.instant(reference),
            timeZone: zone,
            forecastStartTime: forecastStart,
            dailySunEvents: days,
            dailyMoonCount: moonCount,
            hourlyTimes: hourly
        )
    }

    // MARK: - Composition

    func testEveningReferenceComposesThreeConsecutiveAvailableNights() {
        let outlook = compose("2026-07-27T03:00:00Z")  // July 26, 20:00 local
        XCTAssertEqual(outlook.state, .resolved)
        XCTAssertEqual(outlook.nights.map(\.slotIndex), [0, 1, 2])
        XCTAssertEqual(outlook.nights.map(\.dayOffset), [0, 1, 2])
        XCTAssertEqual(outlook.nights.map(\.dayIndex), [1, 2, 3])
        XCTAssertEqual(
            outlook.nights.map(\.observingLocalDate),
            ["2026-07-26", "2026-07-27", "2026-07-28"]
        )
        XCTAssertEqual(outlook.nights.map(\.status), [.available, .available, .available])
    }

    func testAfterMidnightKeepsThePrecedingObservingNightInSlotZero() {
        let outlook = compose("2026-07-26T08:00:00Z")  // July 26, 01:00 local
        XCTAssertEqual(outlook.state, .resolved)
        XCTAssertEqual(outlook.nights.map(\.dayOffset), [-1, 0, 1])
        XCTAssertEqual(
            outlook.nights.map(\.observingLocalDate),
            ["2026-07-25", "2026-07-26", "2026-07-27"]
        )
    }

    func testRequiresActivePreviousPayloadKeepsItsOwnStateAndFallbackDates() {
        // July 25, 01:00 local, with no earlier day represented.
        let outlook = compose(
            "2026-07-25T08:00:00Z",
            forecastStart: Self.instant("2026-07-25T07:00:00Z")
        )
        XCTAssertEqual(outlook.state, .requiresActivePreviousPayload)
        XCTAssertEqual(
            outlook.nights.map(\.observingLocalDate),
            ["2026-07-25", "2026-07-26", "2026-07-27"]
        )
        XCTAssertEqual(outlook.nights.map(\.dayOffset), [0, 1, 2])
        XCTAssertTrue(outlook.nights.allSatisfy { $0.dayIndex == nil })
        XCTAssertTrue(outlook.nights.allSatisfy { $0.status == .unavailable })
        XCTAssertTrue(outlook.nights.allSatisfy { $0.astronomicalNightStart == nil })
    }

    func testCompositionIsAllOrNothingWhenAnyDayLeavesTheDailyArrays() {
        let outlook = compose("2026-07-27T03:00:00Z", days: Array(Self.july.prefix(3)), moonCount: 3)
        XCTAssertEqual(outlook.state, .unavailable)
        XCTAssertEqual(
            outlook.nights.map(\.observingLocalDate),
            ["2026-07-26", "2026-07-27", "2026-07-28"]
        )
        XCTAssertTrue(outlook.nights.allSatisfy { $0.status == .unavailable })
    }

    func testShortMoonArrayAloneStopsComposition() {
        let outlook = compose("2026-07-27T03:00:00Z", moonCount: 3)
        XCTAssertEqual(outlook.state, .unavailable)
    }

    func testTruncatedHourlyStreamMarksOnlyTheUncoveredNightUnavailable() {
        let outlook = compose("2026-07-26T13:00:00Z", hourly: Self.hourly(count: 4 * 24))
        XCTAssertEqual(outlook.nights.map(\.status), [.available, .available, .unavailable])
        // The window is still reported for the uncovered night.
        XCTAssertNotNil(outlook.nights[2].astronomicalNightStart)
        XCTAssertNotNil(outlook.nights[2].astronomicalNightEnd)
    }

    func testMissingAndDuplicateHourlyRowsBreakOnlyTheirOwnNight() {
        var missing = Self.hourly(count: 5 * 24)
        missing.remove(at: 49)  // July 27, 01:00 local — inside the first night
        XCTAssertEqual(
            compose("2026-07-26T13:00:00Z", hourly: missing).nights.map(\.status),
            [.unavailable, .available, .available]
        )

        var duplicated = Self.hourly(count: 5 * 24)
        duplicated.insert(duplicated[49], at: 49)
        XCTAssertEqual(
            compose("2026-07-26T13:00:00Z", hourly: duplicated).nights.map(\.status),
            [.unavailable, .available, .available]
        )
    }

    func testCallerOrderOfHourlyRowsIsNotSemantics() {
        let ordered = compose("2026-07-27T03:00:00Z")
        let reversed = compose("2026-07-27T03:00:00Z", hourly: Self.hourly(count: 5 * 24).reversed())
        XCTAssertEqual(ordered, reversed)
    }

    func testNonHourlyCadenceMakesEveryNightUnavailable() {
        let outlook = compose(
            "2026-07-27T03:00:00Z",
            hourly: Self.hourly(count: 5 * 48, step: 1_800)
        )
        XCTAssertTrue(outlook.nights.allSatisfy { $0.status == .unavailable })
    }

    func testEmptyHourlyStreamCannotCoverAnyNight() {
        let outlook = compose("2026-07-27T03:00:00Z", forecastStart: nil, hourly: [])
        XCTAssertEqual(outlook.state, .resolved)
        XCTAssertTrue(outlook.nights.allSatisfy { $0.status == .unavailable })
    }

    func testEmptyAndInvertedWindowsAreNoAstronomicalNight() {
        var empty = Self.july
        // Day three's evening twilight lands exactly on the next morning's.
        empty[3] = Self.day("2026-07-28T11:37:00Z", "2026-07-29T11:37:00Z")
        XCTAssertEqual(
            compose("2026-07-27T03:00:00Z", days: empty).nights.map(\.status),
            [.available, .available, .noAstronomicalNight]
        )

        var inverted = Self.july
        inverted[3] = Self.day("2026-07-28T11:37:00Z", "2026-07-29T12:00:00Z")
        XCTAssertEqual(
            compose("2026-07-27T03:00:00Z", days: inverted).nights.map(\.status),
            [.available, .available, .noAstronomicalNight]
        )
    }

    func testLastRepresentedDayFallsBackToItsOwnMorningTwilight() {
        let outlook = compose(
            "2026-07-27T03:00:00Z", days: Array(Self.july.prefix(4)), moonCount: 4
        )
        XCTAssertEqual(outlook.state, .resolved)
        XCTAssertEqual(outlook.nights[2].status, .noAstronomicalNight)
        XCTAssertEqual(
            outlook.nights[2].astronomicalNightEnd,
            Self.instant("2026-07-28T11:37:00Z")
        )
    }

    // MARK: - Coverage rule

    func testCoverageRequiresTheStreamToStraddleBothBoundaries() {
        let start = Self.instant("2026-07-26T05:18:00Z")
        let end = Self.instant("2026-07-27T11:37:00Z")
        let full = Self.hourly(count: 5 * 24)
        XCTAssertTrue(NightOutlookComposer.hasCompleteHourlyCoverage(
            astronomicalNightStart: start, astronomicalNightEnd: end, hourlyTimes: full
        ))
        // A stream that begins after the night start cannot cover it.
        XCTAssertFalse(NightOutlookComposer.hasCompleteHourlyCoverage(
            astronomicalNightStart: start, astronomicalNightEnd: end,
            hourlyTimes: Array(full.dropFirst(40))
        ))
        // An inverted window is never covered.
        XCTAssertFalse(NightOutlookComposer.hasCompleteHourlyCoverage(
            astronomicalNightStart: end, astronomicalNightEnd: start, hourlyTimes: full
        ))
    }

    // MARK: - Best night

    func testBestNightPrefersTheHighestScoreAndKeepsTheEarliestTie() {
        func candidates(
            _ rows: [(NightOutlookNightStatus, Int?)]
        ) -> [NightOutlookComposer.BestNightCandidate] {
            rows.map { NightOutlookComposer.BestNightCandidate(status: $0.0, score: $0.1) }
        }

        XCTAssertEqual(
            NightOutlookComposer.selectBestNight(candidates([
                (.available, 72), (.available, 91), (.available, 80)
            ])),
            1
        )
        XCTAssertEqual(
            NightOutlookComposer.selectBestNight(candidates([
                (.available, 91), (.available, 91), (.available, 80)
            ])),
            0
        )
        XCTAssertEqual(
            NightOutlookComposer.selectBestNight(candidates([
                (.available, 40), (.available, 88), (.available, 88)
            ])),
            1
        )
        // A score on a row that is not available never participates.
        XCTAssertEqual(
            NightOutlookComposer.selectBestNight(candidates([
                (.noAstronomicalNight, 99), (.available, 10), (.unavailable, 100)
            ])),
            1
        )
        XCTAssertNil(NightOutlookComposer.selectBestNight(candidates([
            (.available, nil), (.unavailable, nil), (.noAstronomicalNight, nil)
        ])))
        XCTAssertNil(NightOutlookComposer.selectBestNight([]))
    }

    // MARK: - Transport

    private func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        try NightOutlookContract.evaluate(input)
    }

    private var validInput: [String: Any] {
        [
            "reference_time": "2026-07-27T03:00:00Z",
            "time_zone": "America/Los_Angeles",
            "forecast_start_time": "2026-07-25T07:00:00Z",
            "daily_sun_events": (25...29).map { number -> [String: Any] in
                [
                    "astronomical_twilight_begin":
                        "2026-07-\(String(format: "%02d", number))T11:37:00Z",
                    "astronomical_twilight_end":
                        "2026-07-\(String(format: "%02d", number + 1))T05:18:00Z",
                ]
            },
            "daily_moon_count": 5,
            "hourly_times": Self.hourly(count: 24).map { date -> String in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                return formatter.string(from: date)
            },
        ]
    }

    func testTransportReportsEveryKeyForEveryRow() throws {
        let result = try evaluate(validInput)
        XCTAssertEqual(result["state"] as? String, "resolved")
        XCTAssertEqual(result["time_zone"] as? String, "America/Los_Angeles")
        let nights = try XCTUnwrap(result["nights"] as? [[String: Any]])
        XCTAssertEqual(nights.count, 3)
        for night in nights {
            XCTAssertEqual(Set(night.keys), [
                "slot_index", "day_offset", "day_index", "observing_date",
                "observing_day_start", "astronomical_night_start",
                "astronomical_night_end", "status",
            ])
        }
    }

    func testTransportRejectsUnknownKeysZonesAndCaps() {
        var extra = validInput
        extra["display_label"] = "Tonight"
        XCTAssertThrowsError(try evaluate(extra))

        var zone = validInput
        zone["time_zone"] = "US/Pacific"
        XCTAssertThrowsError(try evaluate(zone))

        var days = validInput
        days["daily_sun_events"] = Array(
            repeating: ["astronomical_twilight_begin": "2026-07-25T11:37:00Z",
                        "astronomical_twilight_end": "2026-07-26T05:18:00Z"],
            count: 17
        )
        XCTAssertThrowsError(try evaluate(days)) { error in
            XCTAssertEqual((error as? NightOutlookInputError)?.code, "sample_cap")
        }

        var hourly = validInput
        hourly["hourly_times"] = Array(repeating: "2026-07-25T07:00:00Z", count: 1_441)
        XCTAssertThrowsError(try evaluate(hourly)) { error in
            XCTAssertEqual(
                (error as? NightOutlookInputError)?.message,
                "observing_night.compose_outlook exceeds the 1.0 row cap (1440 rows)"
            )
        }
    }

    func testBestNightTransportRejectsPresentationFieldsAndOutOfRangeScores() throws {
        let ok = try BestNightContract.evaluate(["nights": [
            ["status": "available", "score": 10],
            ["status": "available", "score": 90],
        ]])
        XCTAssertEqual(ok["best_index"] as? Int, 1)

        XCTAssertTrue(
            try BestNightContract.evaluate(["nights": []])["best_index"] is NSNull
        )
        XCTAssertThrowsError(try BestNightContract.evaluate(["nights": [
            ["status": "available", "score": 10, "display_label": "Tonight"]
        ]]))
        XCTAssertThrowsError(try BestNightContract.evaluate(["nights": [
            ["status": "available", "score": 101]
        ]]))
        XCTAssertThrowsError(try BestNightContract.evaluate(["nights": [
            ["status": "great", "score": 10]
        ]]))
        XCTAssertThrowsError(try BestNightContract.evaluate(["nights": Array(
            repeating: ["status": "available", "score": 10] as [String: Any], count: 4
        )])) { error in
            XCTAssertEqual((error as? NightOutlookInputError)?.code, "sample_cap")
        }
    }
}
