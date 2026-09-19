import Foundation

public struct TransparencyCalibration: Hashable, Sendable, Decodable {
    public let penaltyMin: Double
    public let penaltyMax: Double
    public let layerWeights: LayerWeights
    public let combineWeights: CombineWeights
    public let cloudCover: [UpperBoundScoreBucket]
    public let visibilityMeters: [LowerBoundScoreBucket]

    enum CodingKeys: String, CodingKey {
        case penaltyMin = "penalty_min"
        case penaltyMax = "penalty_max"
        case layerWeights = "layer_weights"
        case combineWeights = "combine_weights"
        case cloudCover = "cloud_cover"
        case visibilityMeters = "visibility_meters"
    }

    public struct LayerWeights: Hashable, Sendable, Decodable {
        public let low: Double
        public let mid: Double
        public let high: Double
    }

    public struct CombineWeights: Hashable, Sendable, Decodable {
        public let cloud: Double
        public let visibility: Double
    }

    func validate() throws {
        if penaltyMin > penaltyMax {
            throw EngineCalibrationError.invalid("transparency penalty_min must be <= penalty_max")
        }
        if cloudCover.isEmpty {
            throw EngineCalibrationError.invalid("transparency cloud_cover must not be empty")
        }
        if visibilityMeters.isEmpty {
            throw EngineCalibrationError.invalid("transparency visibility_meters must not be empty")
        }
    }
}
