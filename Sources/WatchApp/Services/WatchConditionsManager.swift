import Foundation
import SwiftUI
import SharedCode
import WidgetKit

enum ConditionsError: Error, LocalizedError {
    case noLocationSelected
    case fetchFailed(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .noLocationSelected: return "No location selected"
        case .fetchFailed(let msg): return msg
        case .timeout: return "Refresh timed out. Showing saved data."
        }
    }
}

protocol WatchConditionsManagerDelegate: AnyObject {
    func conditionsManager(_ manager: WatchConditionsManager, didReceiveConditions conditions: ViewingConditions)
}

/// Bridges WidgetKit reload into the SharedCode protocol used by the update coordinator.
final class WidgetCenterComplicationReloader: WatchComplicationReloadReporting, @unchecked Sendable {
    func reloadComplications() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

class WatchConditionsManager: ObservableObject, @unchecked Sendable, WatchConnectivityManagerDelegate {
    static let shared = WatchConditionsManager()
    private static let freshConditionsInterval: TimeInterval = 3600
    private static let locationMatchTolerance = 0.01
    
    weak var delegate: WatchConditionsManagerDelegate?
    
    private let connectivityManager: WatchConnectivityManager
    private let locationManager: WatchLocationManager
    private let conditionsProvider: ConditionsProvider
    /// Production serialized accept path (resolve → persist pair → state → reload).
    private let updateCoordinator: WatchConditionsAcceptedUpdateCoordinator
    /// Claims live sequence at event receipt (before unstructured Tasks).
    private let liveIngress: WatchConditionsLiveEventIngress
    /// Generation-aware MainActor publication of coordinator applied state.
    private let observablePublisher: WatchConditionsObservablePublisher

    @Published var conditions: ViewingConditions?
    @Published var nightQuality: NightQualityAssessment?
    /// Canonical recomputed OQ headline (saved location only when available).
    @Published private(set) var observingQualityHeadline: WatchObservingQualityHeadline?
    @Published private(set) var locationTimeZone: TimeZone?
    @Published var isLoading = false
    @Published var error: Error?

    /// Headline score for dashboard / complications (OQ when valid, else night).
    var headlineScore: Int {
        if let observingQualityHeadline {
            return observingQualityHeadline.observingQualityScore
        }
        return nightQuality?.calculatedScore ?? 0
    }

    var headlineVerdict: String {
        if let observingQualityHeadline {
            return observingQualityHeadline.verdict
        }
        if let nightQuality {
            return CrossSurfaceHeadlineScorePresentation.verdict(for: nightQuality.calculatedScore)
        }
        return "Unavailable"
    }

    /// Category emoji from the same OQ/night headline band as `headlineScore`.
    var headlineEmoji: String {
        CrossSurfaceHeadlineScorePresentation.emoji(for: headlineScore)
    }
    
    var locationCalendar: Calendar {
        if let timeZone = displayTimeZone {
            return LocationTimeZoneResolver.calendar(for: timeZone)
        }
        return LocationTimeZoneResolver.calendar(for: TimeZone(secondsFromGMT: 0) ?? TimeZone.current)
    }
    
    var displayTimeZone: TimeZone? {
        if let locationTimeZone {
            return locationTimeZone
        }
        if let identifier = conditions?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        if let longitude = conditions?.location.longitude {
            return LocationTimeZoneResolver.approximate(longitude: longitude)
        }
        return nil
    }
    
    private init(
        connectivityManager: WatchConnectivityManager = .shared,
        locationManager: WatchLocationManager = .shared,
        conditionsProvider: ConditionsProvider = ConditionsProvider(),
        updateCoordinator: WatchConditionsAcceptedUpdateCoordinator? = nil
    ) {
        self.connectivityManager = connectivityManager
        self.locationManager = locationManager
        self.conditionsProvider = conditionsProvider
        let coordinator = updateCoordinator ?? WatchConditionsAcceptedUpdateCoordinator(
            store: AppGroupWatchConditionsStore(),
            reloader: WidgetCenterComplicationReloader()
        )
        self.updateCoordinator = coordinator
        // nonisolated claim — no actor hop; order = call order at ingress.
        self.liveIngress = WatchConditionsLiveEventIngress(claim: {
            coordinator.claimLiveUpdate()
        })
        self.observablePublisher = WatchConditionsObservablePublisher(coordinator: coordinator)
        connectivityManager.addDelegate(self)
        loadCachedConditions()
    }

    var shouldRefresh: Bool {
        guard let conditions else { return true }
        guard let selectedLocation = locationManager.selectedLocation else { return true }
        return !Self.isFresh(conditions) || !Self.conditions(conditions, match: selectedLocation)
    }

