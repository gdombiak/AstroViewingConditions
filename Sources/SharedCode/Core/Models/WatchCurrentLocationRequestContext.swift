import Foundation

/// Transient Phase 4C request correlation for watch-supplied Current Location coordinates.
///
/// Used only on the live request/reply path. Not required for durable OQ document restore.
public struct WatchCurrentLocationRequestContext: Codable, Sendable, Equatable {
    public static let currentContextVersion = 1

    public var contextVersion: Int
    public var requestID: UUID
    /// Must be `.currentGPS` for a valid Phase 4C request.
    public var source: SelectedLocation.Source
    public var latitude: Double
    public var longitude: Double

    public init(
        contextVersion: Int = currentContextVersion,
        requestID: UUID = UUID(),
        source: SelectedLocation.Source = .currentGPS,
        latitude: Double,
        longitude: Double
    ) {
        self.contextVersion = contextVersion
        self.requestID = requestID
        self.source = source
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Structural validity for transport (not brightness association).
    public var isStructurallyValid: Bool {
        guard contextVersion > 0,
              contextVersion <= Self.currentContextVersion else {
            return false
        }
        guard source == .currentGPS else { return false }
        return ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: latitude,
            longitude: longitude
        )
            && !(latitude == 0 && longitude == 0)
            && latitude.isFinite
            && longitude.isFinite
    }

    public var asLocationContext: CrossSurfaceLocationContext {
        CrossSurfaceLocationContext(
            source: .currentGPS,
            latitude: latitude,
            longitude: longitude,
            savedLocationID: nil
        )
    }

    public var asCachedLocation: CachedLocation {
        CachedLocation(
            id: nil,
            name: "Current Location",
            latitude: latitude,
            longitude: longitude
        )
    }
}
