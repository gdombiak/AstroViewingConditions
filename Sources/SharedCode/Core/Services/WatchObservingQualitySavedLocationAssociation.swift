import Foundation

/// Strict Phase 4B saved-location identity for conditions ↔ selection ↔ transport association.
///
/// Requires **both** matching non-nil saved IDs **and** coordinates within the narrow
/// widget identity tolerance. Does **not** use the Phase 1 1000 m sample-validity radius.
///
/// Distinct from `WidgetLocationIdentity.matches`, which treats equal IDs as sufficient
/// and ignores coordinate drift (appropriate for some widget cache paths, not Phase 4B).
public enum WatchObservingQualitySavedLocationAssociation: Sendable {
    /// Same narrow tolerance as `WidgetLocationIdentity.coordinateTolerance` (1e-5°).
    public static let coordinateTolerance = WidgetLocationIdentity.coordinateTolerance

    /// True when both sides are saved-identity pairs with equal IDs and agreeing coordinates.
    public static func matches(
        savedLocationID: UUID?,
        latitude: Double,
        longitude: Double,
        otherSavedLocationID: UUID?,
        otherLatitude: Double,
        otherLongitude: Double
    ) -> Bool {
        guard let savedLocationID, let otherSavedLocationID,
              savedLocationID == otherSavedLocationID else {
            return false
        }
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: latitude,
            longitude: longitude
        ) else {
            return false
        }
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: otherLatitude,
            longitude: otherLongitude
        ) else {
            return false
        }
        return abs(latitude - otherLatitude) <= coordinateTolerance
            && abs(longitude - otherLongitude) <= coordinateTolerance
    }

    /// Selected saved location versus a coordinate + optional conditions location id.
    public static func matches(
        selected: SelectedLocation,
        conditionsLocation: CachedLocation
    ) -> Bool {
        guard selected.source == .saved else { return false }
        return matches(
            savedLocationID: selected.id,
            latitude: selected.latitude,
            longitude: selected.longitude,
            otherSavedLocationID: conditionsLocation.id,
            otherLatitude: conditionsLocation.latitude,
            otherLongitude: conditionsLocation.longitude
        )
    }

    /// Selected saved location versus explicit cross-surface context.
    public static func matches(
        selected: SelectedLocation,
        context: CrossSurfaceLocationContext
    ) -> Bool {
        guard selected.source == .saved, context.source == .saved else { return false }
        return matches(
            savedLocationID: selected.id,
            latitude: selected.latitude,
            longitude: selected.longitude,
            otherSavedLocationID: context.savedLocationID,
            otherLatitude: context.latitude,
            otherLongitude: context.longitude
        )
    }

    /// Cross-surface context versus conditions location.
    public static func matches(
        context: CrossSurfaceLocationContext,
        conditionsLocation: CachedLocation
    ) -> Bool {
        guard context.source == .saved else { return false }
        return matches(
            savedLocationID: context.savedLocationID,
            latitude: context.latitude,
            longitude: context.longitude,
            otherSavedLocationID: conditionsLocation.id,
            otherLatitude: conditionsLocation.latitude,
            otherLongitude: conditionsLocation.longitude
        )
    }
}
