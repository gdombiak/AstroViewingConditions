import Foundation

/// The final deterministic composition decision for a mixed target night:
/// global ordering and count truncation over candidates that are **already
/// scored**.
///
/// Normative procedure: contracts/procedures/compose-recommendations.md.
/// Every candidate arrives already scored by whichever path the host applied to
/// it — `targets.moon_recommendation` or `targets.planet_recommendation` where a
/// specialized result exists, and the generic `TargetScoring.score` path
/// otherwise, including the production fall-through when a specialized provider
/// returns nothing. Nothing here rescores, renormalizes or reweights any of
/// them; an existing specialized Moon or planet score is never rescored, and no
/// target type has priority independent of its score and best time.
public enum RecommendationComposition {
    public static let capabilityID = "targets.compose_recommendations"

    /// The minimum frozen row production ordering needs. Target metadata,
    /// window endpoints, reasons, summaries, astronomy facts, weather facts and
    /// equipment facts are deliberately absent: none of them can change the
    /// order, and the host keeps its own recommendation objects.
    public struct Candidate: Sendable, Equatable {
        public let key: String
        public let score: Int
        public let bestTime: Date

        public init(key: String, score: Int, bestTime: Date) {
            self.key = key
            self.score = score
            self.bestTime = bestTime
        }
    }

    /// A selected row in final production order. `index` is the caller's
    /// original position and is the unambiguous mapping handle; `key` is echoed
    /// caller identity and never participates in ordering.
    public struct Selection: Sendable, Equatable {
        public let index: Int
        public let key: String

        public init(index: Int, key: String) {
            self.index = index
            self.key = key
        }
    }

    /// Score descending, then best time ascending, then original input index
    /// ascending, truncated to `max(0, limit)`. This is the one ranking rule the
    /// engine has: it delegates to `TargetScoring.rankedIndices`, the same
    /// primitive `targets.recommend` ranks with.
    public static func selected(candidates: [Candidate], limit: Int) -> [Selection] {
        TargetScoring.rankedIndices(
            scores: candidates.map(\.score),
            bestTimes: candidates.map(\.bestTime),
            limit: limit
        ).map { Selection(index: $0, key: candidates[$0].key) }
    }
}
