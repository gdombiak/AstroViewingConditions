import XCTest
@testable import AstroEngine

/// Focused tests for `observing_night.resolve_active`.
final class ObservingNightTests: XCTestCase {

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
    private static let february = [
        day("2026-02-18T13:35:00Z", "2026-02-19T03:15:00Z"),
        day("2026-02-19T13:34:00Z", "2026-02-20T03:16:00Z"),
        day("2026-02-20T13:33:00Z", "2026-02-21T03:17:00Z"),
        day("2026-02-21T13:32:00Z", "2026-02-22T03:18:00Z"),
    ]
    private static let forecastStart = instant("2026-02-18T08:00:00Z")

    private func select(
        _ reference: String,
        zone: TimeZone = ObservingNightTests.losAngeles,
        forecastStart: Date? = ObservingNightTests.forecastStart,
        days: [ObservingNightSelector.DailySunEvents] = ObservingNightTests.february,
        moonCount: Int = 4
    ) -> ObservingNightSelection {
        ObservingNightSelector.select(
            referenceDate: Self.instant(reference),
            timeZone: zone,
            forecastStartTime: forecastStart,
            dailySunEvents: days,
            dailyMoonCount: moonCount
        )
    }

    private func night(_ selection: ObservingNightSelection) -> ObservingNight? {
        guard case let .selected(night) = selection else { return nil }
        return night
    }

    // MARK: - States

    func testEveningResolvesTheReferenceCivilDate() {
        let resolved = night(select("2026-02-20T05:00:00Z"))
        XCTAssertEqual(resolved?.dayOffset, 0)
        XCTAssertEqual(resolved?.dayIndex, 1)
        XCTAssertEqual(resolved?.observingLocalDate, "2026-02-19")
        XCTAssertEqual(resolved?.astronomicalNightStart, Self.instant("2026-02-20T03:16:00Z"))
        XCTAssertEqual(resolved?.astronomicalNightEnd, Self.instant("2026-02-20T13:33:00Z"))
    }

    func testAfterMidnightKeepsThePrecedingCivilDate() {
        let resolved = night(select("2026-02-20T10:00:00Z"))
        XCTAssertEqual(resolved?.dayOffset, -1)
        XCTAssertEqual(resolved?.observingLocalDate, "2026-02-19")
        XCTAssertEqual(resolved?.observingDayStart, Self.instant("2026-02-19T08:00:00Z"))
    }

    func testDaytimeAlreadyResolvesTheCurrentDate() {
        XCTAssertEqual(night(select("2026-02-19T20:00:00Z"))?.observingLocalDate, "2026-02-19")
    }

    /// The three states are separate product facts and must never collapse.
    func testStatesAreDistinct() {
        XCTAssertEqual(select("2026-02-18T12:00:00Z"), .requiresActivePreviousPayload)
        XCTAssertEqual(select("2026-02-23T05:00:00Z"), .unavailable)
        XCTAssertNotEqual(select("2026-02-18T12:00:00Z"), select("2026-02-23T05:00:00Z"))
    }

    // MARK: - Boundary inclusivity

    func testMorningTwilightBeginComparisonIsInclusive() {
        XCTAssertEqual(select("2026-02-18T13:34:59Z"), .requiresActivePreviousPayload)
        XCTAssertEqual(select("2026-02-18T13:35:00Z"), .requiresActivePreviousPayload)
        XCTAssertEqual(night(select("2026-02-18T13:35:01Z"))?.dayOffset, 0)
    }

    func testPreviousNightEndComparisonIsInclusive() {
        XCTAssertEqual(night(select("2026-02-20T13:32:59Z"))?.dayOffset, -1)
        XCTAssertEqual(night(select("2026-02-20T13:33:00Z"))?.dayOffset, -1)
        XCTAssertEqual(night(select("2026-02-20T13:33:01Z"))?.dayOffset, 0)
    }

