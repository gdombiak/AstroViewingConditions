import AstroEngine
@testable import SharedCode
import XCTest

/// Migration equivalence for the active observing-night slice.
///
/// `LegacyActiveObservingNightOracle` freezes the pre-migration decision as a
/// self-contained copy. It reproduces the old inline timezone precedence, the
/// local reference day, the first-hourly-forecast day indexing, the Sun/Moon
/// array guards, the observing date and the astronomical-night composition —
/// exactly the pieces the compared facts depend on.
///
/// It deliberately calls **none** of `ObservingNightSelector`,
/// `ObservingNightContract`, `LocationTimeZoneResolver.authoritative` or
/// `TargetRecommendationContextBuilder`. The builder is excluded because this
/// slice changed it to call the new `authoritative(...)` helper, so routing the
/// oracle through it would let one timezone-precedence bug corrupt both sides at
/// once. Only unchanged low-level primitives are used: the production calendar
/// constructor, `TimeZone(identifier:)`, `approximate(longitude:)` and the
/// existing `SunEvents` accessors.
///
/// It does not reproduce `NightQualityAnalyzer`, forecast slicing or
/// `TargetRecommendationContext`, because none of those reach the compared
/// facts: state, observing date, timezone identifier and both boundaries.
private enum LegacyActiveObservingNightOracle {
    enum Outcome: Equatable {
        case resolved(observingDate: Date, timeZone: String, nightStart: Date, nightEnd: Date)
        case requiresActivePreviousPayload(timeZone: String)
        case unavailable
    }

    /// The pre-migration `TargetRecommendationContextBuilder` day resolution,
    /// reduced to the facts the oracle compares.
    private struct Night {
        let observingDate: Date
        let sunEventsToday: SunEvents
        let astronomicalNightStart: Date
        let astronomicalNightEnd: Date
    }

    /// Verbatim pre-migration precedence, inline as it used to be written.
    private static func resolvedTimeZone(
        conditions: ViewingConditions,
        preferredTimeZone: TimeZone?
    ) -> TimeZone {
        preferredTimeZone
            ?? conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
    }

    private static func night(
        conditions: ViewingConditions,
        dayOffset: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> Night? {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let dayIndex: Int
        if let firstForecastTime = conditions.hourlyForecasts.first?.time {
            let firstForecastDay = calendar.startOfDay(for: firstForecastTime)
            let elapsedDays = calendar.dateComponents(
                [.day],
                from: firstForecastDay,
                to: referenceDay
            ).day ?? 0
            dayIndex = elapsedDays + dayOffset
        } else {
            dayIndex = dayOffset
        }

        guard dayIndex >= 0,
              dayIndex < conditions.dailySunEvents.count,
              dayIndex < conditions.dailyMoonInfo.count,
              let observingDate = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: referenceDay
              ) else {
            return nil
        }

        let sunEventsToday = conditions.dailySunEvents[dayIndex]
        let nextIndex = dayIndex + 1
        let sunEventsTomorrow = nextIndex < conditions.dailySunEvents.count
            ? conditions.dailySunEvents[nextIndex]
            : nil
        return Night(
            observingDate: observingDate,
            sunEventsToday: sunEventsToday,
            astronomicalNightStart: sunEventsToday.astronomicalNightStart,
            astronomicalNightEnd: sunEventsToday.astronomicalNightEnd(using: sunEventsTomorrow)
        )
    }

    static func resolve(
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone?
    ) -> Outcome {
        let resolvedZone = resolvedTimeZone(conditions: conditions, preferredTimeZone: timeZone)
        let calendar = LocationTimeZoneResolver.calendar(for: resolvedZone)

        if let previous = night(
            conditions: conditions, dayOffset: -1,
            referenceDate: referenceDate, calendar: calendar
        ), referenceDate >= previous.astronomicalNightStart,
           referenceDate <= previous.astronomicalNightEnd {
            return outcome(previous, timeZone: resolvedZone)
        }

        guard let current = night(
            conditions: conditions, dayOffset: 0,
            referenceDate: referenceDate, calendar: calendar
        ) else { return .unavailable }

        if calendar.isDate(current.observingDate, inSameDayAs: referenceDate),
           referenceDate <= current.sunEventsToday.astronomicalTwilightBegin {
            return .requiresActivePreviousPayload(timeZone: resolvedZone.identifier)
        }
        return outcome(current, timeZone: resolvedZone)
    }

    private static func outcome(_ night: Night, timeZone: TimeZone) -> Outcome {
        .resolved(
            observingDate: night.observingDate,
            timeZone: timeZone.identifier,
            nightStart: night.astronomicalNightStart,
            nightEnd: night.astronomicalNightEnd
        )
    }
}

