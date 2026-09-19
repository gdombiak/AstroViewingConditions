import Foundation
import CoreFoundation

public struct NightOutlookInputError: Error, Sendable {
    public let code: String
    public let message: String

    init(capability: String) {
        self.code = "validation"
        self.message = "invalid \(capability) input"
    }

    init(capability: String, rowCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(capability) exceeds the 1.0 row cap (\(maximum) rows)"
    }

    init(capability: String, dayCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(capability) exceeds the 1.0 day cap (\(maximum) days)"
    }

    init(message: String) {
        self.code = "validation"
        self.message = message
    }
}

/// Strict transport for three-night outlook day composition.
///
/// Normative procedure: contracts/procedures/night-outlook.md. Zone, instant
/// grammar, instant range, day cap and the skipped-civil-date exclusion are the
/// ones `observing_night.resolve_active` already established, because this
/// capability composes over exactly that decision.
public enum NightOutlookContract {
    public static let capabilityID = NightOutlookComposer.capabilityID

    public static let timeZonePolicyPath = ObservingNightContract.timeZonePolicyPath
    public static let earliestInstant = ObservingNightContract.earliestInstant
    public static let latestInstant = ObservingNightContract.latestInstant
    public static let maxDayCount = ObservingNightContract.maxDayCount

    /// One day of one-minute rows, the shared 1.0 row cap. Production hourly
    /// payloads are far smaller; the cap only bounds the transport.
    public static let maxHourlyRowCount = 1_440

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        let allowed: Set<String> = [
            "reference_time", "time_zone", "forecast_start_time",
            "daily_sun_events", "daily_moon_count", "hourly_times",
        ]
        guard Set(input.keys) == allowed else { throw invalid() }

        let identifier = try timeZoneIdentifier(input["time_zone"])
        let accepted: Set<String>
        do {
            accepted = try ObservingNightContract.allowedTimeZoneIdentifiers()
        } catch {
            throw NightOutlookInputError(
                message: "\(capabilityID) cannot read \(timeZonePolicyPath)"
            )
        }
        guard accepted.contains(identifier), let timeZone = TimeZone(identifier: identifier) else {
            throw invalid()
        }

        let referenceDate = try date(input["reference_time"])
        let forecastStartTime = try optionalDate(input["forecast_start_time"])
        let dailySunEvents = try days(input["daily_sun_events"])
        let dailyMoonCount = try moonCount(input["daily_moon_count"])
        let hourlyTimes = try hourly(input["hourly_times"])
        guard !ObservingNightContract.hasSkippedCivilDate(
            referenceDate: referenceDate,
            forecastStartTime: forecastStartTime,
            timeZone: timeZone
        ) else { throw invalid() }

        let outlook = NightOutlookComposer.compose(
            referenceDate: referenceDate,
            timeZone: timeZone,
            forecastStartTime: forecastStartTime,
            dailySunEvents: dailySunEvents,
            dailyMoonCount: dailyMoonCount,
            hourlyTimes: hourlyTimes
        )
        // The two composed days after the reference day can leave the shared
        // instant range at its very end; the window is refused rather than
        // reported outside the transport's own domain.
        for night in outlook.nights {
            guard inRange(night.observingDayStart) else { throw invalid() }
        }

