import Foundation

/// Shared domain rules used while analyzing a night's observing conditions.
/// These rules intentionally contain no platform presentation concerns.
public enum NightQualityAnalysisRules {
    public enum CloudTiming: Sendable, Equatable {
        case none
        case earlyHeavy
        case lateHeavy
        case intermittentHeavy

        var summaryText: String? {
            switch self {
            case .none: return nil
            case .earlyHeavy: return "Heavy clouds early, with better conditions later."
            case .lateHeavy: return "Decent early, with heavy clouds expected later tonight."
            case .intermittentHeavy: return "A period of heavy clouds may interrupt otherwise better conditions."
            }
        }
    }

    public static func moonPenalty(illumination: Int, altitude: Double) -> Double {
        guard altitude > 0 else { return 0 }

        let illuminationScore: Double
        switch illumination {
        case ...10: illuminationScore = 0
        case ...25: illuminationScore = 0.5
        case ...50: illuminationScore = 1
        default: illuminationScore = 2
        }
        let altitudeFactor = min(max(altitude / 90, 0), 1)
        return illuminationScore * (0.5 + 0.5 * altitudeFactor)
    }

    public static func windPenalty(_ windSpeed: Double) -> Double {
        switch windSpeed {
        case ...3: return 0
        case ...6: return 0.5
        case ...10: return 1
        default: return 2
        }
    }

    public static func cloudTiming(
        in hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> CloudTiming {
        guard let interval = preferredHeavyCloudInterval(in: hourlyRatings) else { return .none }

        switch (interval.hasUsableHoursBefore, interval.hasUsableHoursAfter) {
        case (true, false): return .lateHeavy
        case (false, true): return .earlyHeavy
        case (true, true): return .intermittentHeavy
        case (false, false): return .none
        }
    }

    private struct HeavyCloudInterval {
        let startIndex: Int
        let hourCount: Int
        let averageCloudCover: Double
        let hasUsableHoursBefore: Bool
        let hasUsableHoursAfter: Bool
    }

    private static func preferredHeavyCloudInterval(
        in hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> HeavyCloudInterval? {
        sustainedHeavyCloudIntervals(in: hourlyRatings)
            .filter { $0.hasUsableHoursBefore || $0.hasUsableHoursAfter }
            .sorted { lhs, rhs in
                if lhs.hourCount != rhs.hourCount { return lhs.hourCount > rhs.hourCount }
                if lhs.averageCloudCover != rhs.averageCloudCover {
                    return lhs.averageCloudCover > rhs.averageCloudCover
                }
                return lhs.startIndex < rhs.startIndex
            }
            .first
    }

    private static func sustainedHeavyCloudIntervals(
        in hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> [HeavyCloudInterval] {
        var intervals: [HeavyCloudInterval] = []
        var runStartIndex: Int?

        func appendInterval(endingAt endIndex: Int) {
            guard let startIndex = runStartIndex, endIndex - startIndex >= 1 else { return }

            let hasUsableHoursBefore = hourlyRatings[..<startIndex].contains {
                $0.score < NightQualityAssessment.Rating.Thresholds.fairMax
            }
            let hasUsableHoursAfter = hourlyRatings[(endIndex + 1)...].contains {
                $0.score < NightQualityAssessment.Rating.Thresholds.fairMax
            }
            let ratings = hourlyRatings[startIndex...endIndex]
            intervals.append(
                HeavyCloudInterval(
                    startIndex: startIndex,
                    hourCount: ratings.count,
                    averageCloudCover: Double(ratings.map(\.cloudCover).reduce(0, +)) / Double(ratings.count),
                    hasUsableHoursBefore: hasUsableHoursBefore,
                    hasUsableHoursAfter: hasUsableHoursAfter
                )
            )
        }

        for index in hourlyRatings.indices {
            let isHeavyCloud = hourlyRatings[index].cloudCover >= 80
            let followsPreviousHour = index > 0 &&
                hourlyRatings[index].time.timeIntervalSince(hourlyRatings[index - 1].time) == 3_600

            if isHeavyCloud && (runStartIndex == nil || followsPreviousHour) {
                runStartIndex = runStartIndex ?? index
            } else {
                appendInterval(endingAt: index - 1)
                runStartIndex = isHeavyCloud ? index : nil
            }
        }

        appendInterval(endingAt: hourlyRatings.count - 1)
        return intervals
    }
}
