import Foundation

/// Why a composed outlook night can or cannot carry a score.
///
/// The three cases are deliberately distinct: `noAstronomicalNight` is an
/// astronomical fact about the night itself, while `unavailable` is a fact
/// about the hourly stream that was supplied for it.
public enum NightOutlookNightStatus: String, Sendable, Equatable {
    case available
    case noAstronomicalNight = "no_astronomical_night"
    case unavailable
}

/// One composed slot of the outlook.
///
/// `slotIndex` is the position the host renders (0 is the active observing
/// night). `dayOffset` is that slot's offset from the local reference day, so
/// it is `-1`, `0`, `1` or `2` for a resolved outlook and `0`, `1`, `2` for the
/// fallback rows a host publishes when nothing can be composed.
public struct NightOutlookNight: Sendable, Equatable {
    public let slotIndex: Int
    public let dayOffset: Int
    /// Index in the caller's daily Sun/Moon arrays, or `nil` on a fallback row
    /// that selected no day at all.
    public let dayIndex: Int?
    /// First moment of the observing day in the resolved zone.
    public let observingDayStart: Date
    /// The observing day as a local civil date, `YYYY-MM-DD` in the resolved zone.
    public let observingLocalDate: String
    /// Boundaries as `observing_night.resolve_active` defines them. Both are
    /// reported for every resolved slot, including a `noAstronomicalNight` slot
    /// whose window is empty or inverted, and both are `nil` on a fallback row.
    public let astronomicalNightStart: Date?
    public let astronomicalNightEnd: Date?
    public let status: NightOutlookNightStatus

    public init(
        slotIndex: Int,
        dayOffset: Int,
        dayIndex: Int?,
        observingDayStart: Date,
        observingLocalDate: String,
        astronomicalNightStart: Date?,
        astronomicalNightEnd: Date?,
        status: NightOutlookNightStatus
    ) {
        self.slotIndex = slotIndex
        self.dayOffset = dayOffset
        self.dayIndex = dayIndex
        self.observingDayStart = observingDayStart
        self.observingLocalDate = observingLocalDate
        self.astronomicalNightStart = astronomicalNightStart
        self.astronomicalNightEnd = astronomicalNightEnd
        self.status = status
    }
}

/// Whether the outlook composed at all, mirroring the three observing-night
/// states rather than collapsing them.
public enum NightOutlookState: String, Sendable, Equatable {
    case resolved
    case requiresActivePreviousPayload = "requires_active_previous_payload"
    case unavailable
}

public struct NightOutlook: Sendable, Equatable {
    public let state: NightOutlookState
    /// Three slots whenever the local reference day and the two days after it
    /// can be expressed in the resolved zone, which is every real payload.
    public let nights: [NightOutlookNight]

    public init(state: NightOutlookState, nights: [NightOutlookNight]) {
        self.state = state
        self.nights = nights
    }
}

/// Composes the three consecutive observing nights a host shows as an outlook,
/// and classifies each one's semantic availability.
///
/// Normative procedure: contracts/procedures/night-outlook.md. This is the
/// portable form of the production three-night day composition. It resolves no
/// timezone, fetches nothing and scores nothing: the active-night decision and
/// every day-arithmetic rule come from ``ObservingNightSelector``
/// (`observing_night.resolve_active`), which this type reuses rather than
/// reimplements. Scores, best windows, labels, verdicts, tone and every cache
/// or persistence concern stay with the host.
public enum NightOutlookComposer {
    public static let capabilityID = "observing_night.compose_outlook"

    /// The outlook is exactly three nights; production has no other length.
    public static let nightCount = 3

