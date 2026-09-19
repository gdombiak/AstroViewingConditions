import Foundation
import CoreFoundation

public struct PlanetRecommendationInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        self.code = "validation"
        self.message = "invalid \(PlanetRecommendationContract.capabilityID) input"
    }

    init(rowCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(PlanetRecommendationContract.capabilityID) exceeds the 1.0 row cap (\(maximum) rows)"
    }
}

/// Strict transport for the deterministic planet recommendation.
///
/// Normative procedure: contracts/procedures/planet-recommendation.md. The
/// observation samples are injected — the `astronomy.planet_observation`
/// result's `observation.samples` — so no orbital-element math runs here.
public enum PlanetRecommendationContract {
    public static let capabilityID = "targets.planet_recommendation"

    /// Night interval range: the same fixed modern product range as
    /// `targets.deep_sky_windows` and `targets.moon_recommendation`.
    static let earliestInstant = Date(timeIntervalSince1970: 946_684_800)
    static let latestInstant = Date(timeIntervalSince1970: 16_725_225_599)

    // MARK: Bounded spill
    //
    // A valid `astronomy.planet_observation` bundle must be consumable verbatim,
    // and that provider samples *outside* the night interval by construction. The
    // spill is therefore derived from production sampling and scoring semantics,
    // not from a wish for unbounded timestamps. Each offset is a fixed transport
    // literal rather than a calibration read, so tuning the scorer can never widen
    // the accepted instant range.

    /// Observation sampling lead: samples start `night_start - 7200`.
    static let sampleSpillBeforeSeconds: TimeInterval = 2 * 3600
    /// Observation sampling trail: samples end at or before `night_end + 3600`.
    static let sampleSpillAfterSeconds: TimeInterval = 3600
    /// Trail plus the fixed 900 s final-sample window extension: the latest
    /// instant this capability can ever *emit*.
    static let windowSpillAfterSeconds: TimeInterval = 3600 + 900
    /// Lead plus one 3600 s rating hour: the earliest rating whose hour can still
    /// end after the earliest possible window start.
    static let ratingSpillBeforeSeconds: TimeInterval = 2 * 3600 + 3600
    /// A rating must begin strictly before the window end, so it shares the
    /// window's trailing bound.
    static let ratingSpillAfterSeconds: TimeInterval = windowSpillAfterSeconds

    /// Injected observation sample instants: 1999-12-31T22:00:00Z through
    /// 2500-01-01T00:59:59Z.
    static let earliestSampleInstant = earliestInstant.addingTimeInterval(-sampleSpillBeforeSeconds)
    static let latestSampleInstant = latestInstant.addingTimeInterval(sampleSpillAfterSeconds)

    /// Injected hourly-rating instants: 1999-12-31T21:00:00Z through
    /// 2500-01-01T01:14:59Z.
    static let earliestRatingInstant = earliestInstant.addingTimeInterval(-ratingSpillBeforeSeconds)
    static let latestRatingInstant = latestInstant.addingTimeInterval(ratingSpillAfterSeconds)

    /// Emitted window instants: a window opens no earlier than the first sample
    /// and closes no later than the last sample plus the fixed extension.
    static let earliestWindowInstant = earliestSampleInstant
    static let latestWindowInstant = latestInstant.addingTimeInterval(windowSpillAfterSeconds)

    /// One day of one-minute rows, applied to both injected arrays.
    public static let maxRowCount = 1_440

    public static let supportedTargetIDs: [String] =
        PlanetBody.recommendationCandidates.map(\.rawValue)

