import Foundation

public struct FogCalibration: Hashable, Sendable, Decodable {
    public let scoreMin: Int
    public let scoreMax: Int
    public let humidity: Humidity
    public let dewSpread: DewSpread
    public let visibility: Visibility
    public let lowCloud: LowCloud
    public let wind: Wind

    enum CodingKeys: String, CodingKey {
        case scoreMin = "score_min"
        case scoreMax = "score_max"
        case humidity
        case dewSpread = "dew_spread"
        case visibility
        case lowCloud = "low_cloud"
        case wind
    }

    public struct Humidity: Hashable, Sendable, Decodable {
        public let minPercent: Int
        public let spanPercent: Double
        public let maxPoints: Double

        enum CodingKeys: String, CodingKey {
            case minPercent = "min_percent"
            case spanPercent = "span_percent"
            case maxPoints = "max_points"
        }
    }

    public struct DewSpread: Hashable, Sendable, Decodable {
        public let maxCelsius: Double
        public let maxPoints: Double

        enum CodingKeys: String, CodingKey {
            case maxCelsius = "max_celsius"
            case maxPoints = "max_points"
        }
    }

    public struct Visibility: Hashable, Sendable, Decodable {
        public let maxMeters: Double
        public let maxPoints: Double

        enum CodingKeys: String, CodingKey {
            case maxMeters = "max_meters"
            case maxPoints = "max_points"
        }
    }

    public struct LowCloud: Hashable, Sendable, Decodable {
        public let minPercent: Int
        public let spanPercent: Double
        public let maxPoints: Double

        enum CodingKeys: String, CodingKey {
            case minPercent = "min_percent"
            case spanPercent = "span_percent"
            case maxPoints = "max_points"
        }
    }

    public struct Wind: Hashable, Sendable, Decodable {
        public let maxMetersPerSecond: Double
        public let maxPoints: Double

        enum CodingKeys: String, CodingKey {
            case maxMetersPerSecond = "max_meters_per_second"
            case maxPoints = "max_points"
        }
    }

    func validate() throws {
        if scoreMin > scoreMax {
            throw EngineCalibrationError.invalid("fog score_min must be <= score_max")
        }
        if humidity.spanPercent == 0 {
            throw EngineCalibrationError.invalid("fog humidity.span_percent must be non-zero")
        }
        if dewSpread.maxCelsius == 0 {
            throw EngineCalibrationError.invalid("fog dew_spread.max_celsius must be non-zero")
        }
        if visibility.maxMeters == 0 {
            throw EngineCalibrationError.invalid("fog visibility.max_meters must be non-zero")
        }
        if lowCloud.spanPercent == 0 {
            throw EngineCalibrationError.invalid("fog low_cloud.span_percent must be non-zero")
        }
        if wind.maxMetersPerSecond == 0 {
            throw EngineCalibrationError.invalid("fog wind.max_meters_per_second must be non-zero")
        }
    }
}