private extension ActiveObservingNightResolution {
    var comparable: LegacyActiveObservingNightOracle.Outcome {
        switch self {
        case let .resolved(resolution):
            return .resolved(
                observingDate: resolution.observingDate,
                timeZone: resolution.timeZone.identifier,
                nightStart: resolution.context.astronomicalNightStart,
                nightEnd: resolution.context.astronomicalNightEnd
            )
        case let .requiresActivePreviousPayload(zone):
            return .requiresActivePreviousPayload(timeZone: zone.identifier)
        case .unavailable:
            return .unavailable
        }
    }
}

final class ActiveObservingNightMigrationTests: XCTestCase {

    // MARK: - Migration equivalence

    /// Every scenario × reference instant must produce the pre-migration state,
    /// observing date, zone and both authoritative boundaries.
    func testResolverMatchesLegacyOracleAcrossScenarios() {
        var comparisons = 0
        var seenStates = Set<String>()

        for scenario in Self.scenarios {
            for reference in scenario.references {
                let label = "\(scenario.name) @ \(Self.text(reference))"
                let actual = ActiveObservingNightResolver.resolve(
                    conditions: scenario.conditions,
                    referenceDate: reference,
                    timeZone: scenario.preferredTimeZone
                )
                let legacy = LegacyActiveObservingNightOracle.resolve(
                    conditions: scenario.conditions,
                    referenceDate: reference,
                    timeZone: scenario.preferredTimeZone
                )
                comparisons += 1
                seenStates.insert(Self.stateName(legacy))
                XCTAssertEqual(actual.comparable, legacy, label)
            }
        }

        XCTAssertEqual(comparisons, 700, "migration comparison count")
        XCTAssertEqual(
            seenStates,
            ["resolved", "requiresActivePreviousPayload", "unavailable"],
            "every pre-migration state must be exercised"
        )
    }

    /// The three states are separate product facts; widget and Watch callers
    /// branch on them differently, so they must not collapse.
    func testStatesRemainDistinguishable() {
        let scenario = Self.pacific()
        let evening = ActiveObservingNightResolver.resolve(
            conditions: scenario.conditions,
            referenceDate: Self.instant("2026-02-19T05:00:00Z"),
            timeZone: nil
        )
        guard case .resolved = evening else { return XCTFail("expected resolved") }

        // Local 04:00 on the first represented day: before its own 05:05
        // astronomical twilight begin, with no preceding row in this payload.
        let beforeDawn = ActiveObservingNightResolver.resolve(
            conditions: scenario.conditions,
            referenceDate: Self.instant("2026-02-17T12:00:00Z"),
            timeZone: nil
        )
        guard case let .requiresActivePreviousPayload(zone) = beforeDawn else {
            return XCTFail("expected requiresActivePreviousPayload")
        }
        XCTAssertEqual(zone.identifier, "America/Los_Angeles")

        let past = ActiveObservingNightResolver.resolve(
            conditions: scenario.conditions,
            referenceDate: Self.instant("2026-02-25T05:00:00Z"),
            timeZone: nil
        )
        guard case .unavailable = past else { return XCTFail("expected unavailable") }
    }