    /// Only reachable where evening twilight ends after local midnight.
    func testPreviousNightStartComparisonIsInclusive() {
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        let days = [
            Self.day("2026-06-19T01:44:00Z", "2026-06-19T22:14:00Z"),
            Self.day("2026-06-20T01:45:00Z", "2026-06-20T22:15:00Z"),
            Self.day("2026-06-21T01:45:00Z", "2026-06-21T22:16:00Z"),
        ]
        let start = select(
            "2026-06-20T22:15:00Z", zone: madrid,
            forecastStart: Self.instant("2026-06-18T22:00:00Z"), days: days, moonCount: 3
        )
        XCTAssertEqual(night(start)?.dayOffset, -1)
        XCTAssertEqual(night(start)?.observingLocalDate, "2026-06-20")
        XCTAssertEqual(
            select(
                "2026-06-20T22:14:59Z", zone: madrid,
                forecastStart: Self.instant("2026-06-18T22:00:00Z"), days: days, moonCount: 3
            ),
            .requiresActivePreviousPayload
        )
    }

    // MARK: - Indexing

    func testEmptyHourlyForecastUsesTheBareDayOffset() {
        let resolved = night(select("2026-02-20T10:00:00Z", forecastStart: nil))
        XCTAssertEqual(resolved?.dayIndex, 0)
        XCTAssertEqual(resolved?.dayOffset, 0)
        XCTAssertEqual(resolved?.observingLocalDate, "2026-02-20")
    }

    func testEmptyHourlyForecastCanNeverResolveThePrecedingNight() {
        for reference in ["2026-02-19T10:00:00Z", "2026-02-20T10:00:00Z", "2026-02-21T10:00:00Z"] {
            XCTAssertNotEqual(night(select(reference, forecastStart: nil))?.dayOffset, -1, reference)
        }
    }

    func testForecastStartingAfterTheReferenceDayIsUnavailable() {
        XCTAssertEqual(
            select("2026-02-18T05:00:00Z", forecastStart: Self.instant("2026-02-20T08:00:00Z")),
            .unavailable
        )
    }

    func testShortMoonArrayBoundsTheSelection() {
        XCTAssertEqual(select("2026-02-20T05:00:00Z", moonCount: 1), .unavailable)
        XCTAssertNotNil(night(select("2026-02-20T05:00:00Z", moonCount: 2)))
    }

    func testMissingFollowingRowFallsBackToTheSameDayMorningTwilight() {
        let resolved = night(select("2026-02-22T05:00:00Z"))
        XCTAssertEqual(resolved?.dayIndex, 3)
        XCTAssertEqual(resolved?.astronomicalNightStart, Self.instant("2026-02-22T03:18:00Z"))
        XCTAssertEqual(resolved?.astronomicalNightEnd, Self.instant("2026-02-21T13:32:00Z"))
    }

    // MARK: - DST

    func testSpringForwardAfterMidnightStaysOnThePrecedingNight() {
        let days = [
            Self.day("2026-03-07T13:11:00Z", "2026-03-08T03:33:00Z"),
            Self.day("2026-03-08T13:09:00Z", "2026-03-09T03:34:00Z"),
            Self.day("2026-03-09T13:08:00Z", "2026-03-10T03:35:00Z"),
        ]
        let resolved = night(select(
            "2026-03-08T11:00:00Z",
            forecastStart: Self.instant("2026-03-07T08:00:00Z"), days: days, moonCount: 3
        ))
        XCTAssertEqual(resolved?.dayOffset, -1)
        XCTAssertEqual(resolved?.observingLocalDate, "2026-03-07")
        XCTAssertEqual(resolved?.observingDayStart, Self.instant("2026-03-07T08:00:00Z"))
    }

