import Foundation

public struct TargetScoringCalibration: Hashable, Sendable, Decodable {
    public let score: TargetScoringCalibrationScore
    public let altitude: TargetScoringCalibrationAltitude
    public let darkness: TargetScoringCalibrationDarkness
    public let weather: TargetScoringCalibrationWeather
    public let difficulty_weight: Double
    public let moon: TargetScoringCalibrationMoon
    public let target_bounds: TargetScoringCalibrationTargetBounds
}
public struct TargetScoringCalibrationScore: Hashable, Sendable, Decodable {
    public let min: Double
    public let max: Double
    public let round: String
}
public struct TargetScoringCalibrationAltitude: Hashable, Sendable, Decodable {
    public let reference_degrees: Double
    public let missing_max_altitude: Double
    public let weight: Double
}
public struct TargetScoringCalibrationDarkness: Hashable, Sendable, Decodable {
    public let deep_sky_and_meteor_shower: TargetScoringCalibrationDarknessDeepSkyAndMeteorShower
    public let satellite: TargetScoringCalibrationDarknessSatellite
    public let moon_and_planet: TargetScoringCalibrationDarknessMoonAndPlanet
}
public struct TargetScoringCalibrationDarknessDeepSkyAndMeteorShower: Hashable, Sendable, Decodable {
    public let base: Double
    public let overlap_weight: Double
}
public struct TargetScoringCalibrationDarknessSatellite: Hashable, Sendable, Decodable {
    public let base: Double
    public let overlap_weight: Double
}
public struct TargetScoringCalibrationDarknessMoonAndPlanet: Hashable, Sendable, Decodable {
    public let base: Double
    public let overlap_weight: Double
}
public struct TargetScoringCalibrationWeather: Hashable, Sendable, Decodable {
    public let weight: Double
    public let hourly_rating_seconds: Double
    public let overlap_score_divisor: Double
    public let cloud_cover_percent_divisor: Double
}
public struct TargetScoringCalibrationMoon: Hashable, Sendable, Decodable {
    public let zero_when_altitude_at_or_below_degrees: Double
    public let altitude_reference_degrees: Double
    public let interference: TargetScoringCalibrationMoonInterference
    public let ceilings: TargetScoringCalibrationMoonCeilings
    public let deep_sky_interference_sensitivity: TargetScoringCalibrationMoonDeepSkyInterferenceSensitivity
}
public struct TargetScoringCalibrationMoonInterference: Hashable, Sendable, Decodable {
    public let base: Double
    public let altitude_weight: Double
}
public struct TargetScoringCalibrationMoonCeilings: Hashable, Sendable, Decodable {
    public let galaxy: Double
    public let diffuse_nebula: Double
    public let globular_cluster: Double
    public let open_cluster: Double
    public let double_star: Double
    public let planetary_nebula: Double
    public let meteor_shower: Double
    public let planet: Double
    public let satellite: Double
    public let moon: Double
    public let unknown_deep_sky_object_type: Double
}
public struct TargetScoringCalibrationMoonDeepSkyInterferenceSensitivity: Hashable, Sendable, Decodable {
    public let `default`: Double
    public let missing_target_value_uses_default: Bool
    public let planetary_nebula_by_surface_brightness: TargetScoringCalibrationMoonDeepSkyInterferenceSensitivityPlanetaryNebulaBySurfaceBrightness
    public let non_planetary_nebula: Double
}
public struct TargetScoringCalibrationMoonDeepSkyInterferenceSensitivityPlanetaryNebulaBySurfaceBrightness: Hashable, Sendable, Decodable {
    public let high_surface_brightness_max: Double
    public let high_surface_brightness_sensitivity: Double
    public let low_surface_brightness_min: Double
    public let low_surface_brightness_sensitivity: Double
    public let mid_sensitivity: Double
}
public struct TargetScoringCalibrationTargetBounds: Hashable, Sendable, Decodable {
    public let difficulty_min: Double
    public let difficulty_max: Double
    public let sensitivity_min: Double
    public let sensitivity_max: Double
}

extension TargetScoringCalibration {
    func validate() throws {
        guard altitude.reference_degrees > 0, moon.altitude_reference_degrees > 0,
              weather.overlap_score_divisor > 0, weather.cloud_cover_percent_divisor > 0,
              weather.hourly_rating_seconds > 0, score.min == 0, score.max == 100,
              score.round == "half_away_from_zero",
              target_bounds.difficulty_min <= target_bounds.difficulty_max,
              target_bounds.sensitivity_min <= target_bounds.sensitivity_max else {
            throw EngineCalibrationError.invalid("target-scoring ranges or divisors")
        }
    }
}