    /// The preceding civil date is retained after local midnight, which is the
    /// entire point of this authority.
    func testPrecedingCivilDateIsRetainedAfterMidnight() {
        let scenario = Self.pacific()
        let calendar = LocationTimeZoneResolver.calendar(for: scenario.zone)
        guard case let .resolved(resolution) = ActiveObservingNightResolver.resolve(
            conditions: scenario.conditions,
            referenceDate: Self.instant("2026-02-19T11:00:00Z"),   // local 03:00
            timeZone: nil
        ) else { return XCTFail("expected resolved") }
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: resolution.observingDate).day,
            18
        )
    }

    /// The host keeps timezone acquisition: an explicit zone still wins over the
    /// payload identifier, and the longitude approximation is still used when
    /// neither is available. Neither path reaches the portable transport.
    func testTimeZonePrecedenceRemainsHostOwned() {
        let scenario = Self.pacific()
        let override = TimeZone(identifier: "America/New_York")!
        guard case let .resolved(resolution) = ActiveObservingNightResolver.resolve(
            conditions: scenario.conditions,
            referenceDate: Self.instant("2026-02-19T05:00:00Z"),
            timeZone: override
        ) else { return XCTFail("expected resolved") }
        XCTAssertEqual(resolution.timeZone.identifier, override.identifier)

        let unidentified = Self.conditions(
            zone: scenario.zone, firstDay: "2026-02-17", dayCount: 4,
            timeZoneIdentifier: nil, longitude: -122.7
        )
        let approximated = LocationTimeZoneResolver.approximate(longitude: -122.7)
        guard case let .resolved(fallback) = ActiveObservingNightResolver.resolve(
            conditions: unidentified,
            referenceDate: Self.instant("2026-02-19T05:00:00Z"),
            timeZone: nil
        ) else { return XCTFail("expected resolved") }
        XCTAssertEqual(fallback.timeZone.identifier, approximated.identifier)
        // The longitude approximation has no IANA identity, which is why it is
        // host acquisition and cannot cross the portable transport.
        XCTAssertFalse(approximated.identifier.contains("/"), approximated.identifier)

        // An *invalid* payload identifier is not the same as a missing one:
        // production's `flatMap(TimeZone.init(identifier:))` yields nil and falls
        // through to the longitude approximation. Pinned independently because
        // the legacy oracle reproduces that `flatMap` itself.
        let malformed = Self.conditions(
            zone: scenario.zone, firstDay: "2026-02-17", dayCount: 4,
            timeZoneIdentifier: "Not/AZone", longitude: -122.7
        )
        let reference = Self.instant("2026-02-19T05:00:00Z")
        guard case let .resolved(malformedResolution) = ActiveObservingNightResolver.resolve(
            conditions: malformed, referenceDate: reference, timeZone: nil
        ) else { return XCTFail("expected resolved") }
        XCTAssertNil(TimeZone(identifier: "Not/AZone"))
        XCTAssertEqual(malformedResolution.timeZone.identifier, approximated.identifier)
        XCTAssertEqual(
            LegacyActiveObservingNightOracle.resolve(
                conditions: malformed, referenceDate: reference, timeZone: nil
            ),
            ActiveObservingNightResolver.resolve(
                conditions: malformed, referenceDate: reference, timeZone: nil
            ).comparable
        )
    }

    // MARK: - Scenarios

    private struct Scenario {
        let name: String
        let zone: TimeZone
        let conditions: ViewingConditions
        let preferredTimeZone: TimeZone?
        let references: [Date]
    }

    private static func pacific() -> Scenario {
        Scenario(
            name: "pacific",
            zone: TimeZone(identifier: "America/Los_Angeles")!,
            conditions: conditions(
                zone: TimeZone(identifier: "America/Los_Angeles")!,
                firstDay: "2026-02-17", dayCount: 4,
                timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7
            ),
            preferredTimeZone: nil,
            references: sweep(from: "2026-02-17T00:00:00Z", days: 6, stepHours: 1)
        )
    }

    private static let scenarios: [Scenario] = {
        let pacificZone = TimeZone(identifier: "America/Los_Angeles")!
        let santiagoZone = TimeZone(identifier: "America/Santiago")!
        let lordHoweZone = TimeZone(identifier: "Australia/Lord_Howe")!
        let kathmanduZone = TimeZone(identifier: "Asia/Kathmandu")!

        return [
            pacific(),
            Scenario(
                name: "pacific-explicit-override",
                zone: TimeZone(identifier: "America/New_York")!,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-02-17", dayCount: 4,
                    timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7
                ),
                preferredTimeZone: TimeZone(identifier: "America/New_York")!,
                references: sweep(from: "2026-02-17T00:00:00Z", days: 5, stepHours: 3)
            ),
            Scenario(
                name: "pacific-no-identifier-longitude-fallback",
                zone: pacificZone,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-02-17", dayCount: 4,
                    timeZoneIdentifier: nil, longitude: -122.7
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-02-17T00:00:00Z", days: 5, stepHours: 3)
            ),
            Scenario(
                name: "pacific-empty-hourly",
                zone: pacificZone,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-02-17", dayCount: 4,
                    timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7,
                    includesForecasts: false
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-02-17T00:00:00Z", days: 5, stepHours: 3)
            ),
            Scenario(
                name: "pacific-single-day",
                zone: pacificZone,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-02-17", dayCount: 1,
                    timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-02-17T00:00:00Z", days: 3, stepHours: 2)
            ),
            Scenario(
                name: "pacific-short-moon-array",
                zone: pacificZone,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-02-17", dayCount: 4,
                    timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7,
                    moonDayCount: 2
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-02-17T00:00:00Z", days: 5, stepHours: 3)
            ),
            Scenario(
                name: "pacific-forecast-starts-late",
                zone: pacificZone,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-02-21", dayCount: 4,
                    timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-02-17T00:00:00Z", days: 4, stepHours: 4)
            ),
            Scenario(
                name: "dst-spring-forward",
                zone: pacificZone,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-03-06", dayCount: 5,
                    timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-03-07T00:00:00Z", days: 3, stepHours: 1)
            ),
            Scenario(
                name: "dst-fall-back",
                zone: pacificZone,
                conditions: conditions(
                    zone: pacificZone, firstDay: "2026-10-30", dayCount: 5,
                    timeZoneIdentifier: "America/Los_Angeles", longitude: -122.7
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-10-31T00:00:00Z", days: 3, stepHours: 1)
            ),
            Scenario(
                name: "dst-midnight-transition-santiago",
                zone: santiagoZone,
                conditions: conditions(
                    zone: santiagoZone, firstDay: "2026-09-04", dayCount: 5,
                    timeZoneIdentifier: "America/Santiago", longitude: -70.6
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-09-05T00:00:00Z", days: 3, stepHours: 1)
            ),
            Scenario(
                name: "half-hour-dst-lord-howe",
                zone: lordHoweZone,
                conditions: conditions(
                    zone: lordHoweZone, firstDay: "2026-10-02", dayCount: 5,
                    timeZoneIdentifier: "Australia/Lord_Howe", longitude: 159.08
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-10-03T00:00:00Z", days: 3, stepHours: 1)
            ),
            Scenario(
                name: "forty-five-minute-offset-kathmandu",
                zone: kathmanduZone,
                conditions: conditions(
                    zone: kathmanduZone, firstDay: "2026-04-09", dayCount: 4,
                    timeZoneIdentifier: "Asia/Kathmandu", longitude: 85.3
                ),
                preferredTimeZone: nil,
                references: sweep(from: "2026-04-09T00:00:00Z", days: 4, stepHours: 2)
            ),
        ]
    }()

    // MARK: - Builders

    /// Twilight instants are built from local wall times in `zone`, so the
    /// scenarios keep DST-realistic boundaries without depending on live
    /// astronomy.
    private static func conditions(
        zone: TimeZone,
        firstDay: String,
        dayCount: Int,
        timeZoneIdentifier: String?,
        longitude: Double,
        includesForecasts: Bool = true,
        moonDayCount: Int? = nil
    ) -> ViewingConditions {
        let calendar = LocationTimeZoneResolver.calendar(for: zone)
        let start = localMidnight(firstDay, zone: zone)
        let sunEvents = (0..<dayCount).map { offset -> SunEvents in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            func at(_ hour: Int, _ minute: Int, dayShift: Int = 0) -> Date {
                let shifted = calendar.date(byAdding: .day, value: dayShift, to: day)!
                return calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: shifted
                )!
            }
            return SunEvents(
                sunrise: at(6, 45), sunset: at(18, 5),
                civilTwilightBegin: at(6, 15), civilTwilightEnd: at(18, 35),
                nauticalTwilightBegin: at(5, 40), nauticalTwilightEnd: at(19, 10),
                astronomicalTwilightBegin: at(5, 5), astronomicalTwilightEnd: at(19, 45)
            )
        }
        let forecasts = includesForecasts ? (0..<(dayCount * 24)).map { offset in
            HourlyForecast(
                time: start.addingTimeInterval(TimeInterval(offset) * 3600),
                cloudCover: 20, humidity: 45, windSpeed: 2, windDirection: 180,
                temperature: 12, dewPoint: 5, visibility: 20_000
            )
        } : []
        return ViewingConditions(
            fetchedAt: start,
            location: CachedLocation(name: "Site", latitude: 40, longitude: longitude),
            hourlyForecasts: forecasts,
            dailySunEvents: sunEvents,
            dailyMoonInfo: (0..<(moonDayCount ?? dayCount)).map { _ in
                MoonInfo(phase: 0.2, phaseName: "Waxing", altitude: 10,
                         illumination: 20, emoji: "🌒")
            },
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private static func localMidnight(_ day: String, zone: TimeZone) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = LocationTimeZoneResolver.calendar(for: zone)
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return LocationTimeZoneResolver.calendar(for: zone)
            .startOfDay(for: formatter.date(from: day)!)
    }

    private static func sweep(from: String, days: Int, stepHours: Int) -> [Date] {
        let start = instant(from)
        let steps = (days * 24) / stepHours
        return (0..<steps).map {
            start.addingTimeInterval(TimeInterval($0 * stepHours) * 3600)
        }
    }

    private static func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)!
    }

    private static func text(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func stateName(_ outcome: LegacyActiveObservingNightOracle.Outcome) -> String {
        switch outcome {
        case .resolved: return "resolved"
        case .requiresActivePreviousPayload: return "requiresActivePreviousPayload"
        case .unavailable: return "unavailable"
        }
    }
}
