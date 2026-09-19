import Foundation
import CoreFoundation

public struct ObservingNightInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        self.code = "validation"
        self.message = "invalid \(ObservingNightContract.capabilityID) input"
    }

    init(dayCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(ObservingNightContract.capabilityID) exceeds the 1.0 day cap (\(maximum) days)"
    }

    init(message: String) {
        self.code = "validation"
        self.message = message
    }
}

/// Strict transport for the active observing-night decision.
///
/// Normative procedure: contracts/procedures/observing-night.md. The zone is an
/// authoritative IANA identifier supplied by the host; this transport never
/// approximates one from longitude and never geocodes, because production
/// resolves the zone before the night decision runs.
public enum ObservingNightContract {
    public static let capabilityID = ObservingNightSelector.capabilityID

    /// The shared engine instant transport: 2000-01-01T00:00:00Z through
    /// 2499-12-31T23:59:59Z. The target capabilities use the same two epoch
    /// bounds; the extra spill they document belongs to their own windows, not
    /// to this one.
    static let earliestInstant = Date(timeIntervalSince1970: 946_684_800)
    static let latestInstant = Date(timeIntervalSince1970: 16_725_225_599)

    /// The public transport accepts exactly the catalogued shared location-style
    /// timezone identifiers under contracts/data: the slash-form names present
    /// in both Foundation's `knownTimeZoneIdentifiers` and Python's
    /// `zoneinfo.available_timezones()`. Neither Foundation's extra identifiers
    /// (`GMT-0800`, `EST5EDT`, `US/Pacific`) nor a host tzdata's private names
    /// may define the public API. The catalogue is symmetric across hosts, not
    /// canonical-IANA-only: historical aliases both runtimes publish are in it.
    public static let timeZonePolicyPath = "data/timezones/observing-night-zones.json"

    /// `BestSpotSearcher.maxForecastDays` is the largest daily payload
    /// production ever builds, so it is the day cap for both daily arrays.
    public static let maxDayCount = 16

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        let allowed: Set<String> = [
            "reference_time", "time_zone", "forecast_start_time",
            "daily_sun_events", "daily_moon_count",
        ]
        guard Set(input.keys) == allowed else { throw ObservingNightInputError() }

        let identifier = try timeZoneIdentifier(input["time_zone"])
        guard try allowedTimeZoneIdentifiers().contains(identifier),
              let timeZone = TimeZone(identifier: identifier) else {
            throw ObservingNightInputError()
        }
        let referenceDate = try date(input["reference_time"])
        let forecastStartTime = try optionalDate(input["forecast_start_time"])
        let dailySunEvents = try days(input["daily_sun_events"])
        let dailyMoonCount = try moonCount(input["daily_moon_count"])
        try requireNoSkippedCivilDate(
            referenceDate: referenceDate,
            forecastStartTime: forecastStartTime,
            timeZone: timeZone
        )

