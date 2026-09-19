import Foundation

/// The observing night a host should treat as "Tonight", plus its authoritative
/// boundaries.
///
/// `dayOffset` is relative to the local reference day (`0` = the reference civil
/// date, `-1` = the preceding civil date whose astronomical night is still
/// running). `dayIndex` is the index the same decision selected in the caller's
/// daily Sun/Moon arrays.
public struct ObservingNight: Sendable, Equatable {
    public let dayOffset: Int
    public let dayIndex: Int
    /// First moment of the observing day in the resolved zone. This is the
    /// instant production carries as `TargetRecommendationContextResolution.observingDate`.
    public let observingDayStart: Date
    /// The observing day as a local civil date, `YYYY-MM-DD` in the resolved zone.
    public let observingLocalDate: String
    /// Evening astronomical twilight end of the observing day.
    public let astronomicalNightStart: Date
    /// Morning astronomical twilight begin of the following day when that day is
    /// represented, otherwise the observing day's own morning twilight begin.
    public let astronomicalNightEnd: Date

    public init(
        dayOffset: Int,
        dayIndex: Int,
        observingDayStart: Date,
        observingLocalDate: String,
        astronomicalNightStart: Date,
        astronomicalNightEnd: Date
    ) {
        self.dayOffset = dayOffset
        self.dayIndex = dayIndex
        self.observingDayStart = observingDayStart
        self.observingLocalDate = observingLocalDate
        self.astronomicalNightStart = astronomicalNightStart
        self.astronomicalNightEnd = astronomicalNightEnd
    }
}

/// The three externally observable outcomes of the Tonight decision.
///
/// The middle case is deliberately not collapsed into `unavailable`: it means
/// "an earlier astronomical night may still be running, but this payload cannot
/// resolve it", which hosts use to preserve a previously published payload.
public enum ObservingNightSelection: Sendable, Equatable {
    case selected(ObservingNight)
    case requiresActivePreviousPayload
    case unavailable
}

/// Chooses which local observing night is active for a reference instant.
///
/// Normative procedure: contracts/procedures/observing-night.md. This is the
/// portable form of the production cross-midnight authority. It resolves no
/// timezone, fetches nothing, reads no calibration and scores nothing: the
/// caller supplies an already-resolved zone, the reference instant, the first
/// hourly-forecast timestamp used for day indexing, the per-day astronomical
/// twilight pair, and how many daily Moon rows the same payload carries.
public enum ObservingNightSelector {
    public static let capabilityID = "observing_night.resolve_active"

    /// The only two Sun facts the decision consumes. `astronomicalTwilightBegin`
    /// is the **morning** of that civil day and `astronomicalTwilightEnd` its
    /// **evening**, so a row is never chronologically ordered and the night
    /// window intentionally spans two rows.
    public struct DailySunEvents: Sendable, Equatable {
        public let astronomicalTwilightEnd: Date
        public let astronomicalTwilightBegin: Date

        public init(astronomicalTwilightEnd: Date, astronomicalTwilightBegin: Date) {
            self.astronomicalTwilightEnd = astronomicalTwilightEnd
            self.astronomicalTwilightBegin = astronomicalTwilightBegin
        }

        public init(_ events: SunEvents) {
            self.init(
                astronomicalTwilightEnd: events.astronomicalTwilightEnd,
                astronomicalTwilightBegin: events.astronomicalTwilightBegin
            )
        }
    }

