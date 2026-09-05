import Foundation

/// Inclusive upper-bound score bucket (`value <= max`). A nil `max` is the catch-all last row.
public struct UpperBoundScoreBucket: Hashable, Sendable, Decodable {
    public let max: Double?
    public let score: Double
}

/// Inclusive upper-bound bucket whose threshold is compared with an `Int` input.
public struct IntUpperBoundScoreBucket: Hashable, Sendable, Decodable {
    public let max: Int?
    public let score: Double
}

/// Inclusive lower-bound score bucket (`value >= min`). A nil `min` is the catch-all last row.
public struct LowerBoundScoreBucket: Hashable, Sendable, Decodable {
    public let min: Double?
    public let score: Double
}

enum CalibrationTables {
    static func score(for value: Double, in buckets: [UpperBoundScoreBucket]) -> Double {
        for bucket in buckets {
            if let max = bucket.max {
                if value <= max { return bucket.score }
            } else {
                return bucket.score
            }
        }
        return buckets.last?.score ?? 0
    }

    static func score(for value: Int, in buckets: [IntUpperBoundScoreBucket]) -> Double {
        for bucket in buckets {
            if let max = bucket.max {
                if value <= max { return bucket.score }
            } else {
                return bucket.score
            }
        }
        return buckets.last?.score ?? 0
    }

    static func score(for value: Double, in buckets: [LowerBoundScoreBucket]) -> Double {
        for bucket in buckets {
            if let min = bucket.min {
                if value >= min { return bucket.score }
            } else {
                return bucket.score
            }
        }
        return buckets.last?.score ?? 0
    }
}
