import AstroEngine
@testable import SharedCode
import XCTest

/// Migration equivalence for three-night outlook day composition.
///
/// `LegacyThreeNightOutlookOracle` freezes the pre-migration deterministic
/// composition as a self-contained copy: the local reference day, the
/// first-hourly-forecast day indexing, the Sun/Moon array guards, the observing
/// date, the astronomical-night composition, the preceding-night-first active
/// selection, the first-slot offset derived by differencing dates, the
/// three-slot all-or-nothing rule, the empty-window and hourly-coverage
/// classification and the best-night reduction.
///
/// It deliberately calls **none** of `NightOutlookComposer`,
/// `NightOutlookContract`, `ThreeNightOutlookWidgetPayloadBuilder` or
/// `ActiveObservingNightResolver` — the whole migrated path. Only unchanged
/// primitives are used: the production calendar constructor, the `SunEvents`
/// accessors, and `TargetRecommendationContextBuilder`, which this slice did not
/// touch and which the oracle consults **solely** for a night's calculated
/// score. Every date, boundary and status on the expected side is derived here.
private enum LegacyThreeNightOutlookOracle {
    static let labels = ["Tonight", "Tomorrow", "Day After"]

    struct Night: Equatable {
        let observingDate: Date
        let astronomicalNightStart: Date?
        let astronomicalNightEnd: Date?
        let status: WidgetThreeNightOutlookNightStatus
        let score: Int?
    }

    struct Outcome: Equatable {
        let published: Bool
        let nights: [Night]
        let bestIndex: Int?
    }

    // MARK: - Pre-migration day resolution

    private struct ResolvedDay {
        let dayOffset: Int
        let observingDate: Date
        let astronomicalNightStart: Date
        let astronomicalNightEnd: Date
        let ownTwilightBegin: Date
    }

    /// Verbatim pre-migration precedence, inline as the builder used to reach it.
    private static func resolvedTimeZone(
        conditions: ViewingConditions,
        preferredTimeZone: TimeZone?
    ) -> TimeZone {
        preferredTimeZone
            ?? conditions.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
    }

    private static func day(
        conditions: ViewingConditions,
        dayOffset: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> ResolvedDay? {
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
                byAdding: .day, value: dayOffset, to: referenceDay
              ) else { return nil }

        let today = conditions.dailySunEvents[dayIndex]
        let nextIndex = dayIndex + 1
        let tomorrow = nextIndex < conditions.dailySunEvents.count
            ? conditions.dailySunEvents[nextIndex]
            : nil
        return ResolvedDay(
            dayOffset: dayOffset,
            observingDate: observingDate,
            astronomicalNightStart: today.astronomicalNightStart,
            astronomicalNightEnd: today.astronomicalNightEnd(using: tomorrow),
            ownTwilightBegin: today.astronomicalTwilightBegin
        )
    }

    // MARK: - Pre-migration hourly coverage

    private static let expectedHourlyCadence: TimeInterval = 60 * 60
    private static let cadenceTolerance: TimeInterval = 60

    private static func nominalHourlyCadence(in forecasts: [HourlyForecast]) -> TimeInterval? {
        let intervals = zip(forecasts, forecasts.dropFirst())
            .compactMap { first, second -> TimeInterval? in
                let interval = second.time.timeIntervalSince(first.time)
                return interval > 0 ? interval : nil
            }
            .sorted()
        guard !intervals.isEmpty else { return nil }
        let cadence = intervals[intervals.count / 2]
        guard abs(cadence - expectedHourlyCadence) <= cadenceTolerance else { return nil }
        return cadence
    }

    static func hasCompleteHourlyCoverage(
        start: Date,
        end: Date,
        conditions: ViewingConditions
    ) -> Bool {
        guard start < end else { return false }
        let forecasts = conditions.hourlyForecasts.sorted { $0.time < $1.time }
        guard let cadence = nominalHourlyCadence(in: forecasts) else { return false }
        let relevant = forecasts.filter {
            $0.time <= end && $0.time.addingTimeInterval(cadence) >= start
        }
        guard let first = relevant.first, let last = relevant.last,
              first.time <= start,
              last.time.addingTimeInterval(cadence) >= end else { return false }
        return zip(relevant, relevant.dropFirst()).allSatisfy {
            abs($1.time.timeIntervalSince($0.time) - cadence) <= cadenceTolerance
        }
    }

    // MARK: - Pre-migration best-night reduction