    /// Preceding-night first, then the reference civil date, exactly as the
    /// production resolver orders them.
    ///
    /// - Parameters:
    ///   - referenceDate: the instant being asked about.
    ///   - timeZone: the already-resolved location zone. Acquisition and the
    ///     production precedence chain stay with the host.
    ///   - forecastStartTime: the first hourly-forecast timestamp, or `nil` when
    ///     the payload carries no hourly forecasts. `nil` makes the day index the
    ///     bare day offset, which is why an empty hourly payload can never
    ///     resolve the preceding night.
    ///   - dailySunEvents: one row per represented day, aligned with the
    ///     forecast's first day.
    ///   - dailyMoonCount: the number of daily Moon rows in the same payload.
    ///     The production guard requires the selected index to exist in both
    ///     daily arrays.
    public static func select(
        referenceDate: Date,
        timeZone: TimeZone,
        forecastStartTime: Date?,
        dailySunEvents: [DailySunEvents],
        dailyMoonCount: Int
    ) -> ObservingNightSelection {
        let calendar = ObservingCalendar.gregorian(for: timeZone)

        if let previous = night(
            dayOffset: -1,
            calendar: calendar,
            referenceDate: referenceDate,
            forecastStartTime: forecastStartTime,
            dailySunEvents: dailySunEvents,
            dailyMoonCount: dailyMoonCount
        ), referenceDate >= previous.astronomicalNightStart,
           referenceDate <= previous.astronomicalNightEnd {
            return .selected(previous)
        }

        guard let current = night(
            dayOffset: 0,
            calendar: calendar,
            referenceDate: referenceDate,
            forecastStartTime: forecastStartTime,
            dailySunEvents: dailySunEvents,
            dailyMoonCount: dailyMoonCount
        ) else { return .unavailable }

        // The observing day of offset 0 is the reference day, so production's
        // same-local-day guard is always satisfied here. It is reproduced rather
        // than assumed away.
        if calendar.isDate(current.observingDayStart, inSameDayAs: referenceDate),
           referenceDate <= dailySunEvents[current.dayIndex].astronomicalTwilightBegin {
            return .requiresActivePreviousPayload
        }
        return .selected(current)
    }

    // MARK: - Day resolution

    /// Resolves one observing night at an explicit day offset, under exactly
    /// the guards ``select(referenceDate:timeZone:forecastStartTime:dailySunEvents:dailyMoonCount:)``
    /// applies. Composition capabilities that need consecutive nights reuse this
    /// rather than re-deriving day indexing or the twilight pairing.
    public static func night(
        dayOffset: Int,
        referenceDate: Date,
        timeZone: TimeZone,
        forecastStartTime: Date?,
        dailySunEvents: [DailySunEvents],
        dailyMoonCount: Int
    ) -> ObservingNight? {
        night(
            dayOffset: dayOffset,
            calendar: ObservingCalendar.gregorian(for: timeZone),
            referenceDate: referenceDate,
            forecastStartTime: forecastStartTime,
            dailySunEvents: dailySunEvents,
            dailyMoonCount: dailyMoonCount
        )
    }

    private static func night(
        dayOffset: Int,
        calendar: Calendar,
        referenceDate: Date,
        forecastStartTime: Date?,
        dailySunEvents: [DailySunEvents],
        dailyMoonCount: Int
    ) -> ObservingNight? {
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let dayIndex: Int
        if let forecastStartTime {
            let firstForecastDay = calendar.startOfDay(for: forecastStartTime)
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
              dayIndex < dailySunEvents.count,
              dayIndex < dailyMoonCount,
              let observingDayStart = calendar.date(
                byAdding: .day,
                value: dayOffset,
                to: referenceDay
              ) else {
            return nil
        }

        let today = dailySunEvents[dayIndex]
        let nextIndex = dayIndex + 1
        let tomorrow = nextIndex < dailySunEvents.count ? dailySunEvents[nextIndex] : nil
        return ObservingNight(
            dayOffset: dayOffset,
            dayIndex: dayIndex,
            observingDayStart: observingDayStart,
            observingLocalDate: localDate(observingDayStart, calendar: calendar),
            astronomicalNightStart: today.astronomicalTwilightEnd,
            astronomicalNightEnd: tomorrow?.astronomicalTwilightBegin
                ?? today.astronomicalTwilightBegin
        )
    }

    static func localDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}
