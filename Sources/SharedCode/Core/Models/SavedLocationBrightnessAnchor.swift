import Foundation

/// Immutable saved-location pin used for modeled-brightness metadata (no name).
///
/// Keyed by stable `SavedLocation.id`. Coordinates are the current pin location
/// for Phase 1 validity checks against a stored sample's lookup coordinates.
public struct SavedLocationBrightnessAnchor: Sendable, Hashable, Equatable {
    public let id: UUID
    public let latitude: Double
    public let longitude: Double

    public init(id: UUID, latitude: Double, longitude: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Returns nil when `CachedLocation.id` is missing (should not occur on the iOS publish path).
    public init?(cachedLocation: CachedLocation) {
        guard let id = cachedLocation.id else { return nil }
        self.id = id
        self.latitude = cachedLocation.latitude
        self.longitude = cachedLocation.longitude
    }
}
