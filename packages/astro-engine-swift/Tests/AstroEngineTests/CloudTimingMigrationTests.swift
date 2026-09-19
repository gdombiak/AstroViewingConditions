import Foundation
import XCTest
@testable import AstroEngine

/// Migration equivalence for the semantic cloud-timing slice.
///
/// The expected side is a verbatim copy of the pre-migration
/// `NightQualityAnalysisRules` implementation, transcribed before production was
/// pointed at ``CloudTimingClassifier``. It deliberately never calls the new
/// classifier or its transport.
final class CloudTimingMigrationTests: XCTestCase {
    private static let base = Date(timeIntervalSince1970: 1_772_496_000)

    // MARK: - Frozen pre-migration implementation

    private struct LegacyHeavyCloudInterval {
        let startIndex: Int
        let hourCount: Int
        let averageCloudCover: Double
        let hasUsableHoursBefore: Bool
        let hasUsableHoursAfter: Bool
    }

    private enum LegacyCloudTiming: Equatable {
        case none
        case earlyHeavy
        case lateHeavy
        case intermittentHeavy
    }

    private static func legacyCloudTiming(
        in hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> LegacyCloudTiming {
        guard let interval = legacyPreferredInterval(in: hourlyRatings) else { return .none }

        switch (interval.hasUsableHoursBefore, interval.hasUsableHoursAfter) {
        case (true, false): return .lateHeavy
        case (false, true): return .earlyHeavy
        case (true, true): return .intermittentHeavy
        case (false, false): return .none
        }
    }

    private static func legacyPreferredInterval(
        in hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> LegacyHeavyCloudInterval? {
        legacySustainedIntervals(in: hourlyRatings)
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

    private static func legacySustainedIntervals(
        in hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> [LegacyHeavyCloudInterval] {
        var intervals: [LegacyHeavyCloudInterval] = []
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
                LegacyHeavyCloudInterval(
                    startIndex: startIndex,
                    hourCount: ratings.count,
                    averageCloudCover: Double(ratings.map(\.cloudCover).reduce(0, +)) / Double(ratings.count),
                    hasUsableHoursBefore: hasUsableHoursBefore,
                    hasUsableHoursAfter: hasUsableHoursAfter
                )
            )
        }

        for index in hourlyRatings.indices {
            let isHeavyCloud =
                hourlyRatings[index].cloudCover
                >= EngineCalibration.current.nightQuality.cloudFloor.cloudCoverMin
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

    private static func expected(
        _ legacy: LegacyCloudTiming
    ) -> NightQualityAnalysisRules.CloudTiming {
        switch legacy {
        case .none: return .none
        case .earlyHeavy: return .earlyHeavy
        case .lateHeavy: return .lateHeavy
        case .intermittentHeavy: return .intermittentHeavy
        }
    }

    // MARK: - Comparison matrix

    /// Straddles the inclusive heavy floor (80) and the strict usable ceiling (1.0).
    private static let scores: [Double] = [0.5, 1.0, 1.5]
    private static let clouds: [Int] = [79, 80, 100]
    /// Contiguous, duplicate, and one second short of contiguous.
    private static let steps: [TimeInterval] = [3600, 0, 3599]

    private static func rating(
        at offset: TimeInterval,
        score: Double,
        cloudCover: Int
    ) -> NightQualityAssessment.HourlyRating {
        .init(
            time: base.addingTimeInterval(offset),
            score: score,
            cloudCover: cloudCover,
            fogScore: 0,
            moonIllumination: 0,
            moonAltitude: 0,
            windSpeed: 0
        )
    }

    private func compare(_ rows: [NightQualityAssessment.HourlyRating], _ label: @autoclosure () -> String) {
        let expected = Self.expected(Self.legacyCloudTiming(in: rows))
        let actual = NightQualityAnalysisRules.cloudTiming(in: rows)
        if actual != expected {
            XCTFail("cloud timing diverged for \(label()): \(actual) vs \(expected)")
        }
    }

    /// Exhaustive over every 0…4 row night drawn from three scores, three cloud
    /// levels and three inter-row steps: 183 961 nights.
    func testExhaustiveShortNightsMatchTheFrozenImplementation() {
        let rowAlphabet = Self.scores.count * Self.clouds.count          // 9
        let stepAlphabet = rowAlphabet * Self.steps.count                // 27
        var comparisons = 0

        compare([], "n=0")
        comparisons += 1

        for count in 1...4 {
            var total = rowAlphabet
            for _ in 1..<max(count, 1) { total *= stepAlphabet }
            if count == 1 { total = rowAlphabet }

            for encoded in 0..<total {
                var remaining = encoded
                var rows: [NightQualityAssessment.HourlyRating] = []
                rows.reserveCapacity(count)
                var offset: TimeInterval = 0

                let first = remaining % rowAlphabet
                remaining /= rowAlphabet
                rows.append(Self.rating(
                    at: offset,
                    score: Self.scores[first % Self.scores.count],
                    cloudCover: Self.clouds[first / Self.scores.count]
                ))

                for _ in 1..<max(count, 1) where count > 1 {
                    let digit = remaining % stepAlphabet
                    remaining /= stepAlphabet
                    let step = Self.steps[digit / rowAlphabet]
                    let cell = digit % rowAlphabet
                    offset += step
                    rows.append(Self.rating(
                        at: offset,
                        score: Self.scores[cell % Self.scores.count],
                        cloudCover: Self.clouds[cell / Self.scores.count]
                    ))
                }

                compare(rows, "n=\(count) encoded=\(encoded)")
                comparisons += 1
            }
        }

        XCTAssertEqual(comparisons, 183_961)
    }

    /// A wider deterministic sweep over longer nights: irregular and backwards
    /// steps, cloud levels either side of the floor, and scores either side of
    /// the usable ceiling.
    func testDeterministicLongerNightSweepMatchesTheFrozenImplementation() {
        let scores: [Double] = [0, 0.5, 0.999, 1.0, 1.001, 1.5, 2.0]
        let clouds: [Int] = [0, 50, 79, 80, 81, 95, 100]
        let steps: [TimeInterval] = [3600, 3600, 3600, 3601, 3599, 0, -3600, 7200, 1800]

        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }

        var comparisons = 0
        for case_ in 0..<20_000 {
            let count = 5 + next(4)  // 5...8 rows
            var rows: [NightQualityAssessment.HourlyRating] = []
            var offset: TimeInterval = 0
            for index in 0..<count {
                if index > 0 { offset += steps[next(steps.count)] }
                rows.append(Self.rating(
                    at: offset,
                    score: scores[next(scores.count)],
                    cloudCover: clouds[next(clouds.count)]
                ))
            }
            compare(rows, "sweep case \(case_)")
            comparisons += 1
        }
        XCTAssertEqual(comparisons, 20_000)
    }

    /// The named production shapes, kept explicit alongside the sweeps.
    func testNamedProductionShapesMatchTheFrozenImplementation() {
        let shapes: [(String, [(TimeInterval, Double, Int)])] = [
            ("empty", []),
            ("one clear row", [(0, 0.2, 10)]),
            ("one heavy row", [(0, 1.5, 100)]),
            ("whole night heavy", [(0, 1.5, 100), (3600, 1.5, 100), (7200, 1.5, 100), (10800, 1.5, 100)]),
            ("heavy only at the beginning", [(0, 1.5, 100), (3600, 1.5, 100), (7200, 0.2, 10), (10800, 0.2, 10)]),
            ("heavy only at the end", [(0, 0.2, 10), (3600, 0.2, 10), (7200, 1.5, 100), (10800, 1.5, 100)]),
            ("heavy in the middle", [(0, 0.2, 10), (3600, 1.5, 100), (7200, 1.5, 100), (10800, 0.2, 10)]),
            ("two equal runs", [(0, 1.2, 90), (3600, 1.2, 90), (7200, 0.2, 10), (10800, 1.2, 90), (14400, 1.2, 90), (21600, 0.2, 10)]),
            ("threshold equality", [(0, 1.0, 80), (3600, 1.0, 80), (7200, 1.0, 79)]),
            ("duplicate timestamps", [(0, 0.2, 10), (3600, 1.2, 90), (3600, 1.2, 90), (3600, 1.2, 90)]),
            ("irregular spacing", [(0, 0.2, 10), (3600, 1.2, 90), (5400, 1.2, 90), (9000, 1.2, 90), (12600, 1.2, 90)]),
            ("distant usable hour", [(0, 0.2, 10), (3600, 1.5, 50), (7200, 1.5, 50), (10800, 1.5, 95), (14400, 1.5, 95)]),
            ("ineligible long run", [(0, 0.5, 100), (3600, 0.5, 100), (7200, 0.5, 100), (10800, 1.5, 10), (14400, 1.5, 90), (18000, 1.5, 90)]),
        ]
        for (label, rows) in shapes {
            compare(rows.map { Self.rating(at: $0.0, score: $0.1, cloudCover: $0.2) }, label)
        }
    }
}
