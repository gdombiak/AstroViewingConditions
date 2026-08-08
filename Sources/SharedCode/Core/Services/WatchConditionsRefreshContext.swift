import Foundation

/// Immutable identity of a conditions refresh/push operation bound to a live token.
///
/// Captured at operation start so async work never re-reads mutable selection state
/// as the request authority after GPS / phone / timezone awaits.
public struct WatchConditionsRefreshContext: Sendable, Equatable {
    public var token: WatchConditionsLiveUpdateToken
    public var selectedLocation: SelectedLocation

    public init(
        token: WatchConditionsLiveUpdateToken,
        selectedLocation: SelectedLocation
    ) {
        self.token = token
        self.selectedLocation = selectedLocation
    }
}

/// Result of acquisition for a bound refresh (selection identity remains attached).
public struct WatchConditionsFetchResult: Sendable {
    public var conditions: ViewingConditions
    public var transported: WatchObservingQualityPayload?
    public var expectedCurrentLocationRequest: WatchCurrentLocationRequestContext?
    public var selectedLocation: SelectedLocation
    public var token: WatchConditionsLiveUpdateToken

    public init(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload?,
        expectedCurrentLocationRequest: WatchCurrentLocationRequestContext?,
        selectedLocation: SelectedLocation,
        token: WatchConditionsLiveUpdateToken
    ) {
        self.conditions = conditions
        self.transported = transported
        self.expectedCurrentLocationRequest = expectedCurrentLocationRequest
        self.selectedLocation = selectedLocation
        self.token = token
    }
}

/// Material identity for selected-location change handling (suppress no-op echoes).
///
/// Separates **conditions refresh** (source / saved ID / observing coordinates) from
/// **display/persistence** (including name-only renames).
public enum WatchSelectedLocationMaterialIdentity: Sendable {
    /// Coordinate identity for saved-location material comparison (same scale as widgets).
    public static let coordinateTolerance = WidgetLocationIdentity.coordinateTolerance

    /// Whether a conditions invalidation + replacement refresh is required.
    ///
    /// - Parameter forceRefresh: User-initiated re-selection (always refresh when true).
    public static func requiresConditionsRefresh(
        from previous: SelectedLocation?,
        to next: SelectedLocation,
        forceRefresh: Bool
    ) -> Bool {
        if forceRefresh { return true }
        guard let previous else { return true }
        if previous.source != next.source { return true }

        switch next.source {
        case .saved:
            if previous.id != next.id { return true }
            return !coordinatesMatch(
                previous.latitude, previous.longitude,
                next.latitude, next.longitude
            )
        case .currentGPS:
            // Repeated Current Location placeholder is not a new observing site.
            let prevPlaceholder = previous.latitude == 0 && previous.longitude == 0
            let nextPlaceholder = next.latitude == 0 && next.longitude == 0
            if prevPlaceholder && nextPlaceholder {
                return false
            }
            if prevPlaceholder != nextPlaceholder {
                return true
            }
            return !coordinatesMatch(
                previous.latitude, previous.longitude,
                next.latitude, next.longitude
            )
        }
    }

    /// Whether selection should be re-persisted / echoed (name-only rename included).
    public static func requiresSelectionPersistence(
        from previous: SelectedLocation?,
        to next: SelectedLocation
    ) -> Bool {
        previous != next
    }

    private static func coordinatesMatch(
        _ lat1: Double, _ lon1: Double,
        _ lat2: Double, _ lon2: Double
    ) -> Bool {
        abs(lat1 - lat2) <= coordinateTolerance
            && abs(lon1 - lon2) <= coordinateTolerance
    }
}

/// Pure production rules for accepting a conditions push against active selection.
public enum WatchConditionsPushAcceptance: Sendable {
    public static let locationMatchTolerance: Double = 0.01
    public static let freshConditionsInterval: TimeInterval = 3600

    /// Whether push conditions may proceed to accept (fresh + selection association).
    public static func shouldAccept(
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?,
        now: Date = Date()
    ) -> Bool {
        guard conditions.isFreshForLocalDay(
            within: freshConditionsInterval,
            relativeTo: now
        ) else {
            return false
        }
        guard let selectedLocation else { return true }
        return conditionsMatch(conditions, selected: selectedLocation)
    }

    public static func conditionsMatch(
        _ conditions: ViewingConditions,
        selected: SelectedLocation
    ) -> Bool {
        if let selectedID = selected.id,
           let conditionsID = conditions.location.id {
            return selectedID == conditionsID
        }
        if selected.source == .currentGPS,
           selected.latitude == 0,
           selected.longitude == 0 {
            return true
        }
        return abs(conditions.location.latitude - selected.latitude) <= locationMatchTolerance
            && abs(conditions.location.longitude - selected.longitude) <= locationMatchTolerance
    }
}

/// Synchronous selected-location mutation → conditions invalidation / replacement refresh.
///
/// Implemented by the watch conditions manager. Location mutations call
/// ``claimSelectedLocationChange()`` **before** mutating selection, then
/// ``startRefresh(for:token:)`` with the same pre-claimed token (no second claim).
public protocol WatchSelectedLocationChangeHandling: AnyObject {
    /// Claim a new live generation that invalidates all prior conditions work.
    func claimSelectedLocationChange() -> WatchConditionsLiveUpdateToken

    /// Start a replacement refresh bound to `token` and `location` (async; non-blocking).
    func startRefresh(
        for location: SelectedLocation,
        token: WatchConditionsLiveUpdateToken
    )
}