    static func bestNightIndex(
        statuses: [WidgetThreeNightOutlookNightStatus],
        scores: [Int?]
    ) -> Int? {
        let validIndices = statuses.indices.filter {
            statuses[$0] == .available && scores[$0] != nil
        }
        guard let first = validIndices.first else { return nil }
        return validIndices.dropFirst().reduce(first) { best, candidate in
            guard let bestScore = scores[best], let candidateScore = scores[candidate] else {
                return best
            }
            return candidateScore > bestScore ? candidate : best
        }
    }

    // MARK: - Pre-migration publication decision

    static func outcome(
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone?
    ) -> Outcome {
        let resolved = resolvedTimeZone(conditions: conditions, preferredTimeZone: timeZone)
        let calendar = LocationTimeZoneResolver.calendar(for: resolved)

        // The pre-migration active-night selection: preceding civil date first,
        // all three comparisons inclusive.
        var active: ResolvedDay?
        var unavailableZone = resolved
        if let previous = day(
            conditions: conditions, dayOffset: -1,
            referenceDate: referenceDate, calendar: calendar
        ), referenceDate >= previous.astronomicalNightStart,
           referenceDate <= previous.astronomicalNightEnd {
            active = previous
        } else if let current = day(
            conditions: conditions, dayOffset: 0,
            referenceDate: referenceDate, calendar: calendar
        ) {
            if calendar.isDate(current.observingDate, inSameDayAs: referenceDate),
               referenceDate <= current.ownTwilightBegin {
                // requiresActivePreviousPayload: with no existing payload the
                // builder publishes the unavailable summary in the resolved zone.
                active = nil
            } else {
                active = current
            }
        } else {
            // The `unavailable` branch does not consult the payload's own zone.
            unavailableZone = timeZone
                ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
            active = nil
        }

        guard let first = active else {
            return unavailable(referenceDate: referenceDate, timeZone: unavailableZone)
        }

        let firstOffset = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: referenceDate), to: first.observingDate
        ).day ?? 0
        let slots = (0..<labels.count).compactMap {
            day(
                conditions: conditions, dayOffset: firstOffset + $0,
                referenceDate: referenceDate, calendar: calendar
            )
        }
        guard slots.count == labels.count else {
            return unavailable(referenceDate: referenceDate, timeZone: resolved)
        }

        var statuses: [WidgetThreeNightOutlookNightStatus] = []
        var scores: [Int?] = []
        for slot in slots {
            let start = slot.astronomicalNightStart
            let end = slot.astronomicalNightEnd
            guard start < end else {
                statuses.append(.noAstronomicalNight)
                scores.append(nil)
                continue
            }
            guard hasCompleteHourlyCoverage(start: start, end: end, conditions: conditions) else {
                statuses.append(.unavailable)
                scores.append(nil)
                continue
            }
            statuses.append(.available)
            // The only fact the oracle borrows from unchanged production code.
            // `locationContext: nil` means the headline score is the night score.
            scores.append(
                TargetRecommendationContextBuilder.resolve(
                    conditions: conditions, dayOffset: slot.dayOffset,
                    referenceDate: referenceDate, timeZone: resolved
                )?.context.nightQuality.calculatedScore
            )
        }

        return Outcome(
            published: true,
            nights: slots.indices.map { index in
                Night(
                    observingDate: slots[index].observingDate,
                    astronomicalNightStart: slots[index].astronomicalNightStart,
                    astronomicalNightEnd: slots[index].astronomicalNightEnd,
                    status: statuses[index],
                    score: scores[index]
                )
            },
            bestIndex: bestNightIndex(statuses: statuses, scores: scores)
        )
    }

    private static func unavailable(referenceDate: Date, timeZone: TimeZone) -> Outcome {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let start = calendar.startOfDay(for: referenceDate)
        return Outcome(
            published: false,
            nights: (0..<labels.count).compactMap { index in
                guard let observingDate = calendar.date(
                    byAdding: .day, value: index, to: start
                ) else { return nil }
                return Night(
                    observingDate: observingDate,
                    astronomicalNightStart: nil,
                    astronomicalNightEnd: nil,
                    status: .unavailable,
                    score: nil
                )
            },
            bestIndex: nil
        )
    }
}

final class ThreeNightOutlookCompositionMigrationTests: XCTestCase {

    // MARK: - Composition sweep

