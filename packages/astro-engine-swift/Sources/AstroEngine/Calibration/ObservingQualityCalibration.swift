import Foundation

public struct ObservingQualityCalibration: Hashable, Sendable, Decodable {
    public let scoreMin: Int
    public let scoreMax: Int
    public let plausibleBrightness: PlausibleBrightness
    public let basePenaltyAnchors: [PenaltyAnchor]
    public let usabilityWeightAnchors: [UsabilityAnchor]

    enum CodingKeys: String, CodingKey {
        case scoreMin = "score_min"
        case scoreMax = "score_max"
        case plausibleBrightness = "plausible_brightness"
        case basePenaltyAnchors = "base_penalty_anchors"
        case usabilityWeightAnchors = "usability_weight_anchors"
    }

    public struct PlausibleBrightness: Hashable, Sendable, Decodable {
        public let min: Double
        public let max: Double
        public let unit: String
    }

    public struct PenaltyAnchor: Hashable, Sendable, Decodable {
        public let brightness: Double
        public let penalty: Double
    }

    public struct UsabilityAnchor: Hashable, Sendable, Decodable {
        public let score: Double
        public let weight: Double
    }

    func isBrightnessInPlausibleRange(_ brightness: Double) -> Bool {
        guard brightness.isFinite else { return false }
        return brightness >= plausibleBrightness.min && brightness <= plausibleBrightness.max
    }

    func validate() throws {
        if scoreMin > scoreMax {
            throw EngineCalibrationError.invalid("observing-quality score_min must be <= score_max")
        }
        if plausibleBrightness.min > plausibleBrightness.max {
            throw EngineCalibrationError.invalid("observing-quality plausible_brightness.min must be <= max")
        }
        if basePenaltyAnchors.isEmpty {
            throw EngineCalibrationError.invalid("observing-quality base_penalty_anchors must not be empty")
        }
        if usabilityWeightAnchors.isEmpty {
            throw EngineCalibrationError.invalid("observing-quality usability_weight_anchors must not be empty")
        }
        try requireStrictlyIncreasing(
            basePenaltyAnchors.map(\.brightness),
            label: "observing-quality base_penalty_anchors brightness"
        )
        try requireStrictlyIncreasing(
            usabilityWeightAnchors.map(\.score),
            label: "observing-quality usability_weight_anchors score"
        )
    }

    private func requireStrictlyIncreasing(_ values: [Double], label: String) throws {
        for index in 1..<values.count {
            if values[index] <= values[index - 1] {
                throw EngineCalibrationError.invalid("\(label) must be strictly increasing")
            }
        }
    }
}
