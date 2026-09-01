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
    }
}
