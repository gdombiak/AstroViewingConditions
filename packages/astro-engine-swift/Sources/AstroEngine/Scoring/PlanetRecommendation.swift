import Foundation

/// Deterministic planet recommendation facts.
///
/// Portable form of the private math in the production
/// `DefaultPlanetTargetRecommendationProvider`. Deterministic: the observation
/// samples are injected, so no ephemeris provider runs here. Presentation copy
/// (the English summary and its poor-conditions branches) stays with the host.
///
/// Normative procedure: contracts/procedures/planet-recommendation.md.
public enum PlanetRecommendation {
    /// Objective reason codes. Raw values are the production
    /// `TargetRecommendationReason` identifiers, not rendered English.
    public enum Reason: String, Sendable, Hashable, CaseIterable {
        case highAltitude
        case lowAltitude
        case astronomicalDarkness
        case convenientPlanetWindow
        case lateOrEarlyPlanetWindow
        case goodNightQuality
        case poorWeather
        case planetMoonlightResistant
    }

    /// One injected observation sample. `solarElongation` is optional because
    /// production reads it as `?? 0`; only the Venus twilight term consumes it.
    public struct Sample: Sendable, Hashable {
        public let time: Date
        public let altitude: Double
        public let azimuth: Double
        public let solarElongation: Double?

