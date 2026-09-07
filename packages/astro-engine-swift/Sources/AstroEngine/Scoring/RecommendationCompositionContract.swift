import Foundation
import CoreFoundation

public struct RecommendationCompositionInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        self.code = "validation"
        self.message = "invalid \(RecommendationCompositionContract.capabilityID) input"
    }

    init(rowCap maximum: Int) {
        self.code = "sample_cap"
        self.message = "\(RecommendationCompositionContract.capabilityID) exceeds the 1.0 row cap (\(maximum) rows)"
    }
}

/// Strict transport for the final mixed-target composition decision.
///
/// Normative procedure: contracts/procedures/compose-recommendations.md. The
/// scores and best times are injected — each row is the result of whichever
/// path the host applied to it, specialized (`targets.moon_recommendation`,
/// `targets.planet_recommendation`) or generic (`targets.recommend`) — so no
/// scorer, provider or catalog runs here.
public enum RecommendationCompositionContract {
    public static let capabilityID = RecommendationComposition.capabilityID

    /// `best_time` accepts the union of the `visibility_window` instant ranges
    /// the three recommendation capabilities can emit. `targets.deep_sky_windows`
    /// and `targets.moon_recommendation` stay inside the plain modern product
    /// range; `targets.planet_recommendation` spills `-7200 / +4500` around it.
    /// The widest of the three is therefore the accepted range here, so every
    /// production recommendation is composable verbatim. These are fixed
    /// transport literals, not calibration reads.
    static let nightRangeStart = Date(timeIntervalSince1970: 946_684_800)
    static let nightRangeEnd = Date(timeIntervalSince1970: 16_725_225_599)
    static let spillBeforeSeconds: TimeInterval = 2 * 3600
    static let spillAfterSeconds: TimeInterval = 3600 + 900

    /// 1999-12-31T22:00:00Z through 2500-01-01T01:14:59Z.
    static let earliestInstant = nightRangeStart.addingTimeInterval(-spillBeforeSeconds)
    static let latestInstant = nightRangeEnd.addingTimeInterval(spillAfterSeconds)

    /// One day of one-minute candidate rows, the same 1.0 row cap the other
    /// target capabilities use.
    public static let maxRowCount = 1_440

    /// `limit` carries no semantic bound: production is `prefix(max(0, limit))`
    /// over an array the row cap already bounds, so a limit above the cap cannot
    /// add work or output and a negative one selects nothing. Only the shared
    /// engine integer-transport magnitude applies — the same
    /// `targets.moon_recommendation` convention — which keeps the value exactly
    /// representable in binary64 and in `Int` on every supported platform.
    public static let integerMagnitudeLimit = 1_000_000_000

    /// `TargetRecommendation.init` clamps the production score to `0 ... 100`,
    /// so that is the integer domain a composable candidate can carry.
    public static let minScore = 0
    public static let maxScore = 100

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        let allowed: Set<String> = ["candidates", "limit"]
        guard Set(input.keys) == allowed else { throw RecommendationCompositionInputError() }

        let candidates = try parseCandidates(input["candidates"])
        let limit = try integer(input["limit"])

        let selected = RecommendationComposition.selected(candidates: candidates, limit: limit)
        return ["selected": selected.map { ["index": $0.index, "key": $0.key] as [String: Any] }]
    }

    // MARK: - Parsing

    /// Caller order is semantically significant: it is the last tie breaker, so
    /// the rows are never sorted or deduplicated during parsing.
    ///
    /// Duplicate `key` values are **accepted**. One production target can
    /// contribute more than one candidate (a deep-sky target with several
    /// visibility windows), production never deduplicates them, and the host
    /// maps a selection back through `index`, which is unique by construction.
    /// This is the one place the composition transport deliberately differs from
    /// `targets.recommend`, whose keys are its only output handle.
    private static func parseCandidates(_ value: Any?) throws -> [RecommendationComposition.Candidate] {
        guard let rows = value as? [Any] else { throw RecommendationCompositionInputError() }
        guard rows.count <= maxRowCount else {
            throw RecommendationCompositionInputError(rowCap: maxRowCount)
        }
        var candidates: [RecommendationComposition.Candidate] = []
        candidates.reserveCapacity(rows.count)
        for raw in rows {
            guard let row = raw as? [String: Any],
                  Set(row.keys) == ["key", "score", "best_time"] else {
                throw RecommendationCompositionInputError()
            }
            candidates.append(RecommendationComposition.Candidate(
                key: try key(row["key"]),
                score: try score(row["score"]),
                bestTime: try date(row["best_time"])
            ))
        }
        return candidates
    }

    private static func key(_ value: Any?) throws -> String {
        guard let text = value as? String, !text.isEmpty else {
            throw RecommendationCompositionInputError()
        }
        return text
    }

    /// The shared engine integer transport, as `targets.moon_recommendation`
    /// defines it: JSON booleans are not numbers, and a non-finite,
    /// non-integral or unsafely large value is not an integer. `5.0` is accepted
    /// as `5`, the same way `targets.recommend` accepts an integral moon
    /// illumination.
    private static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw RecommendationCompositionInputError()
        }
        let raw = number.doubleValue
        guard raw.isFinite, raw.rounded(.towardZero) == raw,
              raw.magnitude <= Double(integerMagnitudeLimit) else {
            throw RecommendationCompositionInputError()
        }
        return Int(raw)
    }

    /// The production recommendation score domain on top of that transport.
    private static func score(_ value: Any?) throws -> Int {
        let value = try integer(value)
        guard value >= minScore, value <= maxScore else {
            throw RecommendationCompositionInputError()
        }
        return value
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
            throw RecommendationCompositionInputError()
        }
        return date
    }
}
