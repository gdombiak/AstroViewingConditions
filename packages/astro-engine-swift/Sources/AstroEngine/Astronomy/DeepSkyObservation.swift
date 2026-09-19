import Foundation

/// Deep-sky visible-run/window facts over an explicit interval.
///
/// This is the portable form of the production `DeepSkyTargetPositionProvider`.
/// Preserved quirks (inclusive threshold, interval-end reporting, earliest-wins
/// ties, degenerate-slope guard) are specified in
/// contracts/procedures/deep-sky-observation.md.
public enum DeepSkyObservation {
    public static let defaultMinimumAltitude: Double = 15
    public static let defaultSampleInterval: TimeInterval = 15 * 60

    public struct Sample: Sendable, Hashable {
        public let time: Date
        public let altitude: Double
        public let azimuth: Double

        public init(time: Date, altitude: Double, azimuth: Double) {
            self.time = time
            self.altitude = altitude
            self.azimuth = azimuth
        }
    }

    /// The objective fact set consumed upstream of target recommendation.
    public struct Window: Sendable, Hashable {
        public let start: Date
        public let end: Date
        public let bestTime: Date
        public let maxAltitude: Double
        public let azimuth: Double
        public let direction: String

        public init(
            start: Date,
            end: Date,
            bestTime: Date,
            maxAltitude: Double,
            azimuth: Double,
            direction: String
        ) {
            self.start = start
            self.end = end
            self.bestTime = bestTime
            self.maxAltitude = maxAltitude
            self.azimuth = azimuth
            self.direction = direction
        }
    }

    /// Inclusive-endpoint sampling by repeated addition of `sampleInterval`.
    /// An inverted interval yields no samples; a zero-length interval yields one.
    public static func samples(
        rightAscensionHours: Double,
        declinationDegrees: Double,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        start: Date,
        end: Date,
        sampleInterval: TimeInterval = defaultSampleInterval
    ) -> [Sample] {
        var samples: [Sample] = []
        var date = start
        while date <= end {
            let position = HorizontalCoordinates.position(
                rightAscensionHours: rightAscensionHours,
                declinationDegrees: declinationDegrees,
                latitudeDegrees: latitudeDegrees,
                longitudeDegrees: longitudeDegrees,
                at: date
            )
            samples.append(Sample(time: date, altitude: position.altitude, azimuth: position.azimuth))
            date = date.addingTimeInterval(sampleInterval)
        }
        return samples
    }

    /// One window per maximal contiguous run of samples at or above the threshold.
    public static func windows(
        from samples: [Sample],
        intervalStart: Date,
        intervalEnd: Date,
        minimumAltitude: Double = defaultMinimumAltitude
    ) -> [Window] {
        var windows: [Window] = []
        var runStartIndex: Int?

        for index in samples.indices {
            let isVisible = samples[index].altitude >= minimumAltitude
            if isVisible, runStartIndex == nil {
                runStartIndex = index
            }

            let runEnded = runStartIndex != nil && (!isVisible || index == samples.index(before: samples.endIndex))
            guard runEnded, let startIndex = runStartIndex else { continue }

            let endIndex = isVisible ? index : samples.index(before: index)
            let run = samples[startIndex...endIndex]
            guard let best = run.max(by: { $0.altitude < $1.altitude }) else { continue }

            let start = startIndex == samples.startIndex
                ? intervalStart
                : thresholdCrossing(
                    between: samples[startIndex - 1],
                    and: samples[startIndex],
                    minimumAltitude: minimumAltitude
                )
            let end = endIndex == samples.index(before: samples.endIndex)
                ? intervalEnd
                : thresholdCrossing(
                    between: samples[endIndex],
                    and: samples[endIndex + 1],
                    minimumAltitude: minimumAltitude
                )

            windows.append(Window(
                start: start,
                end: end,
                bestTime: best.time,
                maxAltitude: best.altitude,
                azimuth: best.azimuth,
                direction: HorizontalCoordinates.compassDirection(forAzimuth: best.azimuth)
            ))
            runStartIndex = nil
        }

        return windows
    }

    /// Sampling plus run detection for one fixed equatorial coordinate.
    public static func observe(
        rightAscensionHours: Double,
        declinationDegrees: Double,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        start: Date,
        end: Date,
        minimumAltitude: Double = defaultMinimumAltitude,
        sampleInterval: TimeInterval = defaultSampleInterval
    ) -> [Window] {
        let samples = samples(
            rightAscensionHours: rightAscensionHours,
            declinationDegrees: declinationDegrees,
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            start: start,
            end: end,
            sampleInterval: sampleInterval
        )
        return windows(
            from: samples,
            intervalStart: start,
            intervalEnd: end,
            minimumAltitude: minimumAltitude
        )
    }

    static func thresholdCrossing(
        between first: Sample,
        and second: Sample,
        minimumAltitude: Double
    ) -> Date {
        let altitudeChange = second.altitude - first.altitude
        guard abs(altitudeChange) > 0.0001 else { return first.time }
        let fraction = min(max((minimumAltitude - first.altitude) / altitudeChange, 0), 1)
        return first.time.addingTimeInterval(second.time.timeIntervalSince(first.time) * fraction)
    }
}
