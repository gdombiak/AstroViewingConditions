import Foundation

public struct NightQualityCalibration: Hashable, Sendable, Decodable {
    public let ratingThresholds: RatingThresholds
    public let cloudFloor: CloudFloor
    public let trend: Trend
    public let cloudCoverScoreTable: [IntUpperBoundScoreBucket]
    public let moonIlluminationBuckets: [IntUpperBoundScoreBucket]
    public let windPenaltyTable: [UpperBoundScoreBucket]
    public let fogPenaltyDivisor: Double
    public let weightRegimes: WeightRegimes
    public let publicScore: PublicScore

    enum CodingKeys: String, CodingKey {
        case ratingThresholds = "rating_thresholds"
        case cloudFloor = "cloud_floor"
        case trend
        case cloudCoverScoreTable = "cloud_cover_score_table"
        case moonIlluminationBuckets = "moon_illumination_buckets"
        case windPenaltyTable = "wind_penalty_table"
        case fogPenaltyDivisor = "fog_penalty_divisor"
        case weightRegimes = "weight_regimes"
        case publicScore = "public_score"
    }

    public struct RatingThresholds: Hashable, Sendable, Decodable {
        public let excellentMax: Double
        public let goodMax: Double
        public let fairMax: Double

        enum CodingKeys: String, CodingKey {
            case excellentMax = "excellent_max"
            case goodMax = "good_max"
            case fairMax = "fair_max"
        }
    }

    public struct CloudFloor: Hashable, Sendable, Decodable {
        public let cloudCoverMin: Int
        public let fairMax: Double

        enum CodingKeys: String, CodingKey {
            case cloudCoverMin = "cloud_cover_min"
            case fairMax = "fair_max"
        }
    }

    public struct Trend: Hashable, Sendable, Decodable {
        public let minHours: Int
        public let diffThreshold: Double

        enum CodingKeys: String, CodingKey {
            case minHours = "min_hours"
            case diffThreshold = "diff_threshold"
        }
    }

    public struct WeightRegimes: Hashable, Sendable, Decodable {
        public let transparencyAndSeeing: WeightedComponents
        public let transparencyOnly: WeightedComponents
        public let seeingOnly: WeightedComponents
        public let neither: WeightedComponents

        enum CodingKeys: String, CodingKey {
            case transparencyAndSeeing = "transparency_and_seeing"
            case transparencyOnly = "transparency_only"
            case seeingOnly = "seeing_only"
            case neither
        }
    }

    public struct WeightedComponents: Hashable, Sendable, Decodable {
        public let transparency: Double?
        public let seeing: Double?
        public let cloud: Double?
        public let fog: Double
        public let moon: Double
        public let wind: Double
    }

    public struct PublicScore: Hashable, Sendable, Decodable {
        public let excellentBase: Int
        public let goodBase: Int
        public let fairBase: Int
        public let poorBase: Int
        public let adjustmentScale: Double
        public let scoreMin: Int
        public let scoreMax: Int

        enum CodingKeys: String, CodingKey {
            case excellentBase = "excellent_base"
            case goodBase = "good_base"
            case fairBase = "fair_base"
            case poorBase = "poor_base"
            case adjustmentScale = "adjustment_scale"
            case scoreMin = "score_min"
            case scoreMax = "score_max"
        }
    }

    func validate() throws {
        if ratingThresholds.excellentMax > ratingThresholds.goodMax
            || ratingThresholds.goodMax > ratingThresholds.fairMax {
            throw EngineCalibrationError.invalid(
                "night-quality rating_thresholds must be ordered excellent_max <= good_max <= fair_max"
            )
        }
        if cloudCoverScoreTable.isEmpty {
            throw EngineCalibrationError.invalid("night-quality cloud_cover_score_table must not be empty")
        }
        if moonIlluminationBuckets.isEmpty {
            throw EngineCalibrationError.invalid("night-quality moon_illumination_buckets must not be empty")
        }
        if windPenaltyTable.isEmpty {
            throw EngineCalibrationError.invalid("night-quality wind_penalty_table must not be empty")
        }
        if fogPenaltyDivisor == 0 {
            throw EngineCalibrationError.invalid("night-quality fog_penalty_divisor must be non-zero")
        }
        if trend.minHours < 0 {
            throw EngineCalibrationError.invalid("night-quality trend.min_hours must be non-negative")
        }
        try require(weightRegimes.transparencyAndSeeing.transparency, "weight_regimes.transparency_and_seeing.transparency")
        try require(weightRegimes.transparencyAndSeeing.seeing, "weight_regimes.transparency_and_seeing.seeing")
        try require(weightRegimes.transparencyOnly.transparency, "weight_regimes.transparency_only.transparency")
        try require(weightRegimes.seeingOnly.cloud, "weight_regimes.seeing_only.cloud")
        try require(weightRegimes.seeingOnly.seeing, "weight_regimes.seeing_only.seeing")
        try require(weightRegimes.neither.cloud, "weight_regimes.neither.cloud")
        if publicScore.scoreMin > publicScore.scoreMax {
            throw EngineCalibrationError.invalid("night-quality public_score.score_min must be <= score_max")
        }
    }

    private func require(_ value: Double?, _ label: String) throws {
        if value == nil {
            throw EngineCalibrationError.invalid("night-quality \(label) is required")
        }
    }
}