    func testCompositionMatchesPreMigrationOracleAcrossTheProductionStateSpace() {
        var comparisons = 0
        var published = 0
        var seenStatuses = Set<WidgetThreeNightOutlookNightStatus>()
        var seenBestPositions = Set<Int?>()

        for shape in Shape.sweep {
            let conditions = makeConditions(shape)
            let referenceDate = shape.referenceDate
            let expected = LegacyThreeNightOutlookOracle.outcome(
                conditions: conditions,
                referenceDate: referenceDate,
                timeZone: shape.preferredTimeZone
            )
            let actual = production(
                conditions: conditions,
                referenceDate: referenceDate,
                timeZone: shape.preferredTimeZone
            )
            XCTAssertEqual(actual, expected, "\(shape)")
            comparisons += 1
            if expected.published { published += 1 }
            seenStatuses.formUnion(expected.nights.map(\.status))
            seenBestPositions.insert(expected.bestIndex)
        }

        // The sweep must actually reach the interesting production states, or
        // the equality above proves nothing.
        XCTAssertEqual(comparisons, Shape.sweep.count)
        XCTAssertGreaterThan(comparisons, 2_000)
        XCTAssertGreaterThan(published, 100)
        XCTAssertEqual(seenStatuses, [.available, .noAstronomicalNight, .unavailable])
        XCTAssertEqual(seenBestPositions, [nil, 0, 1, 2])
    }

