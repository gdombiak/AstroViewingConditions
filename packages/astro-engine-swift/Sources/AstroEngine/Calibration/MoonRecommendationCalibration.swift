import Foundation

/// Canonical constants of the dedicated production Moon recommendation scorer.
/// Source of truth: contracts/data/calibration/moon-recommendation.json.
public struct MoonRecommendationCalibration: Hashable, Sendable, Decodable {
    public let score: MoonRecommendationCalibrationScore
    public let weights: MoonRecommendationCalibrationWeights
    public let near_new_moon: MoonRecommendationCalibrationNearNewMoon
    public let phase_quality: MoonRecommendationCalibrationPhaseQuality
    public let visibility: MoonRecommendationCalibrationVisibility
    public let weather: MoonRecommendationCalibrationWeather
    public let moon_sets_early: MoonRecommendationCalibrationMoonSetsEarly

    func validate() throws {
        guard score.min <= score.max, score.round == "half_away_from_zero" else {
            throw EngineCalibrationError.invalid("moon-recommendation score bounds")
        }
        guard weather.overlap_score_divisor > 0, weather.cloud_cover_percent_divisor > 0 else {
            throw EngineCalibrationError.invalid("moon-recommendation weather divisors")
        }
        guard visibility.window_extension_seconds >= 0 else {
            throw EngineCalibrationError.invalid("moon-recommendation window extension")
        }
    }
}

public struct MoonRecommendationCalibrationScore: Hashable, Sendable, Decodable {
    public let min: Double
    public let max: Double
    public let round: String
}

public struct MoonRecommendationCalibrationWeights: Hashable, Sendable, Decodable {
    public let phase: Double
    public let visibility: Double
    public let weather: Double
}

public struct MoonRecommendationCalibrationNearNewMoon: Hashable, Sendable, Decodable {
    public let illumination_at_or_below_percent: Int
    public let phase_at_or_below: Double
    public let phase_at_or_above: Double
    public let score_cap: Double
    public let phase_quality: Double
}

public struct MoonRecommendationCalibrationPhaseQuality: Hashable, Sendable, Decodable {
    public let quarter_distance_at_or_below: Double
    public let quarter: Double
    public let crescent_illumination_at_or_below_percent: Int
    public let crescent: Double
    public let bright_illumination_at_or_above_percent: Int
    public let bright: Double
    public let otherwise: Double
}

public struct MoonRecommendationCalibrationVisibility: Hashable, Sendable, Decodable {
    public let above_altitude_degrees: Double
    public let window_extension_seconds: Double
    public let useful_fraction_at_or_above: Double
}

public struct MoonRecommendationCalibrationWeather: Hashable, Sendable, Decodable {
    public let hourly_rating_seconds: Double
    public let overlap_score_divisor: Double
    public let cloud_cover_percent_divisor: Double
    public let poor_below: Double
}

public struct MoonRecommendationCalibrationMoonSetsEarly: Hashable, Sendable, Decodable {
    public let remaining_dark_seconds: Double
    public let illumination_at_or_above_percent: Int
}
