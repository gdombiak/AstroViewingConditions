import Foundation
import XCTest
@testable import AstroEngine

final class NightForecastWindowTests: XCTestCase {
    private static func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)!
    }

    private static func calendar(_ identifier: String) -> Calendar {
        ObservingCalendar.gregorian(for: TimeZone(identifier: identifier)!)
    }

    private static func events(begin: String, end: String) -> SunEvents {
        let begin = instant(begin)
        let end = instant(end)
        return SunEvents(
            sunrise: begin,
            sunset: end,
            civilTwilightBegin: begin,
            civilTwilightEnd: end,
            nauticalTwilightBegin: begin,
            nauticalTwilightEnd: end,
            astronomicalTwilightBegin: begin,
            astronomicalTwilightEnd: end
        )
    }

    /// Frozen copy of the pre-migration production implementation. This oracle
    /// deliberately does not call `NightForecastWindowDeriver` or the adapter.
    private static func legacyRange(
        today: SunEvents,
        tomorrow: SunEvents?,
        date: Date,
        calendar: Calendar
    ) -> NightForecastWindow {
        let startOfDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(24 * 60 * 60)
        let duskHour = calendar.component(.hour, from: today.astronomicalTwilightEnd)
        let duskMinute = calendar.component(.minute, from: today.astronomicalTwilightEnd)
        let start = calendar.date(
            bySettingHour: duskHour, minute: duskMinute, second: 0, of: startOfDay
        ) ?? today.astronomicalTwilightEnd
        let tomorrowEvents = tomorrow ?? today
        let dawnHour = calendar.component(.hour, from: tomorrowEvents.astronomicalTwilightBegin)
        let dawnMinute = calendar.component(.minute, from: tomorrowEvents.astronomicalTwilightBegin)
        let end = calendar.date(
            bySettingHour: dawnHour, minute: dawnMinute, second: 0, of: nextDay
        ) ?? tomorrowEvents.astronomicalTwilightBegin
        return NightForecastWindow(start: start, end: end)
    }

    func testMigrationMatchesIndependentLegacyOracleAcrossCalendarEdges() {
        let cases: [(String, String, String, String, String, String?)] = [
            ("ordinary", "America/Los_Angeles", "2026-02-19T20:00:00Z",
             "2026-02-20T03:16:47Z", "2026-02-19T13:34:59Z", "2026-02-20T13:33:58Z"),
            ("spring gap", "America/Los_Angeles", "2026-03-08T20:00:00Z",
             "2026-03-07T10:30:11Z", "2026-03-07T13:00:22Z", "2026-03-09T12:15:33Z"),
            ("fall repeat", "America/Los_Angeles", "2026-11-01T20:00:00Z",
             "2026-10-31T08:30:11Z", "2026-10-31T13:00:22Z", "2026-11-02T13:10:33Z"),
            ("midnight gap", "America/Santiago", "2026-09-06T20:00:00Z",
             "2026-09-05T04:30:11Z", "2026-09-05T09:40:22Z", "2026-09-07T08:30:33Z"),
            ("quarter-hour zone", "Asia/Kathmandu", "2026-04-10T06:15:00Z",
             "2026-04-10T15:02:44Z", "2026-04-09T23:22:55Z", nil),
            ("dropped date", "Pacific/Apia", "2011-12-29T12:00:00Z",
             "2011-12-30T06:00:44Z", "2011-12-29T15:00:55Z", "2011-12-30T15:00:33Z"),
            ("Lord Howe partial-hour gap", "Australia/Lord_Howe", "2026-10-04T12:00:00Z",
             "2026-10-02T15:45:11Z", "2026-10-02T19:00:22Z", "2026-10-04T19:00:33Z"),
            ("Chatham quarter-boundary gap", "Pacific/Chatham", "2026-09-26T12:00:00Z",
             "2026-09-25T14:00:11Z", "2026-09-25T16:15:22Z", "2026-09-27T16:15:33Z"),
            ("Bahia Banderas two-hour gap", "America/Bahia_Banderas", "2010-04-04T12:00:00Z",
             "2010-04-03T09:30:11Z", "2010-04-03T12:00:22Z", "2010-04-05T11:00:33Z"),
            ("Godthab late-day gap", "America/Godthab", "2024-03-30T12:00:00Z",
             "2024-03-29T01:30:11Z", "2024-03-29T08:00:22Z", "2024-04-01T00:45:33Z"),
            ("Caracas valid post-transition clock", "America/Caracas", "2016-05-01T12:00:00Z",
             "2016-05-01T07:15:11Z", "2016-05-01T10:00:22Z", "2016-05-02T10:00:33Z"),
            ("Casey multi-hour midnight gap", "Antarctica/Casey", "2016-10-21T16:00:00Z",
             "2016-10-20T16:30:11Z", "2016-10-20T22:00:22Z", "2016-10-22T19:00:33Z"),
            ("St. John's 00:01 fall-back", "America/St_Johns", "2000-10-29T16:00:00Z",
             "2000-10-29T02:31:11Z", "2000-10-29T09:00:22Z", "2000-10-30T02:31:33Z"),
            ("Casey backward jump at 23:00", "Antarctica/Casey", "2010-03-05T04:00:00Z",
             "2010-03-04T15:15:11Z", "2010-03-04T20:00:22Z", "2010-03-05T15:15:33Z"),
            ("Pyongyang midnight half-hour jump", "Asia/Pyongyang", "2018-05-04T03:00:00Z",
             "2018-05-04T14:30:11Z", "2018-05-03T19:00:22Z", "2018-05-05T14:30:33Z"),
        ]

        for (name, identifier, date, dusk, dawn, tomorrowDawn) in cases {
            let calendar = Self.calendar(identifier)
            let today = Self.events(begin: dawn, end: dusk)
            let tomorrow = tomorrowDawn.map { Self.events(begin: $0, end: dusk) }
            let expected = Self.legacyRange(
                today: today, tomorrow: tomorrow, date: Self.instant(date), calendar: calendar
            )
            let actual = NightForecastWindowDeriver.derive(
                sunEventsToday: today,
                sunEventsTomorrow: tomorrow,
                for: Self.instant(date),
                calendar: calendar
            )
            XCTAssertEqual(actual, expected, name)

            let adapter = NightForecastFilter.calculateNightRange(
                sunEventsToday: today,
                sunEventsTomorrow: tomorrow,
                for: Self.instant(date),
                calendar: calendar
            )
            XCTAssertEqual(adapter.start, expected.start, name)
            XCTAssertEqual(adapter.end, expected.end, name)
        }
    }

    func testDstGapAndRepeatedHourResultsAreFrozen() {
        let spring = NightForecastWindowDeriver.derive(
            astronomicalTwilightEnd: Self.instant("2026-03-07T10:30:11Z"),
            astronomicalTwilightBegin: Self.instant("2026-03-07T13:00:22Z"),
            tomorrowAstronomicalTwilightBegin: Self.instant("2026-03-09T12:15:33Z"),
            for: Self.instant("2026-03-08T20:00:00Z"),
            calendar: Self.calendar("America/Los_Angeles")
        )
        XCTAssertEqual(spring.start, Self.instant("2026-03-08T10:00:00Z"))
        XCTAssertEqual(spring.end, Self.instant("2026-03-09T12:15:00Z"))

        let fall = NightForecastWindowDeriver.derive(
            astronomicalTwilightEnd: Self.instant("2026-10-31T08:30:11Z"),
            astronomicalTwilightBegin: Self.instant("2026-10-31T13:00:22Z"),
            tomorrowAstronomicalTwilightBegin: Self.instant("2026-11-02T13:10:33Z"),
            for: Self.instant("2026-11-01T20:00:00Z"),
            calendar: Self.calendar("America/Los_Angeles")
        )
        XCTAssertEqual(fall.start, Self.instant("2026-11-01T08:30:00Z"))
        XCTAssertEqual(fall.end, Self.instant("2026-11-02T13:10:00Z"))
    }

    func testNonstandardForwardTransitionResultsAreFrozen() {
        let cases: [(String, String, String, Int, Int, String)] = [
            ("Lord Howe", "Australia/Lord_Howe", "2026-10-04T12:00:00Z", 2, 15,
             "2026-10-04T15:15:00Z"),
            ("Chatham", "Pacific/Chatham", "2026-09-26T12:00:00Z", 2, 45,
             "2026-09-26T14:15:00Z"),
            ("Bahia Banderas", "America/Bahia_Banderas", "2010-04-04T12:00:00Z", 2, 30,
             "2010-04-05T07:30:00Z"),
            ("Godthab", "America/Godthab", "2024-03-30T12:00:00Z", 23, 30,
             "2024-04-01T00:30:00Z"),
            ("Caracas", "America/Caracas", "2016-05-01T12:00:00Z", 3, 15,
             "2016-05-02T07:15:00Z"),
            ("Casey", "Antarctica/Casey", "2016-10-21T16:00:00Z", 0, 30,
             "2016-10-22T13:30:00Z"),
        ]
        for (name, identifier, date, hour, minute, expected) in cases {
            let calendar = Self.calendar(identifier)
            let day = calendar.startOfDay(for: Self.instant(date))
            XCTAssertEqual(
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                Self.instant(expected),
                name
            )
        }
    }

    /// `date(bySettingHour:...)` searches from half a second before the day's
    /// first instant, so the clock hour that ends the previous civil date can
    /// resolve onto that previous date. A rejected earlier candidate whose hour
    /// repeats resumes the search one hour on rather than a whole day on.
    func testSearchStartBeforeTheDayReachesThePreviousCivilDate() {
        let cases: [(String, String, String, Int, Int, String)] = [
            ("St. John's", "America/St_Johns", "2000-10-29T16:00:00Z", 23, 1,
             "2000-10-29T02:31:00Z"),
            ("Casey", "Antarctica/Casey", "2010-03-05T04:00:00Z", 23, 15,
             "2010-03-04T15:15:00Z"),
            ("Pyongyang", "Asia/Pyongyang", "2018-05-04T03:00:00Z", 23, 30,
             "2018-05-05T14:30:00Z"),
        ]
        for (name, identifier, date, hour, minute, expected) in cases {
            let calendar = Self.calendar(identifier)
            let day = calendar.startOfDay(for: Self.instant(date))
            XCTAssertEqual(
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                Self.instant(expected),
                name
            )
        }
    }

    func testFilterRemainsInclusiveStartExclusiveEndComposition() {
        let today = Self.events(
            begin: "2026-02-19T13:34:59Z", end: "2026-02-20T03:16:47Z"
        )
        let tomorrow = Self.events(
            begin: "2026-02-20T13:33:58Z", end: "2026-02-21T03:17:00Z"
        )
        let times = [
            "2026-02-20T03:15:59Z", "2026-02-20T03:16:00Z",
            "2026-02-20T13:32:59Z", "2026-02-20T13:33:00Z",
        ]
        let forecasts = times.map {
            HourlyForecast(
                time: Self.instant($0), cloudCover: 0, humidity: 0, windSpeed: 0,
                windDirection: 0, temperature: 0, dewPoint: 0, visibility: 0
            )
        }
        let filtered = NightForecastFilter.filterToNighttime(
            forecasts: forecasts,
            sunEventsToday: today,
            sunEventsTomorrow: tomorrow,
            for: Self.instant("2026-02-19T20:00:00Z"),
            calendar: Self.calendar("America/Los_Angeles")
        )
        XCTAssertEqual(filtered.map(\.time), [times[1], times[2]].map(Self.instant))
    }

    func testStrictTransportAndTimezonePolicy() throws {
        let valid: [String: Any] = [
            "observing_time": "2026-02-19T20:00:00Z",
            "time_zone": "America/Los_Angeles",
            "astronomical_twilight_end": "2026-02-20T03:16:47Z",
            "astronomical_twilight_begin": "2026-02-19T13:34:59Z",
            "tomorrow_astronomical_twilight_begin": NSNull(),
        ]
        let result = try NightForecastWindowContract.evaluate(valid)
        XCTAssertEqual(result["time_zone"] as? String, "America/Los_Angeles")
        XCTAssertEqual(result["start"] as? String, "2026-02-20T03:16:00Z")
        XCTAssertEqual(result["end"] as? String, "2026-02-20T13:34:00Z")

        for override in ["UTC", "GMT-0800", "US/Pacific", "Mars/Olympus_Mons"] {
            var input = valid
            input["time_zone"] = override
            XCTAssertThrowsError(try NightForecastWindowContract.evaluate(input))
        }
        var missing = valid
        missing.removeValue(forKey: "tomorrow_astronomical_twilight_begin")
        XCTAssertThrowsError(try NightForecastWindowContract.evaluate(missing))
        var unknown = valid
        unknown["forecasts"] = []
        XCTAssertThrowsError(try NightForecastWindowContract.evaluate(unknown))
    }
}
