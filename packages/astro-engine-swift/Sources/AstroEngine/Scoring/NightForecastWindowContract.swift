import Foundation

public struct NightForecastWindowInputError: Error, Sendable {
    public let code: String
    public let message: String

    init(message: String = "invalid \(NightForecastWindowContract.capabilityID) input") {
        self.code = "validation"
        self.message = message
    }
}

/// Strict JSON adapter for ``NightForecastWindowDeriver``. The typed API takes
/// a `TimeZone`-pinned `Calendar` directly and does not consult transport data.
public enum NightForecastWindowContract {
    public static let capabilityID = NightForecastWindowDeriver.capabilityID
    public static let timeZonePolicyPath = ObservingNightContract.timeZonePolicyPath
    public static let earliestInstant = ObservingNightContract.earliestInstant
    public static let latestInstant = ObservingNightContract.latestInstant

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        let allowed: Set<String> = [
            "observing_time", "time_zone", "astronomical_twilight_end",
            "astronomical_twilight_begin", "tomorrow_astronomical_twilight_begin",
        ]
        guard Set(input.keys) == allowed else { throw NightForecastWindowInputError() }

        let identifier = try timeZoneIdentifier(input["time_zone"])
        let accepted: Set<String>
        do {
            accepted = try ObservingNightContract.allowedTimeZoneIdentifiers()
        } catch {
            throw NightForecastWindowInputError(
                message: "\(capabilityID) cannot read \(timeZonePolicyPath)"
            )
        }
        guard accepted.contains(identifier), let timeZone = TimeZone(identifier: identifier) else {
            throw NightForecastWindowInputError()
        }

        let window = NightForecastWindowDeriver.derive(
            astronomicalTwilightEnd: try date(input["astronomical_twilight_end"]),
            astronomicalTwilightBegin: try date(input["astronomical_twilight_begin"]),
            tomorrowAstronomicalTwilightBegin: try optionalDate(
                input["tomorrow_astronomical_twilight_begin"]
            ),
            for: try date(input["observing_time"]),
            calendar: ObservingCalendar.gregorian(for: timeZone)
        )
        guard window.start >= earliestInstant, window.start <= latestInstant,
              window.end >= earliestInstant, window.end <= latestInstant else {
            throw NightForecastWindowInputError()
        }
        return [
            "time_zone": identifier,
            "start": text(window.start),
            "end": text(window.end),
        ]
    }

    private static func timeZoneIdentifier(_ value: Any?) throws -> String {
        guard let text = value as? String, !text.isEmpty else {
            throw NightForecastWindowInputError()
        }
        return text
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
              date >= earliestInstant, date <= latestInstant else {
            throw NightForecastWindowInputError()
        }
        return date
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
