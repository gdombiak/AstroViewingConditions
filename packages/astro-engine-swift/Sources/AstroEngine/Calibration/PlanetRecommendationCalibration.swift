import Foundation

/// Canonical constants of the dedicated production planet recommendation scorer.
/// Source of truth: contracts/data/calibration/planet-recommendation.json.
public struct PlanetRecommendationCalibration: Hashable, Sendable, Decodable {
    public let score: PlanetRecommendationCalibrationScore
    public let weights: PlanetRecommendationCalibrationWeights
    public let visibility: PlanetRecommendationCalibrationVisibility
    public let low_altitude: PlanetRecommendationCalibrationLowAltitude
    public let best_sample: PlanetRecommendationCalibrationBestSample
    public let convenience: PlanetRecommendationCalibrationConvenience
    public let weather: PlanetRecommendationCalibrationWeather
    public let venus_twilight: PlanetRecommendationCalibrationVenusTwilight
    public let reasons: PlanetRecommendationCalibrationReasons

    func validate() throws {
        guard score.min <= score.max, score.round == "half_away_from_zero" else {
            throw EngineCalibrationError.invalid("planet-recommendation score bounds")
        }
        guard weather.overlap_score_divisor > 0, weather.cloud_cover_percent_divisor > 0 else {
            throw EngineCalibrationError.invalid("planet-recommendation weather divisors")
        }
        guard visibility.altitude_normalization_degrees > 0,
              visibility.window_extension_seconds >= 0 else {
            throw EngineCalibrationError.invalid("planet-recommendation visibility bounds")
        }
        guard venus_twilight.altitude_span_degrees > 0,
              venus_twilight.elongation_span_degrees > 0,
              venus_twilight.useful_duration_seconds > 0 else {
            throw EngineCalibrationError.invalid("planet-recommendation venus twilight spans")
        }
    }
}

public struct PlanetRecommendationCalibrationScore: Hashable, Sendable, Decodable {
    public let min: Double
    public let max: Double
    public let round: String
}

public struct PlanetRecommendationCalibrationWeights: Hashable, Sendable, Decodable {
    public let altitude: Double
    public let weather: Double
    public let visibility: Double
    public let convenience: Double
}

public struct PlanetRecommendationCalibrationVisibility: Hashable, Sendable, Decodable {
    public let minimum_altitude_degrees: Double
    public let altitude_normalization_degrees: Double
    public let window_extension_seconds: Double
}

public struct PlanetRecommendationCalibrationLowAltitude: Hashable, Sendable, Decodable {
    public let below_degrees: Double
    public let penalty: Double
}

public struct PlanetRecommendationCalibrationBestSample: Hashable, Sendable, Decodable {
    public let altitude_weight: Double
    public let darkness_weight: Double
    public let convenience_weight: Double
    public let outside_darkness_quality: Double
}

public struct PlanetRecommendationCalibrationConvenience: Hashable, Sendable, Decodable {
    public let evening_lead_seconds: Double
    public let evening_trail_seconds: Double
    public let evening: Double
    public let late_night_lead_seconds: Double
    public let late_night: Double
    public let otherwise: Double
}

public struct PlanetRecommendationCalibrationWeather: Hashable, Sendable, Decodable {
    public let hourly_rating_seconds: Double
    public let overlap_score_divisor: Double
    public let cloud_cover_percent_divisor: Double
}

public struct PlanetRecommendationCalibrationVenusTwilight: Hashable, Sendable, Decodable {
    public let eligibility_window_seconds: Double
    public let useful_duration_seconds: Double
    public let altitude_span_degrees: Double
    public let elongation_offset_degrees: Double
    public let elongation_span_degrees: Double
    public let altitude_weight: Double
    public let duration_weight: Double
    public let elongation_weight: Double
}

public struct PlanetRecommendationCalibrationReasons: Hashable, Sendable, Decodable {
    public let high_altitude_at_or_above_degrees: Double
    public let low_altitude_below_degrees: Double
    public let darkness_overlap_at_or_above: Double
    public let convenient_at_or_above: Double
    public let late_or_early_at_or_below: Double
    public let good_weather_at_or_above: Double
    public let poor_weather_below: Double
}