        return [
            "state": outlook.state.rawValue,
            "time_zone": identifier,
            "nights": outlook.nights.map { night in
                [
                    "slot_index": night.slotIndex,
                    "day_offset": night.dayOffset,
                    "day_index": night.dayIndex as Any? ?? NSNull(),
                    "observing_date": night.observingLocalDate,
                    "observing_day_start": text(night.observingDayStart),
                    "astronomical_night_start": night.astronomicalNightStart.map(text)
                        as Any? ?? NSNull(),
                    "astronomical_night_end": night.astronomicalNightEnd.map(text)
                        as Any? ?? NSNull(),
                    "status": night.status.rawValue,
                ] as [String: Any]
            },
        ]
    }

    // MARK: - Parsing

    private static func invalid() -> NightOutlookInputError {
        NightOutlookInputError(capability: capabilityID)
    }

    private static func timeZoneIdentifier(_ value: Any?) throws -> String {
        guard let text = value as? String, !text.isEmpty else { throw invalid() }
        return text
    }

    /// Rows are never reordered or validated for chronology: within one row the
    /// begin is that civil morning and the end that civil evening.
    private static func days(_ value: Any?) throws -> [ObservingNightSelector.DailySunEvents] {
        guard let rows = value as? [Any] else { throw invalid() }
        guard rows.count <= maxDayCount else {
            throw NightOutlookInputError(capability: capabilityID, dayCap: maxDayCount)
        }
        var days: [ObservingNightSelector.DailySunEvents] = []
        days.reserveCapacity(rows.count)
        for raw in rows {
            guard let row = raw as? [String: Any],
                  Set(row.keys) == ["astronomical_twilight_end", "astronomical_twilight_begin"]
            else { throw invalid() }
            days.append(ObservingNightSelector.DailySunEvents(
                astronomicalTwilightEnd: try date(row["astronomical_twilight_end"]),
                astronomicalTwilightBegin: try date(row["astronomical_twilight_begin"])
            ))
        }
        return days
    }

    /// The daily Moon array is transported as its length because the decision
    /// only ever bounds-checks it; no Moon fact participates.
    private static func moonCount(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw invalid()
        }
        let raw = number.doubleValue
        guard raw.isFinite, raw.rounded(.towardZero) == raw,
              raw >= 0, raw <= Double(maxDayCount) else { throw invalid() }
        return Int(raw)
    }

    /// Only the hourly timestamps cross the transport. Caller order is not
    /// semantics here — the coverage rule sorts, exactly as production does.
    private static func hourly(_ value: Any?) throws -> [Date] {
        guard let rows = value as? [Any] else { throw invalid() }
        guard rows.count <= maxHourlyRowCount else {
            throw NightOutlookInputError(capability: capabilityID, rowCap: maxHourlyRowCount)
        }
        return try rows.map { try date($0) }
    }

    private static func optionalDate(_ value: Any?) throws -> Date? {
        if value is NSNull { return nil }
        return try date(value)
    }

    private static func date(_ value: Any?) throws -> Date {
        guard let text = value as? String,
              text.range(
                of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#,
                options: .regularExpression
              ) != nil,
              let date = formatter().date(from: text), formatter().string(from: date) == text,
              inRange(date) else { throw invalid() }
        return date
    }

    private static func inRange(_ date: Date) -> Bool {
        date >= earliestInstant && date <= latestInstant
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func text(_ date: Date) -> String {
        formatter().string(from: date)
    }
}

/// Strict transport for deterministic best-night selection.
///
/// Normative procedure: contracts/procedures/night-outlook.md. The rows are the
/// composed outlook's own statuses plus the host's headline score for each one.
/// Nothing here re-derives a status or a score.
public enum BestNightContract {
    public static let capabilityID = "observing_night.select_best"

    /// The outlook is three nights; a shorter list is accepted because a host
    /// may carry a partially composed one, and an empty list simply has no best
    /// night.
    public static let maxNightCount = NightOutlookComposer.nightCount

    /// Both public score capabilities clamp to this closed range, so a score
    /// outside it never comes from the engine.
    public static let minimumScore = 0
    public static let maximumScore = 100

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys) == ["nights"] else { throw invalid() }
        guard let rows = input["nights"] as? [Any] else { throw invalid() }
        guard rows.count <= maxNightCount else {
            throw NightOutlookInputError(capability: capabilityID, rowCap: maxNightCount)
        }

        var candidates: [NightOutlookComposer.BestNightCandidate] = []
        candidates.reserveCapacity(rows.count)
        for raw in rows {
            guard let row = raw as? [String: Any],
                  Set(row.keys) == ["status", "score"],
                  let statusText = row["status"] as? String,
                  let status = NightOutlookNightStatus(rawValue: statusText) else {
                throw invalid()
            }
            candidates.append(NightOutlookComposer.BestNightCandidate(
                status: status,
                score: try optionalScore(row["score"])
            ))
        }

        let best = NightOutlookComposer.selectBestNight(candidates)
        return ["best_index": best as Any? ?? NSNull()]
    }

    private static func invalid() -> NightOutlookInputError {
        NightOutlookInputError(capability: capabilityID)
    }

    private static func optionalScore(_ value: Any?) throws -> Int? {
        if value is NSNull { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw invalid()
        }
        let raw = number.doubleValue
        guard raw.isFinite, raw.rounded(.towardZero) == raw,
              raw >= Double(minimumScore), raw <= Double(maximumScore) else { throw invalid() }
        return Int(raw)
    }
}
