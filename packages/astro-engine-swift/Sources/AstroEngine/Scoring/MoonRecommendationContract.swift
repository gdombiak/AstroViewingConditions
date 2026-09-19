import Foundation
import CoreFoundation

public struct MoonRecommendationInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        self.code = "validation"
        self.message = "invalid \(MoonRecommendationContract.capabilityID) input"
    }

    init(rowCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(MoonRecommendationContract.capabilityID) exceeds the 1.0 row cap (\(maximum) rows)"
    }
}

/// Strict transport for the deterministic lunar recommendation.
///
/// Normative procedure: contracts/procedures/moon-recommendation.md. The moon
/// fact bundle is injected — the `astronomy.moon_observation` result minus its
/// echoed interval — so no ephemeris runs here.
public enum MoonRecommendationContract {
    public static let capabilityID = "targets.moon_recommendation"

    /// Same fixed modern product range as `targets.deep_sky_windows`.
    static let earliestInstant = Date(timeIntervalSince1970: 946_684_800)
    static let latestInstant = Date(timeIntervalSince1970: 16_725_225_599)

    /// One day of one-minute rows, applied to both injected arrays.
    public static let maxRowCount = 1_440

    public static func evaluate(
        _ input: [String: Any],
        calibration: MoonRecommendationCalibration = EngineCalibration.current.moonRecommendation
    ) throws -> [String: Any] {
        let allowed: Set<String> = [
            "night_start", "night_end", "best_window", "moon", "cloud_cover_score", "hourly_ratings",
        ]
        let keys = Set(input.keys)
        guard keys.isSubset(of: allowed),
              keys.isSuperset(of: ["night_start", "night_end", "moon", "cloud_cover_score", "hourly_ratings"]) else {
            throw MoonRecommendationInputError()
        }

        let nightStart = try date(input["night_start"])
        let nightEnd = try date(input["night_end"])
        let bestWindow = try parseBestWindow(input["best_window"])
        let observation = try parseObservation(input["moon"])
        let cloudCoverScore = try number(input["cloud_cover_score"])
        let hourlyRatings = try parseHourlyRatings(input["hourly_ratings"])

        guard let result = MoonRecommendation.evaluate(
            observation: observation,
            nightStart: nightStart,
            nightEnd: nightEnd,
            bestWindow: bestWindow,
            cloudCoverScore: cloudCoverScore,
            hourlyRatings: hourlyRatings,
            calibration: calibration
        ) else {
            return ["recommendation": NSNull()]
        }

        let window = result.window
        return [
            "recommendation": [
                "score": result.score,
                "visibility_window": [
                    "start": timestamp(window.start),
                    "end": timestamp(window.end),
                    "best_time": timestamp(window.bestTime),
                    "max_altitude": window.maxAltitude.map { $0 as Any } ?? NSNull(),
                    "direction": window.direction.map { $0 as Any } ?? NSNull(),
                    "azimuth": window.azimuth.map { $0 as Any } ?? NSNull(),
                ] as [String: Any],
                "reasons": result.reasons.map(\.rawValue),
            ] as [String: Any],
        ]
    }

    // MARK: - Parsing

    /// Omitted and explicit `null` both mean "no best conditions window", which is
    /// the production `NightQualityAssessment.bestWindow == nil` case.
    private static func parseBestWindow(_ value: Any?) throws -> (start: Date, end: Date)? {
        guard let value, !(value is NSNull) else { return nil }
        guard let object = value as? [String: Any], Set(object.keys) == ["start", "end"] else {
            throw MoonRecommendationInputError()
        }
        return (try date(object["start"]), try date(object["end"]))
    }

    private static func parseObservation(_ value: Any?) throws -> MoonObservationData {
        guard let object = value as? [String: Any],
              Set(object.keys) == [
                  "phase", "illumination", "rise", "set", "always_up", "always_down", "samples",
              ] else {
            throw MoonRecommendationInputError()
        }
        guard let rawSamples = object["samples"] as? [Any], rawSamples.count <= maxRowCount else {
            if object["samples"] is [Any] { throw MoonRecommendationInputError(rowCap: maxRowCount) }
            throw MoonRecommendationInputError()
        }
        var samples: [MoonPositionSample] = []
        samples.reserveCapacity(rawSamples.count)
        for raw in rawSamples {
            guard let row = raw as? [String: Any], Set(row.keys) == ["time", "altitude", "azimuth"] else {
                throw MoonRecommendationInputError()
            }
            let time = try date(row["time"])
            if let previous = samples.last?.time, time <= previous {
                throw MoonRecommendationInputError()
            }
            samples.append(MoonPositionSample(
                time: time,
                altitude: try number(row["altitude"]),
                azimuth: try optionalNumber(row["azimuth"])
            ))
        }
        return MoonObservationData(
            phase: try number(object["phase"]),
            phaseName: "",
            illumination: try integer(object["illumination"]),
            rise: try optionalDate(object["rise"]),
            set: try optionalDate(object["set"]),
            alwaysUp: try boolean(object["always_up"]),
            alwaysDown: try boolean(object["always_down"]),
            positionSamples: samples
        )
    }

    /// Caller order is preserved: production filters and sums the ratings in the
    /// order the night assessment produced them and never sorts them.
    private static func parseHourlyRatings(_ value: Any?) throws -> [MoonRecommendation.HourlyRating] {
        guard let rows = value as? [Any] else { throw MoonRecommendationInputError() }
        guard rows.count <= maxRowCount else { throw MoonRecommendationInputError(rowCap: maxRowCount) }
        return try rows.map { raw in
            guard let row = raw as? [String: Any], Set(row.keys) == ["time", "score"] else {
                throw MoonRecommendationInputError()
            }
            return MoonRecommendation.HourlyRating(
                time: try date(row["time"]),
                score: try number(row["score"])
            )
        }
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { throw MoonRecommendationInputError() }
        return number.doubleValue
    }

    private static func optionalNumber(_ value: Any?) throws -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        return try number(value)
    }

    private static func integer(_ value: Any?) throws -> Int {
        let raw = try number(value)
        guard raw == raw.rounded(.towardZero), raw.magnitude <= 1_000_000_000 else {
            throw MoonRecommendationInputError()
        }
        return Int(raw)
    }

    private static func boolean(_ value: Any?) throws -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw MoonRecommendationInputError()
        }
        return number.boolValue
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
              let date = formatter().date(from: text), formatter().string(from: date) == text,
              date >= earliestInstant, date <= latestInstant else {
            throw MoonRecommendationInputError()
        }
        return date
    }

    private static func optionalDate(_ value: Any?) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        return try date(value)
    }

    /// Window endpoints are injected instants plus whole-second offsets; flooring
    /// keeps the transport shape identical on both hosts.
    private static func timestamp(_ value: Date) -> String {
        formatter().string(from: Date(timeIntervalSince1970: value.timeIntervalSince1970.rounded(.down)))
    }
}
