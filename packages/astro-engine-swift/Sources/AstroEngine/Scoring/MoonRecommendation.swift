import Foundation

/// Deterministic lunar recommendation facts.
///
/// Portable form of the private math in the production
/// `DefaultMoonTargetRecommendationProvider`. Deterministic: the observation is
/// injected, so no ephemeris provider runs here. Presentation copy (summary,
/// phase names, emoji) stays with the host.
///
/// Normative procedure: contracts/procedures/moon-recommendation.md.
public enum MoonRecommendation {
    /// Objective reason codes. Raw values are the production
    /// `TargetRecommendationReason` identifiers, not rendered English.
    public enum Reason: String, Sendable, Hashable, CaseIterable {
        case moonBelowUsefulWindow
        case newMoonDarkSky
        case excellentMoonCraterDetail
        case brightFullMoonDeepSkyImpact
        case moonVisibleUsefulWindow
        case moonSetsEarlyDarkSkyLater
        case poorWeather
    }

    public struct Window: Sendable, Hashable {
        public let start: Date
        public let end: Date
        public let bestTime: Date
        public let maxAltitude: Double?
        public let direction: String?
        public let azimuth: Double?

        public init(
            start: Date,
            end: Date,
            bestTime: Date,
            maxAltitude: Double?,
            direction: String?,
            azimuth: Double?
        ) {
            self.start = start
            self.end = end
            self.bestTime = bestTime
            self.maxAltitude = maxAltitude
            self.direction = direction
            self.azimuth = azimuth
        }
    }

    /// Objective score components. Not part of the capability transport; the
    /// host uses them for its existing validation logging.
    public struct Breakdown: Sendable, Hashable {
        public let phaseQuality: Double
        public let visibleFraction: Double
        public let weatherQuality: Double

        public init(phaseQuality: Double, visibleFraction: Double, weatherQuality: Double) {
            self.phaseQuality = phaseQuality
            self.visibleFraction = visibleFraction
            self.weatherQuality = weatherQuality
        }
    }

    public struct Result: Sendable, Hashable {
        public let score: Int
        public let window: Window
        public let reasons: [Reason]
        public let breakdown: Breakdown

        public init(score: Int, window: Window, reasons: [Reason], breakdown: Breakdown) {
            self.score = score
            self.window = window
            self.reasons = reasons
            self.breakdown = breakdown
        }
    }

    /// One hourly rating row. `score` is the production 0...2 hourly rating.
    public struct HourlyRating: Sendable, Hashable {
        public let time: Date
        public let score: Double

        public init(time: Date, score: Double) {
            self.time = time
            self.score = score
        }
    }

    /// `nil` means "no lunar recommendation tonight", exactly as the production
    /// provider returns `nil` when no sample inside the useful window is above
    /// the horizon.
    public static func evaluate(
        observation: MoonObservationData,
        nightStart: Date,
        nightEnd: Date,
        bestWindow: (start: Date, end: Date)?,
        cloudCoverScore: Double,
        hourlyRatings: [HourlyRating],
        calibration: MoonRecommendationCalibration = EngineCalibration.current.moonRecommendation
    ) -> Result? {
        let usefulStart = bestWindow?.start ?? nightStart
        let usefulEnd = bestWindow?.end ?? nightEnd
        let usefulSamples = observation.positionSamples.filter {
            $0.time >= usefulStart && $0.time <= usefulEnd
        }
        let visibleSamples = usefulSamples.filter {
            $0.altitude > calibration.visibility.above_altitude_degrees
        }
        guard !visibleSamples.isEmpty else { return nil }

        // Swift `max(by:)` keeps the earliest element of an altitude tie.
        let bestSample = visibleSamples.max { $0.altitude < $1.altitude }
        let window = visibilityWindow(
            usefulStart: usefulStart,
            usefulEnd: usefulEnd,
            visibleSamples: visibleSamples,
            bestSample: bestSample,
            calibration: calibration
        )
        let visibleFraction = visibleFraction(samples: usefulSamples, calibration: calibration)
        let weatherQuality = weatherQuality(
            in: window,
            cloudCoverScore: cloudCoverScore,
            hourlyRatings: hourlyRatings,
            calibration: calibration
        )
        return Result(
            score: score(
                observation: observation,
                visibleFraction: visibleFraction,
                weatherQuality: weatherQuality,
                calibration: calibration
            ),
            window: window,
            reasons: reasons(
                observation: observation,
                usefulStart: usefulStart,
                usefulEnd: usefulEnd,
                visibleSamples: visibleSamples,
                visibleFraction: visibleFraction,
                weatherQuality: weatherQuality,
                calibration: calibration
            ),
            breakdown: Breakdown(
                phaseQuality: phaseQuality(observation: observation, calibration: calibration),
                visibleFraction: visibleFraction,
                weatherQuality: weatherQuality
            )
        )
    }

