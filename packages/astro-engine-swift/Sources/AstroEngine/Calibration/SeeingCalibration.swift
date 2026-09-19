import Foundation

public struct SeeingCalibration: Hashable, Sendable, Decodable {
    public let penaltyMin: Double
    public let penaltyMax: Double
    public let temperatureDeltaCelsius: [UpperBoundScoreBucket]
    public let upperWind200hpa: [UpperBoundScoreBucket]

    enum CodingKeys: String, CodingKey {
        case penaltyMin = "penalty_min"
        case penaltyMax = "penalty_max"
        case temperatureDeltaCelsius = "temperature_delta_celsius"
        case upperWind200hpa = "upper_wind_200hpa"
    }

    func validate() throws {
        if penaltyMin > penaltyMax {
            throw EngineCalibrationError.invalid("seeing penalty_min must be <= penalty_max")
        }
        if temperatureDeltaCelsius.isEmpty {
            throw EngineCalibrationError.invalid("seeing temperature_delta_celsius must not be empty")
        }
        if upperWind200hpa.isEmpty {
            throw EngineCalibrationError.invalid("seeing upper_wind_200hpa must not be empty")
        }
    }
}
