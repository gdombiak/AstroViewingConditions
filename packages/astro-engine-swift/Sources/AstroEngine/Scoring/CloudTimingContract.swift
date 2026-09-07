import Foundation
import CoreFoundation

public struct CloudTimingInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        self.code = "validation"
        self.message = "invalid \(CloudTimingContract.capabilityID) input"
    }

    init(rowCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(CloudTimingContract.capabilityID) exceeds the 1.0 row cap (\(maximum) rows)"
    }
}

/// Strict JSON adapter for ``CloudTimingClassifier``. Production callers use the
/// typed classifier directly.
///
/// The transport carries only `time`, `score` and `cloud_cover` because those
/// are the only hourly facts the rule reads, and it never sorts: caller order is
/// part of the semantics.
public enum CloudTimingContract {
    public static let capabilityID = CloudTimingClassifier.capabilityID

    /// One day of one-minute rows, the same 1.0 row cap the other row-transport
    /// capabilities use. A production observing night is far smaller.
    public static let maxRowCount = 1_440

    /// The shared engine integer transport magnitude: exactly representable in
    /// binary64 and in a Swift `Int` on every supported platform.
    public static let integerMagnitudeLimit = 1_000_000_000

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys) == ["hourly_ratings"] else { throw CloudTimingInputError() }
        let rows = try parseRows(input["hourly_ratings"])
        return ["cloud_timing": CloudTimingClassifier.classify(rows).rawValue]
    }

    private static func parseRows(_ value: Any?) throws -> [CloudTimingClassifier.HourlyRow] {
        guard let rows = value as? [Any] else { throw CloudTimingInputError() }
        guard rows.count <= maxRowCount else { throw CloudTimingInputError(rowCap: maxRowCount) }
        var parsed: [CloudTimingClassifier.HourlyRow] = []
        parsed.reserveCapacity(rows.count)
        for raw in rows {
            guard let row = raw as? [String: Any],
                  Set(row.keys) == ["time", "score", "cloud_cover"] else {
                throw CloudTimingInputError()
            }
            parsed.append(CloudTimingClassifier.HourlyRow(
                time: try date(row["time"]),
                score: try number(row["score"]),
                cloudCover: try integer(row["cloud_cover"])
            ))
        }
        return parsed
    }

    /// Scores are the production 0-2 weighted doubles; only finiteness is
    /// required, so a threshold-equal `1.0` stays expressible.
    private static func number(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { throw CloudTimingInputError() }
        return number.doubleValue
    }

    /// `HourlyRating.cloudCover` is an `Int` in production, so the transport is
    /// the shared integer form: booleans are not numbers, and a non-finite,
    /// non-integral or unsafely large value is not an integer. `80.0` is
    /// accepted as `80`.
    private static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw CloudTimingInputError()
        }
        let raw = number.doubleValue
        guard raw.isFinite, raw.rounded(.towardZero) == raw,
              raw.magnitude <= Double(integerMagnitudeLimit) else {
            throw CloudTimingInputError()
        }
        return Int(raw)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func date(_ value: Any?) throws -> Date {
        guard let text = value as? String,
              text.range(
                of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#,
                options: .regularExpression
              ) != nil,
              !text.hasPrefix("0000"),
              let date = formatter().date(from: text), formatter().string(from: date) == text else {
            throw CloudTimingInputError()
        }
        return date
    }
}