    /// Sixteen-point compass code. Objective code, not presentation copy. This is
    /// deliberately *not* the eight-point `HorizontalCoordinates` code: the Moon
    /// path has always reported sixteen points with round-half-away-from-zero.
    public static func compassDirection(forAzimuth azimuth: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW",
        ]
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % directions.count
        return directions[index]
    }

    // MARK: - Components

    /// The `window_extension_seconds` extension is a fixed 1800 s literal in
    /// production and is independent of the observation sampling cadence.
    static func visibilityWindow(
        usefulStart: Date,
        usefulEnd: Date,
        visibleSamples: [MoonPositionSample],
        bestSample: MoonPositionSample?,
        calibration: MoonRecommendationCalibration
    ) -> Window {
        let extension_ = calibration.visibility.window_extension_seconds
        let bestTime = bestSample?.time
            ?? usefulStart.addingTimeInterval(usefulEnd.timeIntervalSince(usefulStart) / 2)
        let start = visibleSamples.first?.time ?? usefulStart
        let end = visibleSamples.last?.time.addingTimeInterval(extension_) ?? usefulEnd

        return Window(
            start: max(start, usefulStart),
            end: min(max(end, start.addingTimeInterval(extension_)), usefulEnd),
            bestTime: bestTime,
            maxAltitude: bestSample?.altitude,
            direction: bestSample?.azimuth.map(compassDirection(forAzimuth:)),
            azimuth: bestSample?.azimuth
        )
    }

    static func score(
        observation: MoonObservationData,
        visibleFraction: Double,
        weatherQuality: Double,
        calibration: MoonRecommendationCalibration
    ) -> Int {
        let weights = calibration.weights
        let rawScore = phaseQuality(observation: observation, calibration: calibration) * weights.phase
            + visibleFraction * weights.visibility
            + weatherQuality * weights.weather
        let cappedScore = observation.illumination <= calibration.near_new_moon.illumination_at_or_below_percent
            ? min(rawScore, calibration.near_new_moon.score_cap)
            : rawScore
        return Int(round(min(max(cappedScore, calibration.score.min), calibration.score.max)))
    }

    static func phaseQuality(
        observation: MoonObservationData,
        calibration: MoonRecommendationCalibration
    ) -> Double {
        let quality = calibration.phase_quality
        guard !isNearNewMoon(observation: observation, calibration: calibration) else {
            return calibration.near_new_moon.phase_quality
        }
        if quarterDistance(phase: observation.phase) <= quality.quarter_distance_at_or_below {
            return quality.quarter
        }
        if observation.illumination <= quality.crescent_illumination_at_or_below_percent {
            return quality.crescent
        }
        if observation.illumination >= quality.bright_illumination_at_or_above_percent {
            return quality.bright
        }
        return quality.otherwise
    }

    static func reasons(
        observation: MoonObservationData,
        usefulStart: Date,
        usefulEnd: Date,
        visibleSamples: [MoonPositionSample],
        visibleFraction: Double,
        weatherQuality: Double,
        calibration: MoonRecommendationCalibration
    ) -> [Reason] {
        var reasons: [Reason] = []
        let usefulMinimum = calibration.visibility.useful_fraction_at_or_above

        if visibleSamples.isEmpty || visibleFraction < usefulMinimum || observation.alwaysDown {
            reasons.append(.moonBelowUsefulWindow)
        }

        if isNearNewMoon(observation: observation, calibration: calibration) {
            reasons.append(.newMoonDarkSky)
        } else if quarterDistance(phase: observation.phase)
                    <= calibration.phase_quality.quarter_distance_at_or_below {
            reasons.append(.excellentMoonCraterDetail)
        } else if observation.illumination
                    >= calibration.phase_quality.bright_illumination_at_or_above_percent {
            reasons.append(.brightFullMoonDeepSkyImpact)
        } else if visibleFraction >= usefulMinimum {
            reasons.append(.moonVisibleUsefulWindow)
        }

        let setsEarly = calibration.moon_sets_early
        if let set = observation.set,
           set > usefulStart,
           set < usefulEnd.addingTimeInterval(-setsEarly.remaining_dark_seconds),
           observation.illumination >= setsEarly.illumination_at_or_above_percent {
            reasons.append(.moonSetsEarlyDarkSkyLater)
        }

        if weatherQuality < calibration.weather.poor_below {
            reasons.append(.poorWeather)
        }

        return reasons.isEmpty ? [.moonVisibleUsefulWindow] : reasons
    }

    /// Fraction of the samples inside the useful window that are above the horizon.
    static func visibleFraction(
        samples: [MoonPositionSample],
        calibration: MoonRecommendationCalibration
    ) -> Double {
        guard !samples.isEmpty else { return 0 }
        let visibleCount = samples.filter {
            $0.altitude > calibration.visibility.above_altitude_degrees
        }.count
        return Double(visibleCount) / Double(samples.count)
    }

    static func weatherQuality(
        in window: Window,
        cloudCoverScore: Double,
        hourlyRatings: [HourlyRating],
        calibration: MoonRecommendationCalibration
    ) -> Double {
        let weather = calibration.weather
        let overlapping = hourlyRatings.filter { rating in
            let ratingEnd = rating.time.addingTimeInterval(weather.hourly_rating_seconds)
            return ratingEnd > window.start && rating.time < window.end
        }

        guard !overlapping.isEmpty else {
            return 1 - min(max(cloudCoverScore / weather.cloud_cover_percent_divisor, 0), 1)
        }

        let averageScore = overlapping.map(\.score).reduce(0, +) / Double(overlapping.count)
        return 1 - min(max(averageScore / weather.overlap_score_divisor, 0), 1)
    }

    private static func isNearNewMoon(
        observation: MoonObservationData,
        calibration: MoonRecommendationCalibration
    ) -> Bool {
        let bounds = calibration.near_new_moon
        return observation.illumination <= bounds.illumination_at_or_below_percent
            || observation.phase <= bounds.phase_at_or_below
            || observation.phase >= bounds.phase_at_or_above
    }

    private static func quarterDistance(phase: Double) -> Double {
        min(abs(phase - 0.25), abs(phase - 0.75))
    }
}
