import Foundation

/// Explicit location identity for cross-surface observing-quality sample association.
///
/// Never infer saved vs Current Location from weather coordinates, names, or
/// presence/absence of a CachedLocation id.
public struct CrossSurfaceLocationContext: Sendable, Equatable, Hashable {
    public var source: SelectedLocation.Source
    public var latitude: Double
    public var longitude: Double
    public var savedLocationID: UUID?

    public init(
        source: SelectedLocation.Source,
        latitude: Double,
        longitude: Double,
        savedLocationID: UUID? = nil
    ) {
        self.source = source
        self.latitude = latitude
        self.longitude = longitude
        self.savedLocationID = savedLocationID
    }

    /// True when source/ID pairing is consistent (does not check coordinates).
    public var hasConsistentIdentity: Bool {
        switch source {
        case .saved:
            return savedLocationID != nil
        case .currentGPS:
            return savedLocationID == nil
        }
    }

    /// True when coordinates pass Phase 1 geographic domain checks.
    public var hasValidGeographicCoordinates: Bool {
        ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: latitude,
            longitude: longitude
        )
    }

    /// App/widget unresolved Current Location placeholder (not a Phase 1 geo rule).
    public var isUnresolvedCurrentLocationPlaceholder: Bool {
        source == .currentGPS && latitude == 0 && longitude == 0
    }

    /// Fully valid for brightness loading/resolution (identity + geo; not placeholder).
    public var isValidForBrightnessAssociation: Bool {
        hasConsistentIdentity
            && hasValidGeographicCoordinates
            && !isUnresolvedCurrentLocationPlaceholder
    }

    /// Maps a selected location using explicit source and ID rules.
    /// Returns nil when identity is inconsistent or coordinates are not Phase-1 geo-valid.
    /// Note: `(0,0)` currentGPS is geo-valid at Phase 1 but is the app placeholder — callers
    /// that load samples must still reject it via `isUnresolvedCurrentLocationPlaceholder`.
    public static func make(from selected: SelectedLocation) -> CrossSurfaceLocationContext? {
        // Authoritative source from SelectedLocation — never invent from id alone.
        let savedID: UUID?
        switch selected.source {
        case .saved:
            guard let id = selected.id else { return nil }
            savedID = id
        case .currentGPS:
            guard selected.id == nil else { return nil }
            savedID = nil
        }
        let context = CrossSurfaceLocationContext(
            source: selected.source,
            latitude: selected.latitude,
            longitude: selected.longitude,
            savedLocationID: savedID
        )
        guard context.hasConsistentIdentity else { return nil }
        guard context.hasValidGeographicCoordinates else { return nil }
        return context
    }
}
