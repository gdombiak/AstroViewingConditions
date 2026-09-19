import Foundation

/// The production best-conditions decision over already-included scored rows.
/// See contracts/procedures/observing-window.md for preserved endpoint quirks.
public enum ObservingWindowSelector {
    public struct HourlyRating: Sendable {
        public let time: Date
        public let score: Double

        public init(time: Date, score: Double) {
            self.time = time
            self.score = score
        }
    }

    public static func select(
        hourlyRatings: [HourlyRating],
        goodRatingThreshold: Double = EngineCalibration.current.nightQuality.ratingThresholds.fairMax
    ) -> NightQualityAssessment.TimeWindow? {
        let ratings = hourlyRatings.sorted { $0.time < $1.time }
        guard let first = ratings.first, let last = ratings.last else { return nil }
        let goodCount = ratings.filter { $0.score < goodRatingThreshold }.count
        if goodCount == 0 {
            guard let best = ratings.min(by: { $0.score < $1.score }) else { return nil }
            return .init(start: best.time, end: best.time.addingTimeInterval(3600))
        }
        if Double(goodCount) / Double(ratings.count) >= 0.5 {
            return .init(start: first.time, end: last.time)
        }

        var longestStart = first.time
        var longestLength: TimeInterval = 0
        var currentStart: Date?
        var currentLength: TimeInterval = 0
        for rating in ratings {
            if rating.score < goodRatingThreshold {
                currentStart = currentStart ?? rating.time
                currentLength += 3600
            } else {
                if let start = currentStart, currentLength > longestLength {
                    longestStart = start
                    longestLength = currentLength
                }
                currentStart = nil
                currentLength = 0
            }
        }
        if let start = currentStart, currentLength > longestLength {
            longestStart = start
            longestLength = currentLength
        }
        guard longestLength > 0 else { return nil }
        return .init(start: longestStart, end: longestStart.addingTimeInterval(longestLength))
    }
}