    /// Composes the outlook for a reference instant.
    ///
    /// - Parameters:
    ///   - referenceDate: the instant being asked about.
    ///   - timeZone: the already-resolved location zone. Acquisition and the
    ///     production precedence chain stay with the host.
    ///   - forecastStartTime: the first hourly-forecast timestamp, or `nil` when
    ///     the payload carries no hourly forecasts.
    ///   - dailySunEvents: one row per represented day, aligned with the
    ///     forecast's first day.
    ///   - dailyMoonCount: the number of daily Moon rows in the same payload.
    ///   - hourlyTimes: every hourly-forecast timestamp in the payload. Only the
    ///     timestamps participate; the weather values do not.
    public static func compose(
        referenceDate: Date,
        timeZone: TimeZone,
        forecastStartTime: Date?,
        dailySunEvents: [ObservingNightSelector.DailySunEvents],
        dailyMoonCount: Int,
        hourlyTimes: [Date]
    ) -> NightOutlook {
        let selection = ObservingNightSelector.select(
            referenceDate: referenceDate,
            timeZone: timeZone,
            forecastStartTime: forecastStartTime,
            dailySunEvents: dailySunEvents,
            dailyMoonCount: dailyMoonCount
        )
        guard case let .selected(active) = selection else {
            let state: NightOutlookState = selection == .requiresActivePreviousPayload
                ? .requiresActivePreviousPayload
                : .unavailable
            return NightOutlook(
                state: state,
                nights: fallbackNights(referenceDate: referenceDate, timeZone: timeZone)
            )
        }

        // The first slot is the active observing night; the other two are the
        // next two local civil days. Production derives the same first offset by
        // differencing the reference day against the resolved observing day,
        // which is the exact inverse of the day shift that produced it.
        let resolved = (0..<nightCount).compactMap { slot in
            ObservingNightSelector.night(
                dayOffset: active.dayOffset + slot,
                referenceDate: referenceDate,
                timeZone: timeZone,
                forecastStartTime: forecastStartTime,
                dailySunEvents: dailySunEvents,
                dailyMoonCount: dailyMoonCount
            )
        }
        guard resolved.count == nightCount else {
            // All-or-nothing: production discards a partially composable outlook
            // and publishes the fallback rows instead.
            return NightOutlook(
                state: .unavailable,
                nights: fallbackNights(referenceDate: referenceDate, timeZone: timeZone)
            )
        }

        let sortedHourlyTimes = hourlyTimes.sorted()
        let nights = resolved.enumerated().map { slot, night in
            NightOutlookNight(
                slotIndex: slot,
                dayOffset: night.dayOffset,
                dayIndex: night.dayIndex,
                observingDayStart: night.observingDayStart,
                observingLocalDate: night.observingLocalDate,
                astronomicalNightStart: night.astronomicalNightStart,
                astronomicalNightEnd: night.astronomicalNightEnd,
                status: status(
                    astronomicalNightStart: night.astronomicalNightStart,
                    astronomicalNightEnd: night.astronomicalNightEnd,
                    sortedHourlyTimes: sortedHourlyTimes
                )
            )
        }
        return NightOutlook(state: .resolved, nights: nights)
    }

    /// The candidate facts best-night selection reads, and nothing else.
    public struct BestNightCandidate: Sendable, Equatable {
        public let status: NightOutlookNightStatus
        public let score: Int?

        public init(status: NightOutlookNightStatus, score: Int?) {
            self.status = status
            self.score = score
        }
    }

    /// Picks the outlook's best night, or `nil` when no row is eligible.
    ///
    /// Only an `available` row that carries a score participates. The highest
    /// score wins and a tie keeps the **earliest** eligible row, because
    /// production replaces the incumbent only on a strictly greater score. The
    /// supplied order is the semantics; nothing is sorted.
    public static func selectBestNight(_ candidates: [BestNightCandidate]) -> Int? {
        let eligible = candidates.indices.filter {
            candidates[$0].status == .available && candidates[$0].score != nil
        }
        guard let first = eligible.first else { return nil }
        return eligible.dropFirst().reduce(first) { best, candidate in
            guard let bestScore = candidates[best].score,
                  let candidateScore = candidates[candidate].score else { return best }
            return candidateScore > bestScore ? candidate : best
        }
    }

    // MARK: - Hourly coverage

