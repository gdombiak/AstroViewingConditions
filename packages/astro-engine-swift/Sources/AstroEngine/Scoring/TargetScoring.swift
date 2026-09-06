import Foundation

/// Generic scoring only. Hosts supply windows and weather facts; no astronomy is sampled.
public enum FrozenTargetType: String, CaseIterable, Sendable {
    case deepSky, meteorShower, satellite, moon, planet
}

public struct TargetScoreComponents: Sendable {
    public let score: Int
    public let altitude: Double
    public let darknessOverlap: Double
    public let weatherQuality: Double
    public let moonPenalty: Double
    public let difficultyPenalty: Double
    public let altitudeComponent: Double
    public let darknessComponent: Double
    public let weatherComponent: Double
    public let rawScore: Double
}

public enum TargetScoring {
    public static func score(
        type: FrozenTargetType, objectType: DeepSkyObjectType?, difficulty: Double,
        sensitivity: Double?, maxAltitude: Double?, start: Date, end: Date,
        darknessStart: Date, darknessEnd: Date, cloudCoverScore: Double,
        hourlyRatings: [(time: Date, score: Double)], moonAltitude: Double,
        moonIllumination: Double, calibration c: TargetScoringCalibration = EngineCalibration.current.targetScoring
    ) -> TargetScoreComponents {
        let altitude = clamp((maxAltitude ?? c.altitude.missing_max_altitude) / c.altitude.reference_degrees)
        let overlapStart = max(start, darknessStart)
        let overlapEnd = min(end, darknessEnd)
        let overlap = end > start && overlapEnd > overlapStart
            ? overlapEnd.timeIntervalSince(overlapStart) / end.timeIntervalSince(start) : 0
        let hours = hourlyRatings.filter {
            $0.time.addingTimeInterval(c.weather.hourly_rating_seconds) > start && $0.time < end
        }
        let weather = hours.isEmpty
            ? 1 - clamp(cloudCoverScore / c.weather.cloud_cover_percent_divisor)
            : 1 - clamp(hours.map(\.score).reduce(0, +) / Double(hours.count) / c.weather.overlap_score_divisor)
        let darkness: Double
        switch type {
        case .deepSky, .meteorShower:
            darkness = c.darkness.deep_sky_and_meteor_shower.base + overlap * c.darkness.deep_sky_and_meteor_shower.overlap_weight
        case .satellite:
            darkness = c.darkness.satellite.base + overlap * c.darkness.satellite.overlap_weight
        case .moon, .planet:
            darkness = c.darkness.moon_and_planet.base + overlap * c.darkness.moon_and_planet.overlap_weight
        }
        let ceiling: Double
        switch type {
        case .deepSky:
            switch objectType {
            case .galaxy: ceiling = c.moon.ceilings.galaxy
            case .diffuseNebula: ceiling = c.moon.ceilings.diffuse_nebula
            case .globularCluster: ceiling = c.moon.ceilings.globular_cluster
            case .openCluster: ceiling = c.moon.ceilings.open_cluster
            case .doubleStar: ceiling = c.moon.ceilings.double_star
            case .planetaryNebula: ceiling = c.moon.ceilings.planetary_nebula
            case nil: ceiling = c.moon.ceilings.unknown_deep_sky_object_type
            }
        case .meteorShower: ceiling = c.moon.ceilings.meteor_shower
        case .planet: ceiling = c.moon.ceilings.planet
        case .satellite: ceiling = c.moon.ceilings.satellite
        case .moon: ceiling = c.moon.ceilings.moon
        }
        let b = c.target_bounds
        let sensitivity = min(max(sensitivity ?? c.moon.deep_sky_interference_sensitivity.default, b.sensitivity_min), b.sensitivity_max)
        let interference = clamp(moonIllumination / 100) * (c.moon.interference.base
            + clamp(moonAltitude / c.moon.altitude_reference_degrees) * c.moon.interference.altitude_weight)
        let moonPenalty = moonAltitude <= c.moon.zero_when_altitude_at_or_below_degrees ? 0
            : interference * ceiling * (type == .deepSky ? sensitivity : 1)
        let difficultyPenalty = min(max(difficulty, b.difficulty_min), b.difficulty_max) * c.difficulty_weight
        let altitudeComponent = altitude * c.altitude.weight
        let weatherComponent = weather * c.weather.weight
        let raw = altitudeComponent + darkness + weatherComponent - moonPenalty - difficultyPenalty
        return TargetScoreComponents(score: Int(min(max(raw, c.score.min), c.score.max).rounded(.toNearestOrAwayFromZero)),
            altitude: altitude, darknessOverlap: overlap, weatherQuality: weather, moonPenalty: moonPenalty,
            difficultyPenalty: difficultyPenalty, altitudeComponent: altitudeComponent,
            darknessComponent: darkness, weatherComponent: weatherComponent, rawScore: raw)
    }

    /// Complete ties preserve input order (the production stable sort behavior).
    public static func rankedIndices(scores: [Int], bestTimes: [Date], limit: Int) -> [Int] {
        scores.indices.sorted {
            if scores[$0] != scores[$1] { return scores[$0] > scores[$1] }
            if bestTimes[$0] != bestTimes[$1] { return bestTimes[$0] < bestTimes[$1] }
            return $0 < $1
        }.prefix(max(0, limit)).map { $0 }
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