    private func loadCachedConditions() {
        Task {
            let token = await updateCoordinator.beginDeferredApplication()
            guard let conditions = await AppGroupStorage.loadWatchNightConditionsAsync() else { return }
            let timeZone = await Self.resolveTimeZone(for: conditions)
            let document = await AppGroupStorage.loadWatchObservingQualityAsync()
            let selected = await MainActor.run { locationManager.selectedLocation }
            let result = await updateCoordinator.applyCached(
                conditions: conditions,
                selectedLocation: selected,
                persistedDocument: document,
                locationTimeZone: timeZone,
                token: token
            )
            if case .applied(let state) = result {
                await self.publishIfCurrent(state)
            }
        }
    }

    func connectivityManager(
        _ manager: WatchConnectivityManager,
        didReceiveConditions conditions: ViewingConditions,
        observingQuality: WatchObservingQualityPayload?
    ) {
        // Claim at callback receipt — synchronous, before any unstructured Task.
        // Task run order must not determine live sequence.
        let token = liveIngress.claimPushIngress()
        liveIngress.scheduleProcessing { [weak self] in
            guard let self else { return }
            if !Self.isFresh(conditions) {
                // Token still invalidates older outstanding work.
                return
            }

            let selectedLocation = await MainActor.run { self.locationManager.selectedLocation }
            if let selectedLocation,
               !Self.conditions(conditions, match: selectedLocation) {
                return
            }

            await self.completeLiveUpdate(
                conditions: conditions,
                transported: observingQuality,
                selectedLocation: selectedLocation,
                token: token
            )
            await MainActor.run {
                self.error = nil
                self.isLoading = false
            }
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem) {
    }
    
    func refresh() async {
        // First operation of this refresh: synchronous live claim (before any await).
        let token = liveIngress.claimRefreshIngress()

        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            // requestConditions result and local fallback share this refresh token.
            let result = try await fetchConditionsWithOQ()
            await completeLiveUpdate(
                conditions: result.conditions,
                transported: result.oq,
                selectedLocation: locationManager.selectedLocation,
                token: token,
                expectedCurrentLocationRequest: result.expectedCurrentLocationRequest
            )
            await MainActor.run {
                self.error = nil
                self.isLoading = false
            }
        } catch {
            print("WatchConditionsManager: Failed to refresh conditions: \(error)")
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
            // Token remains claimed: a failed newer refresh still invalidates older work.
        }
    }

    func loadNewerSharedCacheIfAvailable() async {
        guard let cached = await AppGroupStorage.loadWatchNightConditionsAsync() else { return }

        let selectedLocation = await MainActor.run { locationManager.selectedLocation }
        if let selectedLocation,
           !Self.conditions(cached, match: selectedLocation) {
            return
        }

        let shouldUseCached = await MainActor.run {
            guard let conditions else { return true }
            return cached.fetchedAt > conditions.fetchedAt
        }

        guard shouldUseCached else { return }

        let token = await updateCoordinator.beginDeferredApplication()
        let document = await AppGroupStorage.loadWatchObservingQualityAsync()
        let timeZone = await Self.resolveTimeZone(for: cached)
        let result = await updateCoordinator.applyCached(
            conditions: cached,
            selectedLocation: selectedLocation,
            persistedDocument: document,
            locationTimeZone: timeZone,
            token: token
        )
        if case .applied(let state) = result {
            await publishIfCurrent(state)
        }
    }
    
    private struct FetchResult {
        var conditions: ViewingConditions
        var oq: WatchObservingQualityPayload?
        var expectedCurrentLocationRequest: WatchCurrentLocationRequestContext?
    }