    /// The post-migration production entry point, reduced to the same facts.
    private func production(
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone?
    ) -> LegacyThreeNightOutlookOracle.Outcome {
        let decision = ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions,
            existingSummary: nil,
            referenceDate: referenceDate,
            timeZone: timeZone,
            locationContext: nil
        )
        let summary: WidgetThreeNightOutlookSummary
        let published: Bool
        switch decision {
        case let .publish(value):
            summary = value
            published = true
        case let .unavailable(value):
            summary = value
            published = false
        case .preserveExisting:
            return LegacyThreeNightOutlookOracle.Outcome(
                published: false, nights: [], bestIndex: nil
            )
        }
        return LegacyThreeNightOutlookOracle.Outcome(
            published: published,
            nights: summary.nights.map {
                LegacyThreeNightOutlookOracle.Night(
                    observingDate: $0.observingDate,
                    astronomicalNightStart: $0.astronomicalNightStart,
                    astronomicalNightEnd: $0.astronomicalNightEnd,
                    status: $0.status,
                    score: $0.score
                )
            },
            bestIndex: summary.nights.firstIndex(where: \.isBestNight)
        )
    }

    // MARK: - Exhaustive best-night oracle

    func testBestNightSelectionMatchesPreMigrationOracleExhaustively() {
        let statuses: [WidgetThreeNightOutlookNightStatus] =
            [.available, .noAstronomicalNight, .unavailable]
        // Two equal scores make every tie position reachable; the endpoints pin
        // the clamped score domain.
        let scores: [Int?] = [nil, 0, 50, 50, 100]
        var comparisons = 0

        for firstStatus in statuses {
            for firstScore in scores {
                for secondStatus in statuses {
                    for secondScore in scores {
                        for thirdStatus in statuses {
                            for thirdScore in scores {
                                let rowStatuses = [firstStatus, secondStatus, thirdStatus]
                                let rowScores = [firstScore, secondScore, thirdScore]
                                let expected = LegacyThreeNightOutlookOracle.bestNightIndex(
                                    statuses: rowStatuses, scores: rowScores
                                )
                                let actual = ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(
                                    in: zip(rowStatuses, rowScores).enumerated().map {
                                        night(index: $0.offset, status: $0.element.0, score: $0.element.1)
                                    }
                                )
                                XCTAssertEqual(actual, expected, "\(rowStatuses) \(rowScores)")
                                comparisons += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 3_375)
    }

    func testBestNightSelectionHandlesShorterAndEmptyRowSets() {
        XCTAssertNil(ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: []))
        XCTAssertEqual(
            ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: [
                night(index: 0, status: .available, score: 10)
            ]),
            0
        )
        XCTAssertEqual(
            ThreeNightOutlookWidgetPayloadBuilder.bestNightIndex(in: [
                night(index: 0, status: .available, score: 10),
                night(index: 1, status: .available, score: 10)
            ]),
            0
        )
    }

    // MARK: - Hourly coverage sweep

    func testHourlyCoverageMatchesPreMigrationOracle() {
        var comparisons = 0
        var complete = 0
        for shape in Shape.coverageSweep {
            let conditions = makeConditions(shape)
            for dayOffset in 0..<3 {
                guard let resolution = TargetRecommendationContextBuilder.resolve(
                    conditions: conditions,
                    dayOffset: dayOffset,
                    referenceDate: shape.referenceDate,
                    timeZone: shape.timeZone
                ) else { continue }
                let expected = LegacyThreeNightOutlookOracle.hasCompleteHourlyCoverage(
                    start: resolution.context.astronomicalNightStart,
                    end: resolution.context.astronomicalNightEnd,
                    conditions: conditions
                )
                let actual = ThreeNightOutlookWidgetPayloadBuilder.hasCompleteHourlyCoverage(
                    for: resolution, conditions: conditions
                )
                XCTAssertEqual(actual, expected, "\(shape) offset \(dayOffset)")
                comparisons += 1
                if expected { complete += 1 }
            }
        }
        XCTAssertGreaterThan(comparisons, 50)
        XCTAssertGreaterThan(complete, 10)
        XCTAssertLessThan(complete, comparisons)
    }

    // MARK: - Case space

    /// One generated production payload plus the instant it is asked about.
    struct Shape: CustomStringConvertible {
        enum NightShape: CaseIterable {
            /// Ordinary 22:00 → 04:00 nights on every represented day.
            case normal
            /// The second represented day's evening twilight lands an hour
            /// **after** the following morning's — an inverted window.
            case invertedSecondDay
            /// The second represented day's window is exactly empty.
            case emptySecondDay
        }

        enum Perturbation: CaseIterable {
            case unperturbed
            /// One hour removed from the middle of the stream.
            case missingHour
            /// One timestamp repeated, which breaks the cadence continuity.
            case duplicateHour
            /// Half-hourly rows, which is not the nominal cadence.
            case halfHourly
        }

        let zoneIdentifier: String
        let baseDay: DateComponents
        let referenceHour: Int
        let dailyCount: Int
        let hourlyDays: Int
        let nightShape: NightShape
        let perturbation: Perturbation
        /// Whether the caller passes an explicit zone, which is the branch that
        /// makes the unavailable-summary zone precedence observable.
        let passesPreferredTimeZone: Bool

        /// Four per-day cloud profiles; the flat one keeps the all-tie case in
        /// the sweep, the others separate the three nights' scores.
        static let cloudProfiles: [[Int]] = [
            [20, 20, 20, 20],
            [10, 45, 85, 30],
            [85, 45, 10, 60],
            [45, 10, 70, 90]
        ]

        var profileIndex: Int {
            (dailyCount + hourlyDays + referenceHour) % Shape.cloudProfiles.count
        }

        var timeZone: TimeZone { TimeZone(identifier: zoneIdentifier)! }
        var preferredTimeZone: TimeZone? { passesPreferredTimeZone ? timeZone : nil }

        var referenceDate: Date {
            var components = baseDay
            components.hour = referenceHour
            return calendar.date(from: components)!
        }

        var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar
        }

        var description: String {
            "\(zoneIdentifier) \(baseDay.year!)-\(baseDay.month!)-\(baseDay.day!)"
                + " h\(referenceHour) daily\(dailyCount) hourly\(hourlyDays)"
                + " \(nightShape) \(perturbation) tz:\(passesPreferredTimeZone)"
        }

        /// Three zones whose local-midnight arithmetic differs: an ordinary DST
        /// zone, a zone whose transition is at local midnight, and a zone with a
        /// repeated local midnight. All three are pinned by the observing-night
        /// procedure.
        static let zones: [(String, DateComponents)] = [
            ("America/Los_Angeles", DateComponents(year: 2026, month: 7, day: 26)),
            ("America/Santiago", DateComponents(year: 2026, month: 9, day: 6)),
            ("America/Havana", DateComponents(year: 2026, month: 11, day: 1))
        ]

        static let sweep: [Shape] = {
            var shapes: [Shape] = []
            for (identifier, baseDay) in zones {
                for referenceHour in [0, 1, 4, 5, 6, 22, 23] {
                    for dailyCount in [0, 2, 3, 4, 5] {
                        for hourlyDays in [0, 3, 4, 5] {
                            for nightShape in NightShape.allCases {
                                for perturbation in [
                                    Perturbation.unperturbed, .missingHour, .duplicateHour
                                ] {
                                    shapes.append(Shape(
                                        zoneIdentifier: identifier,
                                        baseDay: baseDay,
                                        referenceHour: referenceHour,
                                        dailyCount: dailyCount,
                                        hourlyDays: hourlyDays,
                                        nightShape: nightShape,
                                        perturbation: perturbation,
                                        passesPreferredTimeZone: dailyCount % 2 == 0
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            return shapes
        }()

        static let coverageSweep: [Shape] = {
            var shapes: [Shape] = []
            for hourlyDays in [0, 1, 3, 4, 5, 6] {
                for perturbation in Perturbation.allCases {
                    shapes.append(Shape(
                        zoneIdentifier: "America/Los_Angeles",
                        baseDay: DateComponents(year: 2026, month: 7, day: 26),
                        referenceHour: 6,
                        dailyCount: 6,
                        hourlyDays: hourlyDays,
                        nightShape: .normal,
                        perturbation: perturbation,
                        passesPreferredTimeZone: true
                    ))
                }
            }
            return shapes
        }()
    }

    /// Builds a payload for one shape. The daily arrays start one civil day
    /// before the reference day so the preceding-night branch is reachable.
    private func makeConditions(_ shape: Shape) -> ViewingConditions {
        let calendar = shape.calendar
        let referenceDay = calendar.startOfDay(for: shape.referenceDate)
        let firstDay = calendar.date(byAdding: .day, value: -1, to: referenceDay)!

        func moment(dayOffset: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay)!
            return calendar.date(byAdding: .hour, value: hour, to: day)!
        }

        let sunEvents = (0..<shape.dailyCount).map { offset -> SunEvents in
            var eveningHour = 22
            switch shape.nightShape {
            case .normal:
                break
            case .invertedSecondDay where offset == 1:
                // One hour after the following morning's 04:00 twilight begin.
                eveningHour = 24 + 5
            case .emptySecondDay where offset == 1:
                eveningHour = 24 + 4
            default:
                break
            }
            return SunEvents(
                sunrise: moment(dayOffset: offset, hour: 6),
                sunset: moment(dayOffset: offset, hour: 20),
                civilTwilightBegin: moment(dayOffset: offset, hour: 5),
                civilTwilightEnd: moment(dayOffset: offset, hour: 21),
                nauticalTwilightBegin: moment(dayOffset: offset, hour: 4),
                nauticalTwilightEnd: moment(dayOffset: offset, hour: 21),
                astronomicalTwilightBegin: moment(dayOffset: offset, hour: 4),
                astronomicalTwilightEnd: moment(dayOffset: offset, hour: eveningHour)
            )
        }

        let step: TimeInterval = shape.perturbation == .halfHourly ? 1_800 : 3_600
        let rowCount = Int(Double(shape.hourlyDays) * 24 * (3_600 / step))
        var times = (0..<rowCount).map {
            firstDay.addingTimeInterval(Double($0) * step)
        }
        switch shape.perturbation {
        case .missingHour where times.count > 30:
            times.remove(at: 30)
        case .duplicateHour where times.count > 30:
            times.insert(times[30], at: 30)
        case .unperturbed, .halfHourly, .missingHour, .duplicateHour:
            break
        }
        // Cloud cover varies by local day so the three nights can score
        // differently; a uniform sky would tie every outlook and never make the
        // second or third row the best night.
        let profile = Shape.cloudProfiles[shape.profileIndex]
        let forecasts = times.map { time -> HourlyForecast in
            let dayNumber = Int(time.timeIntervalSince(firstDay) / 86_400)
            return HourlyForecast(
                time: time,
                cloudCover: profile[((dayNumber % profile.count) + profile.count) % profile.count],
                humidity: 45, windSpeed: 2,
                windDirection: 180, temperature: 12, dewPoint: 5, visibility: 20_000
            )
        }

        return ViewingConditions(
            fetchedAt: shape.referenceDate,
            location: CachedLocation(name: "Home", latitude: 45.5, longitude: -122.7),
            hourlyForecasts: forecasts,
            dailySunEvents: sunEvents,
            dailyMoonInfo: (0..<shape.dailyCount).map {
                MoonInfo(
                    phase: 0.2, phaseName: "Waxing", altitude: 10,
                    illumination: 20 + $0, emoji: "🌒"
                )
            },
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: shape.zoneIdentifier
        )
    }

    private func night(
        index: Int,
        status: WidgetThreeNightOutlookNightStatus,
        score: Int?
    ) -> WidgetThreeNightOutlookNight {
        WidgetThreeNightOutlookNight(
            id: "\(index)", displayLabel: "\(index)",
            observingDate: Date(timeIntervalSinceReferenceDate: Double(index) * 86_400),
            score: score, verdict: "", scoreTone: nil,
            astronomicalNightStart: nil, astronomicalNightEnd: nil, bestWindow: nil,
            statusText: "", status: status, isBestNight: false
        )
    }
}
