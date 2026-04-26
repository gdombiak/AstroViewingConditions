import Foundation

#if os(iOS)
import SwiftData

@Model
public class SavedLocation {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double?
    public var isFavorite: Bool
    public var dateAdded: Date
    
    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        elevation: Double? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.isFavorite = false
        self.dateAdded = Date()
    }
}

extension SavedLocation {
    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}
#endif

public struct Coordinate: Sendable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double
    
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

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
    
#if os(iOS)
    public init(from savedLocation: SavedLocation) {
        self.id = savedLocation.id
        self.name = savedLocation.name
        self.latitude = savedLocation.latitude
        self.longitude = savedLocation.longitude
        self.elevation = savedLocation.elevation
    }
#endif
    
    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}

public struct SelectedLocation: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case currentGPS
        case saved
    }
    
    public var source: Source
    public var id: UUID?
    public var name: String
    public var latitude: Double
    public var longitude: Double
    
    public init(source: Source, id: UUID? = nil, name: String, latitude: Double, longitude: Double) {
        self.source = source
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}