    /// Whether the hourly stream continuously covers the whole astronomical
    /// night.
    ///
    /// Hourly timestamps represent the start of their interval, so an interval
    /// may contain a non-hour-aligned boundary. The nominal cadence is the
    /// median positive step across the whole stream and must itself be an hour
    /// within the tolerance; the covering rows must start at or before the night
    /// start, reach past the night end, and step by that cadence throughout. A
    /// duplicate, backwards or missing row therefore breaks coverage.
    public static func hasCompleteHourlyCoverage(
        astronomicalNightStart start: Date,
        astronomicalNightEnd end: Date,
        hourlyTimes: [Date]
    ) -> Bool {
        hasCompleteHourlyCoverage(
            astronomicalNightStart: start,
            astronomicalNightEnd: end,
            sortedHourlyTimes: hourlyTimes.sorted()
        )
    }

    static let expectedHourlyCadence: TimeInterval = 60 * 60
    static let cadenceTolerance: TimeInterval = 60

    private static func status(
        astronomicalNightStart start: Date?,
        astronomicalNightEnd end: Date?,
        sortedHourlyTimes: [Date]
    ) -> NightOutlookNightStatus {
        guard let start, let end, start < end else { return .noAstronomicalNight }
        return hasCompleteHourlyCoverage(
            astronomicalNightStart: start,
            astronomicalNightEnd: end,
            sortedHourlyTimes: sortedHourlyTimes
        ) ? .available : .unavailable
    }

    private static func hasCompleteHourlyCoverage(
        astronomicalNightStart start: Date,
        astronomicalNightEnd end: Date,
        sortedHourlyTimes: [Date]
    ) -> Bool {
        guard start < end else { return false }
        guard let cadence = nominalHourlyCadence(in: sortedHourlyTimes) else { return false }
        let relevant = sortedHourlyTimes.filter {
            $0 <= end && $0.addingTimeInterval(cadence) >= start
        }
        guard let first = relevant.first, let last = relevant.last,
              first <= start,
              last.addingTimeInterval(cadence) >= end else { return false }
        return zip(relevant, relevant.dropFirst()).allSatisfy {
            abs($1.timeIntervalSince($0) - cadence) <= cadenceTolerance
        }
    }

    /// The median strictly positive step, accepted only when it is an hour
    /// within the tolerance. Zero and negative steps are excluded from the
    /// estimate but still break the continuity check above.
    private static func nominalHourlyCadence(in sortedHourlyTimes: [Date]) -> TimeInterval? {
        let intervals = zip(sortedHourlyTimes, sortedHourlyTimes.dropFirst())
            .compactMap { first, second -> TimeInterval? in
                let interval = second.timeIntervalSince(first)
                return interval > 0 ? interval : nil
            }
            .sorted()
        guard !intervals.isEmpty else { return nil }
        let cadence = intervals[intervals.count / 2]
        guard abs(cadence - expectedHourlyCadence) <= cadenceTolerance else { return nil }
        return cadence
    }

    // MARK: - Fallback rows

    /// The rows production publishes when no outlook composes: the local
    /// reference day and the two days after it, with no boundaries and no score.
    /// A slot whose civil day cannot be expressed at all is dropped, exactly as
    /// the production builder drops it.
    public static func fallbackNights(
        referenceDate: Date,
        timeZone: TimeZone
    ) -> [NightOutlookNight] {
        let calendar = ObservingCalendar.gregorian(for: timeZone)
        let start = calendar.startOfDay(for: referenceDate)
        return (0..<nightCount).compactMap { slot in
            guard let day = calendar.date(byAdding: .day, value: slot, to: start) else {
                return nil
            }
            return NightOutlookNight(
                slotIndex: slot,
                dayOffset: slot,
                dayIndex: nil,
                observingDayStart: day,
                observingLocalDate: ObservingNightSelector.localDate(day, calendar: calendar),
                astronomicalNightStart: nil,
                astronomicalNightEnd: nil,
                status: .unavailable
            )
        }
    }
}
