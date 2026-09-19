import Foundation
import CoreFoundation

public struct ObservingWindowInputError: Error, Sendable {
    public let message = "invalid observing_window.select input"
}

/// Strict transport adapter; production callers use the typed pure selector.
public enum ObservingWindowContract {
    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys).isSubset(of: ["hourly_ratings", "good_rating_threshold"]),
              let rows = input["hourly_ratings"] as? [Any] else { throw ObservingWindowInputError() }
        let ratings = try rows.map { value -> ObservingWindowSelector.HourlyRating in
            guard let row = value as? [String: Any], Set(row.keys) == ["time", "score"] else {
                throw ObservingWindowInputError()
            }
            return try .init(time: date(row["time"]), score: number(row["score"]))
        }
        let threshold = try input["good_rating_threshold"].map(number)
            ?? EngineCalibration.current.nightQuality.ratingThresholds.fairMax
        guard let window = ObservingWindowSelector.select(hourlyRatings: ratings, goodRatingThreshold: threshold) else {
            return ["best_window": NSNull()]
        }
        let start = formatter().string(from: window.start)
        let end = formatter().string(from: window.end)
        // Date supports a wider range than the portable four-digit-year format.
        _ = try date(start)
        _ = try date(end)
        return ["best_window": ["start": start, "end": end]]
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { throw ObservingWindowInputError() }
        return number.doubleValue
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func date(_ value: Any?) throws -> Date {
        guard let text = value as? String,
              text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#, options: .regularExpression) != nil,
              !text.hasPrefix("0000"),
              let date = formatter().date(from: text), formatter().string(from: date) == text else {
            throw ObservingWindowInputError()
        }
        return date
    }
}