    func testFallBackRepeatedHourStaysOnThePrecedingNight() {
        let days = [
            Self.day("2026-10-31T12:41:00Z", "2026-11-01T01:53:00Z"),
            Self.day("2026-11-01T13:42:00Z", "2026-11-02T01:52:00Z"),
            Self.day("2026-11-02T13:43:00Z", "2026-11-03T01:51:00Z"),
        ]
        let resolved = night(select(
            "2026-11-01T09:00:00Z",
            forecastStart: Self.instant("2026-10-31T07:00:00Z"), days: days, moonCount: 3
        ))
        XCTAssertEqual(resolved?.dayOffset, -1)
        XCTAssertEqual(resolved?.observingLocalDate, "2026-10-31")
        XCTAssertEqual(resolved?.observingDayStart, Self.instant("2026-10-31T07:00:00Z"))
    }

    /// Santiago skips local midnight on 2026-09-06, so the observing day starts
    /// at 01:00 local and whole-day differencing loses a day. Frozen quirk.
    func testSkippedLocalMidnightDayStartAndIndexQuirk() {
        let santiago = TimeZone(identifier: "America/Santiago")!
        let days = [
            Self.day("2026-09-05T10:30:00Z", "2026-09-05T23:50:00Z"),
            Self.day("2026-09-06T09:29:00Z", "2026-09-06T23:51:00Z"),
            Self.day("2026-09-07T09:27:00Z", "2026-09-07T23:52:00Z"),
            Self.day("2026-09-08T09:25:00Z", "2026-09-08T23:53:00Z"),
        ]
        let crossing = night(select(
            "2026-09-07T06:00:00Z", zone: santiago,
            forecastStart: Self.instant("2026-09-05T04:00:00Z"), days: days
        ))
        XCTAssertEqual(crossing?.observingLocalDate, "2026-09-06")
        XCTAssertEqual(crossing?.observingDayStart, Self.instant("2026-09-06T04:00:00Z"))

        let quirk = night(select(
            "2026-09-08T02:00:00Z", zone: santiago,
            forecastStart: Self.instant("2026-09-06T05:00:00Z"), days: days
        ))
        // Two civil days after the first forecast day, but the index is 0.
        XCTAssertEqual(quirk?.dayIndex, 0)
        XCTAssertEqual(quirk?.observingLocalDate, "2026-09-07")
    }

    /// `date(byAdding:)` is not `startOfDay`: on a repeated local midnight it
    /// keeps the source instant's offset and lands on the LATER occurrence.
    /// `America/Havana` repeats local midnight on 2026-11-01.
    func testRepeatedLocalMidnightKeepsTheSourceOffset() {
        let havana = TimeZone(identifier: "America/Havana")!
        let calendar = ObservingCalendar.gregorian(for: havana)
        let referenceDay = calendar.startOfDay(for: Self.instant("2026-11-02T07:00:00Z"))
        XCTAssertEqual(referenceDay, Self.instant("2026-11-02T05:00:00Z"))
        XCTAssertEqual(
            calendar.date(byAdding: .day, value: -1, to: referenceDay),
            Self.instant("2026-11-01T05:00:00Z")
        )
        // startOfDay of that same civil date is the earlier occurrence.
        XCTAssertEqual(
            calendar.startOfDay(for: Self.instant("2026-11-01T12:00:00Z")),
            Self.instant("2026-11-01T04:00:00Z")
        )

        let days = [
            Self.day("2026-10-31T10:30:00Z", "2026-10-31T23:10:00Z"),
            Self.day("2026-11-01T11:31:00Z", "2026-11-02T00:11:00Z"),
            Self.day("2026-11-02T11:32:00Z", "2026-11-03T00:12:00Z"),
        ]
        let resolved = night(select(
            "2026-11-02T07:00:00Z", zone: havana,
            forecastStart: Self.instant("2026-10-31T04:00:00Z"), days: days, moonCount: 3
        ))
        XCTAssertEqual(resolved?.dayOffset, -1)
        XCTAssertEqual(resolved?.observingLocalDate, "2026-11-01")
        XCTAssertEqual(resolved?.observingDayStart, Self.instant("2026-11-01T05:00:00Z"))
    }

