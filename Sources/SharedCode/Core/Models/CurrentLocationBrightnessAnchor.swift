import Foundation

/// Immutable Current Location pin used for modeled-brightness metadata.
///
/// Not associated with a `SavedLocation.id`. Validity uses Phase 1 coordinate
/// rules (1000 m haversine, dataset identity) with `savedLocationID == nil`.
public struct CurrentLocationBrightnessAnchor: Sendable, Hashable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