    private func fetchConditionsWithOQ() async throws -> FetchResult {
        guard let selectedLocation = locationManager.selectedLocation else {
            throw ConditionsError.noLocationSelected
        }

        // Phase 4C: obtain watch GPS and build request context for Current Location only.
        let currentLocationRequest: WatchCurrentLocationRequestContext?
        if selectedLocation.source == .currentGPS {
            let coordinate = try await locationManager.getCurrentCoordinate()
            guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            !(coordinate.latitude == 0 && coordinate.longitude == 0) else {
                throw ConditionsError.fetchFailed("Invalid watch Current Location coordinates")
            }
            currentLocationRequest = WatchCurrentLocationRequestContext(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        } else {
            currentLocationRequest = nil
        }
        
        do {
            let (conditions, _, oq) = try await connectivityManager.requestConditions(
                currentLocationRequest: currentLocationRequest
            )
            guard Self.isFresh(conditions) else {
                throw ConditionsError.fetchFailed("iOS returned stale conditions")
            }
            if let currentLocationRequest {
                // Conditions must match watch-requested coordinates (not phone selection).
                guard WatchObservingQualityCurrentLocationAssociation.matches(
                    request: currentLocationRequest,
                    conditionsLocation: conditions.location
                ) else {
                    throw ConditionsError.fetchFailed("iOS returned conditions for a different location")
                }
            } else {
                guard Self.conditions(conditions, match: selectedLocation) else {
                    throw ConditionsError.fetchFailed("iOS returned conditions for a different location")
                }
            }
            return FetchResult(
                conditions: conditions,
                oq: oq,
                expectedCurrentLocationRequest: currentLocationRequest
            )
        } catch {
            print("WatchConditionsManager: Watch connectivity failed: \(error.localizedDescription), computing locally")
            let coordinate: (latitude: Double, longitude: Double)
            if let currentLocationRequest {
                coordinate = (currentLocationRequest.latitude, currentLocationRequest.longitude)
            } else {
                coordinate = try await locationManager.getCurrentCoordinate()
            }
            let conditions = try await AsyncTimeout.run(seconds: 20, error: ConditionsError.timeout) { [self] in
                try await computeConditionsLocally(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    locationName: selectedLocation.name
                )
            }
            // Local compute: no phone OQ / atlas — exact night-only.
            // Same live token; drop CL request correlation (no correlated transport).
            return FetchResult(
                conditions: conditions,
                oq: nil,
                expectedCurrentLocationRequest: nil
            )
        }
    }

    /// Timezone resolution then coordinator accept using a pre-claimed live token.
    private func completeLiveUpdate(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload?,
        selectedLocation: SelectedLocation?,
        token: WatchConditionsLiveUpdateToken,
        expectedCurrentLocationRequest: WatchCurrentLocationRequestContext? = nil
    ) async {
        let timeZone = await Self.resolveTimeZone(for: conditions)
        let result = await updateCoordinator.accept(
            conditions: conditions,
            transported: transported,
            selectedLocation: selectedLocation,
            locationTimeZone: timeZone,
            reloadComplications: true,
            token: token,
            expectedCurrentLocationRequest: expectedCurrentLocationRequest
        )
        switch result {
        case .discardedStale:
            return
        case .persistFailed(let error):
            print("WatchConditionsManager: Failed to persist conditions/OQ pair: \(error)")
            return
        case .applied(let state):
            await publishIfCurrent(state)
        }
    }

    /// Generation-aware transfer from coordinator applied state to observable properties.
    ///
    /// Validation + mutation are one MainActor-ordered operation under the ingress lock.
    private func publishIfCurrent(_ state: WatchConditionsAppliedState) async {
        await MainActor.run {
            _ = self.observablePublisher.publish(state) { applied in
                self.conditions = applied.conditions
                self.nightQuality = applied.nightQuality
                self.observingQualityHeadline = applied.observingQualityHeadline
                self.locationTimeZone = applied.locationTimeZone
            }
        }
    }

    private static func isFresh(_ conditions: ViewingConditions) -> Bool {
        conditions.isFreshForLocalDay(within: freshConditionsInterval)
    }

    private static func conditions(_ conditions: ViewingConditions, match selectedLocation: SelectedLocation) -> Bool {
        if let selectedID = selectedLocation.id,
           let conditionsID = conditions.location.id {
            return selectedID == conditionsID
        }

        if selectedLocation.source == .currentGPS,
           selectedLocation.latitude == 0,
           selectedLocation.longitude == 0 {
            return true
        }

        return coordinates(
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            matchLatitude: selectedLocation.latitude,
            matchLongitude: selectedLocation.longitude
        )
    }

    private static func coordinates(
        latitude: Double,
        longitude: Double,
        matchLatitude: Double,
        matchLongitude: Double
    ) -> Bool {
        abs(latitude - matchLatitude) <= locationMatchTolerance
            && abs(longitude - matchLongitude) <= locationMatchTolerance
    }
    
    private func computeConditionsLocally(
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws -> ViewingConditions {
        try await conditionsProvider.fetchConditions(
            for: CachedLocation(
                name: locationName,
                latitude: latitude,
                longitude: longitude
            ),
            days: 2
        )
    }
    
    private static func resolveTimeZone(for conditions: ViewingConditions) async -> TimeZone {
        if let identifier = conditions.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        
        return await resolveTimeZone(for: conditions.location)
    }
    
    private static func resolveTimeZone(for location: CachedLocation) async -> TimeZone {
        await LocationTimeZoneResolver.resolve(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }
}
