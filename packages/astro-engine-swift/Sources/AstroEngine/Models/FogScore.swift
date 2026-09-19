import Foundation

public struct FogScore: Sendable, Codable, Hashable {
    public let score: Int
    public let factors: [FogFactor]
    
    public init(score: Int, factors: [FogFactor]) {
        self.score = min(max(score, 0), 100)
        self.factors = factors
    }
    
    public enum FogFactor: String, CaseIterable, Sendable, Codable {
        case highHumidity = "High Humidity"
        case lowTempDewDiff = "Low Temp/Dew Point Difference"
        case lowVisibility = "Low Visibility"
        case highLowCloud = "High Low-Level Clouds"
        case lowWind = "Calm Winds"

        /// Language-neutral contract factor id. Display `rawValue` stays English.
        public var contractID: String {
            switch self {
            case .highHumidity: return "high_humidity"
            case .lowTempDewDiff: return "low_temp_dew_diff"
            case .lowVisibility: return "low_visibility"
            case .highLowCloud: return "high_low_cloud"
            case .lowWind: return "low_wind"
            }
        }
    }
}
