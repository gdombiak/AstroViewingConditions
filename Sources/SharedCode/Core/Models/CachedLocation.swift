import Foundation

public struct CachedLocation: Codable, Sendable {
    public let id: UUID?
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double?
    
    public init(id: UUID? = nil, name: String, latitude: Double, longitude: Double, elevation: Double? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    public func matches(latitude: Double, longitude: Double, tolerance: Double = 0.01) -> Bool {
        abs(self.latitude - latitude) <= tolerance &&
            abs(self.longitude - longitude) <= tolerance
    }
}