        public init(time: Date, altitude: Double, azimuth: Double, solarElongation: Double?) {
            self.time = time
            self.altitude = altitude
            self.azimuth = azimuth
            self.solarElongation = solarElongation
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

    /// The planet path always has a best visible sample, so unlike the lunar
    /// window every field here is present.
    public struct Window: Sendable, Hashable {
        public let start: Date
        public let end: Date
        public let bestTime: Date
        public let maxAltitude: Double
        public let direction: String
        public let azimuth: Double

        public init(
            start: Date,
            end: Date,
            bestTime: Date,
            maxAltitude: Double,
            direction: String,
            azimuth: Double
        ) {
            self.start = start
            self.end = end
            self.bestTime = bestTime
            self.maxAltitude = maxAltitude
            self.direction = direction
            self.azimuth = azimuth
        }

        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Objective score components. Not part of the capability transport; the
    /// host uses them for its existing validation logging.
    public struct Breakdown: Sendable, Hashable {
        public let altitudeQuality: Double
        public let weatherQuality: Double
        public let visibilityQuality: Double
        public let convenience: Double
        public let darknessOverlap: Double
        public let lowAltitudePenalty: Double

        public init(
            altitudeQuality: Double,
            weatherQuality: Double,
            visibilityQuality: Double,
            convenience: Double,
            darknessOverlap: Double,
            lowAltitudePenalty: Double
        ) {
            self.altitudeQuality = altitudeQuality
            self.weatherQuality = weatherQuality
            self.visibilityQuality = visibilityQuality
            self.convenience = convenience
            self.darknessOverlap = darknessOverlap
            self.lowAltitudePenalty = lowAltitudePenalty
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

    /// Interpolation guard from production `thresholdCrossing`. A structural
    /// numeric constant, not a product heuristic, so it is not calibrated.
    static let thresholdCrossingEpsilonDegrees = 0.0001

    /// `nil` means "no planet recommendation tonight", exactly as the production
    /// provider returns `nil` when no sample reaches the visible altitude.
    ///
    /// `targetID` is compared lowercased against `venus`, which is the only
    /// body with specialized twilight suitability in production.
    public static func evaluate(
        targetID: String,
        samples: [Sample],
        nightStart: Date,
        nightEnd: Date,
        cloudCoverScore: Double,
        hourlyRatings: [HourlyRating],
        calibration: PlanetRecommendationCalibration = EngineCalibration.current.planetRecommendation
    ) -> Result? {
        let visibleSamples = visibleSamples(samples, calibration: calibration)
        guard !visibleSamples.isEmpty,
              let bestSample = bestSample(
                from: visibleSamples,
                nightStart: nightStart,
                nightEnd: nightEnd,
                calibration: calibration
              ) else {
            return nil
        }

        let window = visibilityWindow(
            from: samples,
            visibleSamples: visibleSamples,
            bestSample: bestSample,
            calibration: calibration
        )
        let weatherQuality = weatherQuality(
            in: window,
            cloudCoverScore: cloudCoverScore,
            hourlyRatings: hourlyRatings,
            calibration: calibration
        )
        let darknessOverlap = overlapFraction(
            windowStart: window.start,
            windowEnd: window.end,
            darknessStart: nightStart,
            darknessEnd: nightEnd
        )
        let convenience = convenienceScore(
            for: bestSample.time,
            nightStart: nightStart,
            nightEnd: nightEnd,
            calibration: calibration
        )
        let visibilityQuality = visibilityQuality(
            targetID: targetID,
            bestSample: bestSample,
            window: window,
            darknessOverlap: darknessOverlap,
            nightStart: nightStart,
            nightEnd: nightEnd,
            calibration: calibration
        )
        let score = score(
            altitude: bestSample.altitude,
            weatherQuality: weatherQuality,
            visibilityQuality: visibilityQuality,
            convenience: convenience,
            calibration: calibration
        )
        let reasons = reasons(
            bestSample: bestSample,
            weatherQuality: weatherQuality,
            darknessOverlap: darknessOverlap,
            convenience: convenience,
            calibration: calibration
        )

        return Result(
            score: score,
            window: window,
            reasons: reasons,
            breakdown: Breakdown(
                altitudeQuality: altitudeQuality(bestSample.altitude, calibration: calibration),
                weatherQuality: weatherQuality,
                visibilityQuality: visibilityQuality,
                convenience: convenience,
                darknessOverlap: darknessOverlap,
                lowAltitudePenalty: lowAltitudePenalty(bestSample.altitude, calibration: calibration)
            )
        )
    }

    /// Sixteen-point compass code with round-half-away-from-zero. Objective
    /// code, not presentation copy; the host uppercases it for display, which is
    /// a no-op on these values.
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

    /// Inclusive `>=` visible-altitude filter. Exposed so the host validation
    /// summary keeps its pre-migration meaning.
    public static func visibleSamples(
        _ samples: [Sample],
        calibration: PlanetRecommendationCalibration = EngineCalibration.current.planetRecommendation
    ) -> [Sample] {
        samples.filter { $0.altitude >= calibration.visibility.minimum_altitude_degrees }
    }

    // MARK: - Components

    /// Swift `max(by:)` keeps the earliest element of a weighted-score tie.
    static func bestSample(
        from samples: [Sample],
        nightStart: Date,
        nightEnd: Date,
        calibration: PlanetRecommendationCalibration
    ) -> Sample? {
        samples.max { lhs, rhs in
            weightedScore(for: lhs, nightStart: nightStart, nightEnd: nightEnd, calibration: calibration)
                < weightedScore(for: rhs, nightStart: nightStart, nightEnd: nightEnd, calibration: calibration)
        }
    }

    static func weightedScore(
        for sample: Sample,
        nightStart: Date,
        nightEnd: Date,
        calibration: PlanetRecommendationCalibration
    ) -> Double {
        let weights = calibration.best_sample
        let altitude = altitudeQuality(sample.altitude, calibration: calibration)
        let darkness = sample.time >= nightStart && sample.time <= nightEnd
            ? 1.0
            : weights.outside_darkness_quality
        let convenience = convenienceScore(
            for: sample.time,
            nightStart: nightStart,
            nightEnd: nightEnd,
            calibration: calibration
        )
        return altitude * weights.altitude_weight
            + darkness * weights.darkness_weight
            + convenience * weights.convenience_weight
    }

    /// Interior crossings interpolate against the visible-altitude threshold.
    /// A run that ends on the final sample extends by the fixed
    /// `window_extension_seconds` literal, which production does *not* tie to
    /// the sampling cadence even though both are 900 s by default.
    static func visibilityWindow(
        from samples: [Sample],
        visibleSamples: [Sample],
        bestSample: Sample,
        calibration: PlanetRecommendationCalibration
    ) -> Window {
        let extension_ = calibration.visibility.window_extension_seconds
        let firstVisible = visibleSamples.first
        let lastVisible = visibleSamples.last
        let firstVisibleIndex = firstVisible.flatMap { sample in
            samples.firstIndex(where: { $0.time == sample.time })
        }
        let lastVisibleIndex = lastVisible.flatMap { sample in
            samples.lastIndex(where: { $0.time == sample.time })
        }

        let start: Date
        if let firstVisible, let firstVisibleIndex, firstVisibleIndex > samples.startIndex {
            start = thresholdCrossing(
                between: samples[firstVisibleIndex - 1],
                and: firstVisible,
                calibration: calibration
            )
        } else {
            start = firstVisible?.time ?? bestSample.time
        }

        let end: Date
        if let lastVisible, let lastVisibleIndex, lastVisibleIndex < samples.index(before: samples.endIndex) {
            end = thresholdCrossing(
                between: lastVisible,
                and: samples[lastVisibleIndex + 1],
                calibration: calibration
            )
        } else {
            end = lastVisible?.time.addingTimeInterval(extension_)
                ?? bestSample.time.addingTimeInterval(extension_)
        }

        return Window(
            start: start,
            end: end,
            bestTime: bestSample.time,
            maxAltitude: bestSample.altitude,
            direction: compassDirection(forAzimuth: bestSample.azimuth),
            azimuth: bestSample.azimuth
        )
    }

    static func thresholdCrossing(
        between first: Sample,
        and second: Sample,
        calibration: PlanetRecommendationCalibration
    ) -> Date {
        let altitudeChange = second.altitude - first.altitude
        guard abs(altitudeChange) > thresholdCrossingEpsilonDegrees else { return first.time }
        let fraction = min(
            max((calibration.visibility.minimum_altitude_degrees - first.altitude) / altitudeChange, 0),
            1
        )
        return first.time.addingTimeInterval(second.time.timeIntervalSince(first.time) * fraction)
    }

    static func altitudeQuality(
        _ altitude: Double,
        calibration: PlanetRecommendationCalibration
    ) -> Double {
        min(max(altitude / calibration.visibility.altitude_normalization_degrees, 0), 1)
    }

    static func lowAltitudePenalty(
        _ altitude: Double,
        calibration: PlanetRecommendationCalibration
    ) -> Double {
        altitude < calibration.low_altitude.below_degrees ? calibration.low_altitude.penalty : 0
    }

    static func score(
        altitude: Double,
        weatherQuality: Double,
        visibilityQuality: Double,
        convenience: Double,
        calibration: PlanetRecommendationCalibration
    ) -> Int {
        let weights = calibration.weights
        let rawScore = altitudeQuality(altitude, calibration: calibration) * weights.altitude
            + weatherQuality * weights.weather
            + visibilityQuality * weights.visibility
            + convenience * weights.convenience
            - lowAltitudePenalty(altitude, calibration: calibration)
        return Int(round(min(max(rawScore, calibration.score.min), calibration.score.max)))
    }

    /// Every body except Venus scores visibility as astronomical-darkness
    /// overlap. Venus can take the better of that and its twilight suitability.
    static func visibilityQuality(
        targetID: String,
        bestSample: Sample,
        window: Window,
        darknessOverlap: Double,
        nightStart: Date,
        nightEnd: Date,
        calibration: PlanetRecommendationCalibration
    ) -> Double {
        guard targetID.lowercased() == "venus" else { return darknessOverlap }

        return max(
            darknessOverlap,
            venusTwilightSuitability(
                bestSample: bestSample,
                window: window,
                nightStart: nightStart,
                nightEnd: nightEnd,
                calibration: calibration
            )
        )
    }

    static func venusTwilightSuitability(
        bestSample: Sample,
        window: Window,
        nightStart: Date,
        nightEnd: Date,
        calibration: PlanetRecommendationCalibration
    ) -> Double {
        let twilight = calibration.venus_twilight
        let isEveningTwilight = bestSample.time < nightStart
            && window.end > nightStart.addingTimeInterval(-twilight.eligibility_window_seconds)
        let isMorningTwilight = bestSample.time > nightEnd
            && window.start < nightEnd.addingTimeInterval(twilight.eligibility_window_seconds)
        guard isEveningTwilight || isMorningTwilight else { return 0 }

        let altitudeQuality = min(max(
            (bestSample.altitude - calibration.visibility.minimum_altitude_degrees)
                / twilight.altitude_span_degrees,
            0
        ), 1)
        let durationQuality = min(max(window.duration / twilight.useful_duration_seconds, 0), 1)
        let elongationQuality = min(max(
            ((bestSample.solarElongation ?? 0) - twilight.elongation_offset_degrees)
                / twilight.elongation_span_degrees,
            0
        ), 1)

        return altitudeQuality * twilight.altitude_weight
            + durationQuality * twilight.duration_weight
            + elongationQuality * twilight.elongation_weight
    }

    /// Reason order is the production order and is part of the contract.
    /// `astronomicalDarkness` keys on the darkness overlap, not on the Venus
    /// twilight-adjusted visibility quality.
    static func reasons(
        bestSample: Sample,
        weatherQuality: Double,
        darknessOverlap: Double,
        convenience: Double,
        calibration: PlanetRecommendationCalibration
    ) -> [Reason] {
        let bounds = calibration.reasons
        var reasons: [Reason] = []

        if bestSample.altitude >= bounds.high_altitude_at_or_above_degrees {
            reasons.append(.highAltitude)
        } else if bestSample.altitude < bounds.low_altitude_below_degrees {
            reasons.append(.lowAltitude)
        }

        if darknessOverlap >= bounds.darkness_overlap_at_or_above {
            reasons.append(.astronomicalDarkness)
        }

        if convenience >= bounds.convenient_at_or_above {
            reasons.append(.convenientPlanetWindow)
        } else if convenience <= bounds.late_or_early_at_or_below {
            reasons.append(.lateOrEarlyPlanetWindow)
        }

        if weatherQuality >= bounds.good_weather_at_or_above {
            reasons.append(.goodNightQuality)
        } else if weatherQuality < bounds.poor_weather_below {
            reasons.append(.poorWeather)
        }

        reasons.append(.planetMoonlightResistant)
        return reasons
    }

    /// The evening band is tested first, so an instant inside both the evening
    /// band and the late-night band scores as evening.
    static func convenienceScore(
        for time: Date,
        nightStart: Date,
        nightEnd: Date,
        calibration: PlanetRecommendationCalibration
    ) -> Double {
        let bounds = calibration.convenience
        let eveningStart = nightStart.addingTimeInterval(-bounds.evening_lead_seconds)
        let eveningEnd = nightStart.addingTimeInterval(bounds.evening_trail_seconds)
        if time >= eveningStart && time <= eveningEnd {
            return bounds.evening
        }

        let lateNightStart = nightEnd.addingTimeInterval(-bounds.late_night_lead_seconds)
        if time >= lateNightStart {
            return bounds.late_night
        }

        return bounds.otherwise
    }

    static func weatherQuality(
        in window: Window,
        cloudCoverScore: Double,
        hourlyRatings: [HourlyRating],
        calibration: PlanetRecommendationCalibration
    ) -> Double {
        let weather = calibration.weather
        let overlappingRatings = hourlyRatings.filter { rating in
            let ratingEnd = rating.time.addingTimeInterval(weather.hourly_rating_seconds)
            return ratingEnd > window.start && rating.time < window.end
        }

        guard !overlappingRatings.isEmpty else {
            return 1 - min(max(cloudCoverScore / weather.cloud_cover_percent_divisor, 0), 1)
        }

        let averageScore = overlappingRatings.map(\.score).reduce(0, +) / Double(overlappingRatings.count)
        return 1 - min(max(averageScore / weather.overlap_score_divisor, 0), 1)
    }

    static func overlapFraction(
        windowStart: Date,
        windowEnd: Date,
        darknessStart: Date,
        darknessEnd: Date
    ) -> Double {
        guard windowEnd > windowStart else { return 0 }

        let overlapStart = max(windowStart, darknessStart)
        let overlapEnd = min(windowEnd, darknessEnd)
        guard overlapEnd > overlapStart else { return 0 }

        return overlapEnd.timeIntervalSince(overlapStart) / windowEnd.timeIntervalSince(windowStart)
    }
}
