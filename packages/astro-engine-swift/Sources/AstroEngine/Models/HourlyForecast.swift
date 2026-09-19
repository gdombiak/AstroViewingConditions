import Foundation

public struct HourlyForecast: Identifiable, Sendable, Codable {
    public let id: UUID
    public let time: Date
    public let cloudCover: Int
    public let humidity: Int
    public let windSpeed: Double
    public let windDirection: Int
    public let temperature: Double
    public let dewPoint: Double?
    public let visibility: Double?
    public let lowCloudCover: Int?
    public let midCloudCover: Int?
    public let highCloudCover: Int?
    public let windSpeed200hPa: Double?
    
    public init(
        id: UUID = UUID(),
        time: Date,
        cloudCover: Int,
        humidity: Int,
        windSpeed: Double,
        windDirection: Int,
        temperature: Double,
        dewPoint: Double? = nil,
        visibility: Double? = nil,
        lowCloudCover: Int? = nil,
        midCloudCover: Int? = nil,
        highCloudCover: Int? = nil,
        windSpeed200hPa: Double? = nil
    ) {
        self.id = id
        self.time = time
        self.cloudCover = cloudCover
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.temperature = temperature
        self.dewPoint = dewPoint
        self.visibility = visibility
        self.lowCloudCover = lowCloudCover
        self.midCloudCover = midCloudCover
        self.highCloudCover = highCloudCover
        self.windSpeed200hPa = windSpeed200hPa
    }
}