        let selection = ObservingNightSelector.select(
            referenceDate: referenceDate,
            timeZone: timeZone,
            forecastStartTime: forecastStartTime,
            dailySunEvents: dailySunEvents,
            dailyMoonCount: dailyMoonCount
        )
        return result(selection, timeZone: identifier)
    }

    /// Every key is always present. A state that carries no night reports JSON
    /// null rather than omitting the field, so the three states stay distinct
    /// under `null_vs_omitted: distinct`.
    private static func result(
        _ selection: ObservingNightSelection,
        timeZone: String
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "state": NSNull(),
            "time_zone": timeZone,
            "day_offset": NSNull(),
            "day_index": NSNull(),
            "observing_date": NSNull(),
            "observing_day_start": NSNull(),
            "astronomical_night_start": NSNull(),
            "astronomical_night_end": NSNull(),
        ]
        switch selection {
        case let .selected(night):
            payload["state"] = "resolved"
            payload["day_offset"] = night.dayOffset
            payload["day_index"] = night.dayIndex
            payload["observing_date"] = night.observingLocalDate
            payload["observing_day_start"] = text(night.observingDayStart)
            payload["astronomical_night_start"] = text(night.astronomicalNightStart)
            payload["astronomical_night_end"] = text(night.astronomicalNightEnd)
        case .requiresActivePreviousPayload:
            payload["state"] = "requires_active_previous_payload"
        case .unavailable:
            payload["state"] = "unavailable"
        }
        return payload
    }

    // MARK: - Timezone policy

    private static let allowedIdentifiersBox = AllowedIdentifiers()

    private final class AllowedIdentifiers: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: Set<String>?

        func value() throws -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            if let cached { return cached }
            let root = try ContractsRoot.resolve()
            let url = root.appendingPathComponent(ObservingNightContract.timeZonePolicyPath)
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(TimeZonePolicy.self, from: data)
            let identifiers = Set(document.identifiers)
            cached = identifiers
            return identifiers
        }
    }

    private struct TimeZonePolicy: Decodable {
        let identifiers: [String]
    }

    /// The catalogued shared identifier set. Reads `contracts/data`; the typed
    /// ``ObservingNightSelector`` API never consults it, which is why the iOS
    /// host keeps its own `TimeZone` values, including the longitude
    /// approximation, without needing the contracts root at runtime.
    public static func allowedTimeZoneIdentifiers() throws -> Set<String> {
        do {
            return try allowedIdentifiersBox.value()
        } catch {
            throw ObservingNightInputError(
                message: "\(capabilityID) cannot read \(timeZonePolicyPath)"
            )
        }
    }

    /// Rejects a zone that dropped an entire civil date inside the usable
    /// window. A line crossing (`Pacific/Apia` and `Pacific/Fakaofo` dropped
    /// 2011-12-30) is the one case where Foundation's day arithmetic is not
    /// reproducible portably, so the contract excludes it explicitly on both
    /// hosts rather than diverging silently. Only a missing civil *date* trips
    /// this; a missing hour never does.
    private static func requireNoSkippedCivilDate(
        referenceDate: Date,
        forecastStartTime: Date?,
        timeZone: TimeZone
    ) throws {
        guard !hasSkippedCivilDate(
            referenceDate: referenceDate,
            forecastStartTime: forecastStartTime,
            timeZone: timeZone
        ) else { throw ObservingNightInputError() }
    }

    /// The same exclusion as a predicate, so a capability that composes over
    /// this decision can reject the zone under its own error identity.
    static func hasSkippedCivilDate(
        referenceDate: Date,
        forecastStartTime: Date?,
        timeZone: TimeZone
    ) -> Bool {
        let calendar = ObservingCalendar.gregorian(for: timeZone)
        var first = calendar.dateComponents(
            [.year, .month, .day], from: referenceDate
        )
        if let forecastStartTime {
            let other = calendar.dateComponents(
                [.year, .month, .day], from: forecastStartTime
            )
            if isEarlier(other, than: first) { first = other }
        }
        // One day back covers the dayOffset -1 probe, then the bounded window.
        for offset in (-1)...dayWindowBound {
            guard let day = shift(first, byDays: offset),
                  civilDateExists(day, calendar: calendar) else {
                return true
            }
        }
        return false
    }

    /// One past the day cap: the widest usable separation between the forecast
    /// start day and the reference day. A larger separation already fails the
    /// index guard on both hosts.
    static let dayWindowBound = maxDayCount + 1

    private static func isEarlier(_ lhs: DateComponents, than rhs: DateComponents) -> Bool {
        (lhs.year ?? 0, lhs.month ?? 0, lhs.day ?? 0) < (rhs.year ?? 0, rhs.month ?? 0, rhs.day ?? 0)
    }

    /// Pure proleptic-Gregorian date arithmetic, deliberately zone-independent:
    /// the question is which civil dates exist, so the shift must not itself go
    /// through the zone.
    private static func shift(_ day: DateComponents, byDays offset: Int) -> DateComponents? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var base = DateComponents()
        base.year = day.year
        base.month = day.month
        base.day = day.day
        guard let anchor = utc.date(from: base),
              let moved = utc.date(byAdding: .day, value: offset, to: anchor) else {
            return nil
        }
        return utc.dateComponents([.year, .month, .day], from: moved)
    }

    /// Whether any instant falls on this local civil date. On a dropped date the
    /// first resolvable instant lands on a different date.
    private static func civilDateExists(_ day: DateComponents, calendar: Calendar) -> Bool {
        var request = DateComponents()
        request.year = day.year
        request.month = day.month
        request.day = day.day
        guard let instant = calendar.date(from: request) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: instant)
        return resolved.year == day.year && resolved.month == day.month
            && resolved.day == day.day
    }

    // MARK: - Parsing

    private static func timeZoneIdentifier(_ value: Any?) throws -> String {
        guard let text = value as? String, !text.isEmpty else {
            throw ObservingNightInputError()
        }
        return text
    }

    /// Rows are never reordered or validated for chronology: within one row the
    /// begin is that civil morning and the end that civil evening, so a row is
    /// expected to read "backwards", and degenerate high-latitude days are
    /// production data rather than malformed input.
    private static func days(_ value: Any?) throws -> [ObservingNightSelector.DailySunEvents] {
        guard let rows = value as? [Any] else { throw ObservingNightInputError() }
        guard rows.count <= maxDayCount else {
            throw ObservingNightInputError(dayCap: maxDayCount)
        }
        var days: [ObservingNightSelector.DailySunEvents] = []
        days.reserveCapacity(rows.count)
        for raw in rows {
            guard let row = raw as? [String: Any],
                  Set(row.keys) == ["astronomical_twilight_end", "astronomical_twilight_begin"] else {
                throw ObservingNightInputError()
            }
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
            throw ObservingNightInputError()
        }
        let raw = number.doubleValue
        guard raw.isFinite, raw.rounded(.towardZero) == raw,
              raw >= 0, raw <= Double(maxDayCount) else {
            throw ObservingNightInputError()
        }
        return Int(raw)
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

    private static func optionalDate(_ value: Any?) throws -> Date? {
        if value is NSNull { return nil }
        return try date(value)
    }

    private static func date(_ value: Any?) throws -> Date {
        guard let text = value as? String,
              text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#, options: .regularExpression) != nil,
              let date = formatter().date(from: text), formatter().string(from: date) == text,
              date >= earliestInstant, date <= latestInstant else {
            throw ObservingNightInputError()
        }
        return date
    }
}