    func testRepeatedLocalMidnightInASecondCurrentZone() {
        let azores = TimeZone(identifier: "Atlantic/Azores")!
        let calendar = ObservingCalendar.gregorian(for: azores)
        let referenceDay = calendar.startOfDay(for: Self.instant("2026-10-26T02:00:00Z"))
        XCTAssertEqual(referenceDay, Self.instant("2026-10-26T01:00:00Z"))
        XCTAssertEqual(
            calendar.date(byAdding: .day, value: -1, to: referenceDay),
            Self.instant("2026-10-25T01:00:00Z")
        )
        XCTAssertEqual(
            calendar.startOfDay(for: Self.instant("2026-10-25T12:00:00Z")),
            Self.instant("2026-10-25T00:00:00Z")
        )
    }

    func testNonWholeHourOffsetsAreHonoured() {
        let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!
        let days = [
            Self.day("2026-04-09T22:50:00Z", "2026-04-10T14:10:00Z"),
            Self.day("2026-04-10T22:49:00Z", "2026-04-11T14:11:00Z"),
        ]
        let resolved = night(select(
            "2026-04-10T19:45:00Z", zone: kathmandu,
            forecastStart: Self.instant("2026-04-09T18:15:00Z"), days: days, moonCount: 2
        ))
        XCTAssertEqual(resolved?.observingDayStart, Self.instant("2026-04-09T18:15:00Z"))
        XCTAssertEqual(resolved?.observingLocalDate, "2026-04-10")
    }

    // MARK: - Transport

