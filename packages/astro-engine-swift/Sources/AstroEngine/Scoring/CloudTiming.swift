import Foundation

/// Authoritative semantic classification of *when* heavy cloud interrupts an
/// observing night.
///
/// This is the portable form of the rule production `NightQualityAnalyzer`
/// reaches through ``NightQualityAnalysisRules/cloudTiming(in:)``. It is
/// deliberately semantics-only: the English advice a host builds from the
/// verdict is presentation and is not part of the public contract.
///
/// Normative procedure: contracts/procedures/cloud-timing.md.
public enum CloudTimingClassifier {
    public static let capabilityID = "night_conditions.classify_cloud_timing"

    /// Exactly the three hourly facts the rule reads. Every other
    /// `NightQualityAssessment.HourlyRating` field — fog, moon, wind, seeing,
    /// transparency, identity — is deliberately absent because the
    /// classification never consults it.
    public struct HourlyRow: Sendable, Equatable {
        public let time: Date
        public let score: Double
        public let cloudCover: Int

        public init(time: Date, score: Double, cloudCover: Int) {
            self.time = time
            self.score = score
            self.cloudCover = cloudCover
        }
    }

    /// The four production verdicts. Raw values are the public transport domain.
    public enum Classification: String, Sendable, Equatable, CaseIterable {
        case none
        case earlyHeavy = "early_heavy"
        case lateHeavy = "late_heavy"
        case intermittentHeavy = "intermittent_heavy"
    }

    /// Caller order **is** the rule's order: rows are never sorted, deduplicated
    /// or reordered. Adjacency is an exact `3600` second delta between array
    /// neighbours, the usable-hour tests scan the whole prefix and suffix around
    /// a run rather than only its neighbours, and the last tie break is the
    /// array start index.
    ///
    /// Thresholds come from the shared night-quality calibration:
    /// heavy is `cloud_floor.cloud_cover_min` inclusive, usable is strictly
    /// below `rating_thresholds.fair_max`.
    public static func classify(_ rows: [HourlyRow]) -> Classification {
        let night = EngineCalibration.current.nightQuality
        return classify(
            rows,
            heavyCloudCoverMin: night.cloudFloor.cloudCoverMin,
            usableScoreMax: night.ratingThresholds.fairMax
        )
    }

    private static func classify(
        _ rows: [HourlyRow],
        heavyCloudCoverMin: Int,
        usableScoreMax: Double
    ) -> Classification {
        guard let interval = preferredHeavyCloudInterval(
            in: rows,
            heavyCloudCoverMin: heavyCloudCoverMin,
            usableScoreMax: usableScoreMax
        ) else { return .none }

        switch (interval.hasUsableHoursBefore, interval.hasUsableHoursAfter) {
        case (true, false): return .lateHeavy
        case (false, true): return .earlyHeavy
        case (true, true): return .intermittentHeavy
        case (false, false): return .none
        }
    }

    /// A sustained heavy-cloud run plus the eligibility facts around it.
    private struct HeavyCloudInterval {
        let startIndex: Int
        let hourCount: Int
        let averageCloudCover: Double
        let hasUsableHoursBefore: Bool
        let hasUsableHoursAfter: Bool
    }

    /// Eligibility first — a run with no usable hour on either side is dropped
    /// before ranking — then longest run, then greatest average cloud cover,
    /// then earliest start index.
    private static func preferredHeavyCloudInterval(
        in rows: [HourlyRow],
        heavyCloudCoverMin: Int,
        usableScoreMax: Double
    ) -> HeavyCloudInterval? {
        sustainedHeavyCloudIntervals(
            in: rows,
            heavyCloudCoverMin: heavyCloudCoverMin,
            usableScoreMax: usableScoreMax
        )
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

    /// Runs of at least two heavy rows whose consecutive array neighbours are
    /// exactly one hour apart. A single heavy row never qualifies, and any
    /// non-heavy row or non-3600 second step — including a duplicate or
    /// backwards timestamp — closes the current run and may open a new one.
    private static func sustainedHeavyCloudIntervals(
        in rows: [HourlyRow],
        heavyCloudCoverMin: Int,
        usableScoreMax: Double
    ) -> [HeavyCloudInterval] {
        var intervals: [HeavyCloudInterval] = []
        var runStartIndex: Int?

        func appendInterval(endingAt endIndex: Int) {
            guard let startIndex = runStartIndex, endIndex - startIndex >= 1 else { return }

            let hasUsableHoursBefore = rows[..<startIndex].contains { $0.score < usableScoreMax }
            let hasUsableHoursAfter = rows[(endIndex + 1)...].contains { $0.score < usableScoreMax }
            let run = rows[startIndex...endIndex]
            intervals.append(
                HeavyCloudInterval(
                    startIndex: startIndex,
                    hourCount: run.count,
                    averageCloudCover: Double(run.map(\.cloudCover).reduce(0, +)) / Double(run.count),
                    hasUsableHoursBefore: hasUsableHoursBefore,
                    hasUsableHoursAfter: hasUsableHoursAfter
                )
            )
        }

        for index in rows.indices {
            let isHeavyCloud = rows[index].cloudCover >= heavyCloudCoverMin
            let followsPreviousHour = index > 0 &&
                rows[index].time.timeIntervalSince(rows[index - 1].time) == 3_600

            if isHeavyCloud && (runStartIndex == nil || followsPreviousHour) {
                runStartIndex = runStartIndex ?? index
            } else {
                appendInterval(endingAt: index - 1)
                runStartIndex = isHeavyCloud ? index : nil
            }
        }

        appendInterval(endingAt: rows.count - 1)
        return intervals
    }
}
