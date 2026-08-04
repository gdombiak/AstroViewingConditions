import Foundation

/// Strict Phase 4C Current Location coordinate / request association.
///
/// Uses the narrow widget identity coordinate tolerance (1e-5°), **not** the Phase 1
/// 1000 m brightness sample radius. Does not accept `.saved` identities.
public enum WatchObservingQualityCurrentLocationAssociation: Sendable {
    public static let coordinateTolerance = WidgetLocationIdentity.coordinateTolerance

    public static func coordinatesMatch(
        latitude: Double,
        longitude: Double,
        otherLatitude: Double,
        otherLongitude: Double
    ) -> Bool {
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: latitude,
            longitude: longitude
        ),
        ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: otherLatitude,
            longitude: otherLongitude
        ) else {
            return false
        }
        // Reject unresolved phone/watch placeholder.
        if (latitude == 0 && longitude == 0) || (otherLatitude == 0 && otherLongitude == 0) {
            return false
        }
        return abs(latitude - otherLatitude) <= coordinateTolerance
            && abs(longitude - otherLongitude) <= coordinateTolerance
    }

    public static func matches(
        request: WatchCurrentLocationRequestContext,
        conditionsLocation: CachedLocation
    ) -> Bool {
        guard request.isStructurallyValid else { return false }
        // Conditions for Current Location must not carry a saved ID.
        guard conditionsLocation.id == nil else { return false }
        return coordinatesMatch(
            latitude: request.latitude,
            longitude: request.longitude,
            otherLatitude: conditionsLocation.latitude,
            otherLongitude: conditionsLocation.longitude
        )
    }

    public static func matches(
        request: WatchCurrentLocationRequestContext,
        context: CrossSurfaceLocationContext
    ) -> Bool {
        guard request.isStructurallyValid else { return false }
        guard context.source == .currentGPS,
              context.savedLocationID == nil,
              context.hasConsistentIdentity else {
            return false
        }
        return coordinatesMatch(
            latitude: request.latitude,
            longitude: request.longitude,
            otherLatitude: context.latitude,
            otherLongitude: context.longitude
        )
    }

    public static func matches(
        context: CrossSurfaceLocationContext,
        conditionsLocation: CachedLocation
    ) -> Bool {
        guard context.source == .currentGPS,
              context.savedLocationID == nil,
              context.hasConsistentIdentity,
              context.hasValidGeographicCoordinates else {
            return false
        }
        guard conditionsLocation.id == nil else { return false }
        return coordinatesMatch(
            latitude: context.latitude,
            longitude: context.longitude,
            otherLatitude: conditionsLocation.latitude,
            otherLongitude: conditionsLocation.longitude
        )
    }

    /// Live transport: expected request must match echoed transport request context.
    public static func requestCorrelationMatches(
        expected: WatchCurrentLocationRequestContext,
        transported: WatchCurrentLocationRequestContext
    ) -> Bool {
        guard expected.isStructurallyValid, transported.isStructurallyValid else { return false }
        guard expected.requestID == transported.requestID else { return false }
        guard expected.source == .currentGPS, transported.source == .currentGPS else { return false }
        return coordinatesMatch(
            latitude: expected.latitude,
            longitude: expected.longitude,
            otherLatitude: transported.latitude,
            otherLongitude: transported.longitude
        )
    }
}