    private func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        try ObservingNightContract.evaluate(input)
    }

    private static func transportDay(_ begin: String, _ end: String) -> [String: Any] {
        ["astronomical_twilight_begin": begin, "astronomical_twilight_end": end]
    }

    private static func transportInput(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var input: [String: Any] = [
            "reference_time": "2026-02-20T05:00:00Z",
            "time_zone": "America/Los_Angeles",
            "forecast_start_time": "2026-02-18T08:00:00Z",
            "daily_sun_events": [
                transportDay("2026-02-18T13:35:00Z", "2026-02-19T03:15:00Z"),
                transportDay("2026-02-19T13:34:00Z", "2026-02-20T03:16:00Z"),
                transportDay("2026-02-20T13:33:00Z", "2026-02-21T03:17:00Z"),
                transportDay("2026-02-21T13:32:00Z", "2026-02-22T03:18:00Z"),
            ],
            "daily_moon_count": 4,
        ]
        for (key, value) in overrides { input[key] = value }
        return input
    }

    func testTransportEchoesTheZoneAndAlwaysCarriesEveryKey() throws {
        let expected: Set<String> = [
            "state", "time_zone", "day_offset", "day_index", "observing_date",
            "observing_day_start", "astronomical_night_start", "astronomical_night_end",
        ]
        for reference in ["2026-02-20T05:00:00Z", "2026-02-18T12:00:00Z", "2026-02-23T05:00:00Z"] {
            let result = try evaluate(Self.transportInput(["reference_time": reference]))
            XCTAssertEqual(Set(result.keys), expected, reference)
            XCTAssertEqual(result["time_zone"] as? String, "America/Los_Angeles")
        }
    }

    func testTransportReportsNullForFieldsAStateDoesNotCarry() throws {
        let result = try evaluate(Self.transportInput(["reference_time": "2026-02-23T05:00:00Z"]))
        XCTAssertEqual(result["state"] as? String, "unavailable")
        for key in ["day_offset", "day_index", "observing_date", "observing_day_start",
                    "astronomical_night_start", "astronomical_night_end"] {
            XCTAssertTrue(result[key] is NSNull, key)
        }
    }

    func testTransportFailsClosed() {
        let invalid: [[String: Any]] = [
            ["time_zone": "Mars/Olympus_Mons"],
            ["time_zone": ""],
            ["time_zone": 0],
            ["reference_time": "2026-02-20T05:00Z"],
            ["reference_time": "1999-12-31T23:59:59Z"],
            ["reference_time": NSNull()],
            ["forecast_start_time": "not-a-time"],
            ["daily_sun_events": [:]],
            ["daily_sun_events": [["astronomical_twilight_begin": "2026-02-18T13:35:00Z"]]],
            ["daily_sun_events": [Self.transportDay("2026-02-18T13:35:00Z", "2026-02-19T03:15:00Z")
                .merging(["sunset": "2026-02-19T02:00:00Z"]) { current, _ in current }]],
            ["daily_moon_count": true],
            ["daily_moon_count": 2.5],
            ["daily_moon_count": -1],
            ["daily_moon_count": 17],
        ]
        for overrides in invalid {
            XCTAssertThrowsError(try evaluate(Self.transportInput(overrides)), "\(overrides)") { error in
                XCTAssertEqual((error as? ObservingNightInputError)?.code, "validation")
            }
        }
        var unknownKey = Self.transportInput()
        unknownKey["location"] = [:]
        XCTAssertThrowsError(try evaluate(unknownKey))
        var missingKey = Self.transportInput()
        missingKey.removeValue(forKey: "forecast_start_time")
        XCTAssertThrowsError(try evaluate(missingKey))
    }

    func testTransportDayCap() {
        XCTAssertEqual(ObservingNightContract.maxDayCount, 16)
        let row = Self.transportDay("2026-02-18T13:35:00Z", "2026-02-19T03:15:00Z")
        XCTAssertThrowsError(
            try evaluate(Self.transportInput(["daily_sun_events": Array(repeating: row, count: 17)]))
        ) { error in
            XCTAssertEqual((error as? ObservingNightInputError)?.code, "sample_cap")
        }
    }

    // MARK: - Transport policy

    func testTimeZonePolicyIsOneSharedCatalogueNotFoundationsParser() throws {
        let allowed = try ObservingNightContract.allowedTimeZoneIdentifiers()
        XCTAssertEqual(allowed.count, 442)
        for catalogued in ["America/Los_Angeles", "America/Havana", "Atlantic/Azores",
                           "Pacific/Apia", "Pacific/Fakaofo", "Australia/Lord_Howe",
                           "Asia/Kathmandu", "America/Santiago", "Europe/Madrid"] {
            XCTAssertTrue(allowed.contains(catalogued), catalogued)
        }
        // Foundation parses all of these; the public transport must not.
        for alias in ["GMT-0800", "GMT+0530", "GMT", "UTC", "Etc/GMT+8",
                      "US/Pacific", "EST5EDT", "Zulu"] {
            XCTAssertNotNil(TimeZone(identifier: alias), "\(alias) parses in Foundation")
            XCTAssertFalse(allowed.contains(alias), alias)
            XCTAssertThrowsError(try evaluate(Self.transportInput(["time_zone": alias]))) { error in
                XCTAssertEqual((error as? ObservingNightInputError)?.code, "validation")
            }
        }
        XCTAssertTrue(allowed.allSatisfy { $0.contains("/") })
    }

    /// Pacific/Apia and Pacific/Fakaofo have no 2011-12-30. A window containing a
    /// dropped civil date is refused rather than answered differently per host.
    func testWindowContainingADroppedCivilDateIsRefused() {
        let samoa = [
            Self.transportDay("2011-12-28T15:30:00Z", "2011-12-29T07:10:00Z"),
            Self.transportDay("2011-12-29T15:31:00Z", "2011-12-30T07:11:00Z"),
            Self.transportDay("2011-12-30T15:32:00Z", "2011-12-31T07:12:00Z"),
        ]
        for zone in ["Pacific/Apia", "Pacific/Fakaofo"] {
            XCTAssertThrowsError(try evaluate(Self.transportInput([
                "reference_time": "2011-12-31T12:00:00Z",
                "time_zone": zone,
                "forecast_start_time": "2011-12-28T10:00:00Z",
                "daily_sun_events": samoa,
                "daily_moon_count": 3,
            ])), zone) { error in
                XCTAssertEqual((error as? ObservingNightInputError)?.code, "validation")
            }
        }
    }

    func testTheSameZoneIsAcceptedAwayFromItsDroppedDate() throws {
        let result = try evaluate(Self.transportInput([
            "reference_time": "2026-06-16T08:00:00Z",
            "time_zone": "Pacific/Apia",
            "forecast_start_time": "2026-06-14T11:00:00Z",
            "daily_sun_events": [
                Self.transportDay("2026-06-14T15:30:00Z", "2026-06-15T07:10:00Z"),
                Self.transportDay("2026-06-15T15:31:00Z", "2026-06-16T07:11:00Z"),
                Self.transportDay("2026-06-16T15:32:00Z", "2026-06-17T07:12:00Z"),
            ],
            "daily_moon_count": 3,
        ]))
        XCTAssertEqual(result["state"] as? String, "resolved")
        XCTAssertEqual(result["observing_date"] as? String, "2026-06-16")
    }

    /// A skipped hour is not a skipped date: ordinary DST zones are unaffected.
    func testOrdinaryDstZonesAreNotRefused() throws {
        for zone in ["America/Santiago", "America/Havana", "Atlantic/Azores"] {
            let result = try evaluate(Self.transportInput(["time_zone": zone]))
            XCTAssertNotNil(result["state"], zone)
        }
    }

    func testInstantRangeBoundaries() throws {
        for accepted in ["2000-01-01T00:00:00Z", "2499-12-31T23:59:59Z"] {
            let result = try evaluate(Self.transportInput(["reference_time": accepted]))
            XCTAssertEqual(result["state"] as? String, "unavailable", accepted)
        }
        for rejected in ["1999-12-31T23:59:59Z", "2500-01-01T00:00:00Z"] {
            XCTAssertThrowsError(
                try evaluate(Self.transportInput(["reference_time": rejected])), rejected
            )
        }
        XCTAssertEqual(ObservingNightContract.latestInstant.timeIntervalSince1970, 16_725_225_599)
        XCTAssertEqual(ObservingNightContract.earliestInstant.timeIntervalSince1970, 946_684_800)
    }

    /// The array cap is `sample_cap`; an out-of-domain scalar is `validation`.
    func testMoonCountAboveCapIsValidationNotSampleCap() {
        XCTAssertThrowsError(try evaluate(Self.transportInput(["daily_moon_count": 17]))) { error in
            XCTAssertEqual((error as? ObservingNightInputError)?.code, "validation")
        }
    }

    func testCapabilityIdentity() {
        XCTAssertEqual(ObservingNightSelector.capabilityID, "observing_night.resolve_active")
        XCTAssertEqual(ObservingNightContract.capabilityID, ObservingNightSelector.capabilityID)
    }

    /// The engine already owns the boundary accessors; the transported pair is
    /// exactly what `SunEvents` exposes.
    func testDailySunEventsMirrorsSunEvents() {
        let events = SunEvents(
            sunrise: Self.instant("2026-02-19T14:20:00Z"),
            sunset: Self.instant("2026-02-20T01:40:00Z"),
            civilTwilightBegin: Self.instant("2026-02-19T13:55:00Z"),
            civilTwilightEnd: Self.instant("2026-02-20T02:05:00Z"),
            nauticalTwilightBegin: Self.instant("2026-02-19T13:25:00Z"),
            nauticalTwilightEnd: Self.instant("2026-02-20T02:35:00Z"),
            astronomicalTwilightBegin: Self.instant("2026-02-19T13:34:00Z"),
            astronomicalTwilightEnd: Self.instant("2026-02-20T03:16:00Z")
        )
        let row = ObservingNightSelector.DailySunEvents(events)
        XCTAssertEqual(row.astronomicalTwilightEnd, events.astronomicalNightStart)
        XCTAssertEqual(row.astronomicalTwilightBegin, events.astronomicalNightEnd)
    }
}
