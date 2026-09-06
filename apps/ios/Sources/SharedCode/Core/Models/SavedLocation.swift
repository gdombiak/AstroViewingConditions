import Foundation
import AstroEngine

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
    /// Nil for locations created before manual ordering was introduced.
    public var sortPosition: Int?
    
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
        self.sortPosition = nil
    }
}

extension SavedLocation {
    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Manual positions sort first. Unpositioned records retain the app's
    /// previous newest-first ordering and are placed above positioned records,
    /// which also keeps newly added locations at the top of the list.
    public static func ordered(_ locations: [SavedLocation]) -> [SavedLocation] {
        locations.sorted { lhs, rhs in
            switch (lhs.sortPosition, rhs.sortPosition) {
            case let (lhsPosition?, rhsPosition?):
                if lhsPosition != rhsPosition {
                    return lhsPosition < rhsPosition
                }
                return lhs.dateAdded > rhs.dateAdded
            case (nil, nil):
                return lhs.dateAdded > rhs.dateAdded
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            }
        }
    }
}

extension CachedLocation {
    public init(from savedLocation: SavedLocation) {
        self.init(
            id: savedLocation.id,
            name: savedLocation.name,
            latitude: savedLocation.latitude,
            longitude: savedLocation.longitude,
            elevation: savedLocation.elevation
        )
    }
}
#endif

public struct SelectedLocation: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable, Hashable {
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