    public static func evaluate(
        _ input: [String: Any],
        calibration: PlanetRecommendationCalibration = EngineCalibration.current.planetRecommendation
    ) throws -> [String: Any] {
        let allowed: Set<String> = [
            "target_id", "night_start", "night_end", "samples", "cloud_cover_score", "hourly_ratings",
        ]
        let keys = Set(input.keys)
        guard keys == allowed else { throw PlanetRecommendationInputError() }

        let targetID = try planetTargetID(input["target_id"])
        let nightStart = try date(input["night_start"])
        let nightEnd = try date(input["night_end"])
        let samples = try parseSamples(input["samples"])
        let cloudCoverScore = try number(input["cloud_cover_score"])
        let hourlyRatings = try parseHourlyRatings(input["hourly_ratings"])

        guard let result = PlanetRecommendation.evaluate(
            targetID: targetID,
            samples: samples,
            nightStart: nightStart,
            nightEnd: nightEnd,
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
                    "max_altitude": window.maxAltitude,
                    "direction": window.direction,
                    "azimuth": window.azimuth,
                ] as [String: Any],
                "reasons": result.reasons.map(\.rawValue),
            ] as [String: Any],
        ]
    }

    // MARK: - Parsing

    private static func planetTargetID(_ value: Any?) throws -> String {
        guard let text = value as? String, supportedTargetIDs.contains(text) else {
            throw PlanetRecommendationInputError()
        }
        return text
    }

    /// Strictly ordered instants. Production reads the visibility window through
    /// `firstIndex(where: time ==)` / `lastIndex(where: time ==)`, which only has
    /// one meaning for a strictly ordered series, so the transport requires it.
    private static func parseSamples(_ value: Any?) throws -> [PlanetRecommendation.Sample] {
        guard let rawSamples = value as? [Any] else { throw PlanetRecommendationInputError() }
        guard rawSamples.count <= maxRowCount else {
            throw PlanetRecommendationInputError(rowCap: maxRowCount)
        }
        var samples: [PlanetRecommendation.Sample] = []
        samples.reserveCapacity(rawSamples.count)
        for raw in rawSamples {
            guard let row = raw as? [String: Any],
                  Set(row.keys) == ["time", "altitude", "azimuth", "solar_elongation"] else {
                throw PlanetRecommendationInputError()
            }
            let time = try date(
                row["time"],
                notBefore: Self.earliestSampleInstant,
                notAfter: Self.latestSampleInstant
            )
            if let previous = samples.last?.time, time <= previous {
                throw PlanetRecommendationInputError()
            }
            samples.append(PlanetRecommendation.Sample(
                time: time,
                altitude: try number(row["altitude"]),
                azimuth: try number(row["azimuth"]),
                solarElongation: try optionalNumber(row["solar_elongation"])
            ))
        }
        return samples
    }

    /// Caller order is preserved: production filters and sums the ratings in the
    /// order the night assessment produced them and never sorts them.
    private static func parseHourlyRatings(_ value: Any?) throws -> [PlanetRecommendation.HourlyRating] {
        guard let rows = value as? [Any] else { throw PlanetRecommendationInputError() }
        guard rows.count <= maxRowCount else { throw PlanetRecommendationInputError(rowCap: maxRowCount) }
        return try rows.map { raw in
            guard let row = raw as? [String: Any], Set(row.keys) == ["time", "score"] else {
                throw PlanetRecommendationInputError()
            }
            return PlanetRecommendation.HourlyRating(
                time: try date(
                    row["time"],
                    notBefore: Self.earliestRatingInstant,
                    notAfter: Self.latestRatingInstant
                ),
                score: try number(row["score"])
            )
        }
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { throw PlanetRecommendationInputError() }
        return number.doubleValue
    }

    private static func optionalNumber(_ value: Any?) throws -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        return try number(value)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    /// `night_start` / `night_end` keep the plain night range; injected sample and
    /// rating instants pass their own bounded-spill limits.
    private static func date(
        _ value: Any?,
        notBefore: Date = earliestInstant,
        notAfter: Date = latestInstant
    ) throws -> Date {
        guard let text = value as? String,
              text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"#, options: .regularExpression) != nil,
              let date = formatter().date(from: text), formatter().string(from: date) == text,
              date >= notBefore, date <= notAfter else {
            throw PlanetRecommendationInputError()
        }
        return date
    }

    /// Interior window endpoints are interpolated crossings and are generally
    /// not whole seconds. The host keeps the full binary64 instant; the
    /// transport floors, which keeps the shape identical on both hosts.
    ///
    /// Bounded inputs make the emitted instant provably inside
    /// `earliestWindowInstant ... latestWindowInstant`, so this never rejects.
    private static func timestamp(_ value: Date) -> String {
        formatter().string(from: Date(timeIntervalSince1970: value.timeIntervalSince1970.rounded(.down)))
    }
}
