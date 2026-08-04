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
    /// Canonical recomputed OQ headline when available.
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
        // Conditions manager connectivity (conditions payloads) — independent of location selection delivery.
        connectivityManager.addDelegate(self)
        // Explicit one-time activation: install this fully-initialized handler, then enable
        // location-manager connectivity selection delivery (handler before addDelegate).
        locationManager.activateSelectionHandling(handler: self)
        // Cached conditions load is generation-aware; any selection claimed during activation
        // supersedes stale cache via live-token acceptance rules.
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
        let token = liveIngress.claimPushIngress()
        liveIngress.scheduleProcessing { [weak self] in
            guard let self else { return }

            // Bind to selection at process time (after claim; location mutations claim higher).
            let selectedLocation = await MainActor.run { self.locationManager.selectedLocation }
            // Production pure acceptance seam (fresh + selection association).
            guard WatchConditionsPushAcceptance.shouldAccept(
                conditions: conditions,
                selectedLocation: selectedLocation
            ) else {
                return
            }

            await self.completeLiveUpdate(
                conditions: conditions,
                transported: observingQuality,
                selectedLocation: selectedLocation,
                token: token
            )
            await self.applyTerminalUIIfCurrent(token: token, error: nil)
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem) {
    }

    /// Manual / automatic refresh: claims its own live token and binds current selection.
    func refresh() async {
        guard let selectedLocation = locationManager.selectedLocation else {
            let token = liveIngress.claimRefreshIngress()
            await applyTerminalUIIfCurrent(
                token: token,
                error: ConditionsError.noLocationSelected
            )
            return
        }
        let token = liveIngress.claimRefreshIngress()
        await performRefresh(
            context: WatchConditionsRefreshContext(
                token: token,
                selectedLocation: selectedLocation
            )
        )
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

    // MARK: - Bound refresh pipeline

    /// Full refresh for an immutable context (pre-claimed token + selection).
    private func performRefresh(context: WatchConditionsRefreshContext) async {
        await beginLoadingIfCurrent(token: context.token)

        // Superseded before acquisition starts.
        guard isTokenCurrent(context.token) else { return }

        do {
            let result = try await fetchConditionsWithOQ(
                selectedLocation: context.selectedLocation,
                token: context.token
            )
            // Stale after acquisition — zero side effects.
            guard isTokenCurrent(context.token) else { return }

            await completeLiveUpdate(
                conditions: result.conditions,
                transported: result.transported,
                selectedLocation: result.selectedLocation,
                token: result.token,
                expectedCurrentLocationRequest: result.expectedCurrentLocationRequest
            )
            await applyTerminalUIIfCurrent(token: context.token, error: nil)
        } catch {
            print("WatchConditionsManager: Failed to refresh conditions: \(error)")
            // Token remains claimed: a failed newer refresh still invalidates older work.
            await applyTerminalUIIfCurrent(token: context.token, error: error)
        }
    }

    private func fetchConditionsWithOQ(
        selectedLocation: SelectedLocation,
        token: WatchConditionsLiveUpdateToken
    ) async throws -> WatchConditionsFetchResult {
        // Phase 4C: obtain watch GPS and build request context for Current Location only.
        let currentLocationRequest: WatchCurrentLocationRequestContext?
        if selectedLocation.source == .currentGPS {
            // May await; re-check token after GPS (selection may have changed).
            let coordinate = try await locationManager.getCurrentCoordinate()
            guard isTokenCurrent(token) else {
                throw ConditionsError.fetchFailed("Refresh superseded")
            }
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

        // Bail before phone request if superseded during GPS.
        guard isTokenCurrent(token) else {
            throw ConditionsError.fetchFailed("Refresh superseded")
        }
        
        do {
            let (conditions, _, oq) = try await connectivityManager.requestConditions(
                currentLocationRequest: currentLocationRequest
            )
            guard isTokenCurrent(token) else {
                throw ConditionsError.fetchFailed("Refresh superseded")
            }
            guard Self.isFresh(conditions) else {
                throw ConditionsError.fetchFailed("iOS returned stale conditions")
            }
            if let currentLocationRequest {
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
            return WatchConditionsFetchResult(
                conditions: conditions,
                transported: oq,
                expectedCurrentLocationRequest: currentLocationRequest,
                selectedLocation: selectedLocation,
                token: token
            )
        } catch {
            // If already superseded, do not run local fallback (avoid side work / commit attempts).
            guard isTokenCurrent(token) else {
                throw ConditionsError.fetchFailed("Refresh superseded")
            }
            print("WatchConditionsManager: Watch connectivity failed: \(error.localizedDescription), computing locally")
            let coordinate: (latitude: Double, longitude: Double)
            if let currentLocationRequest {
                coordinate = (currentLocationRequest.latitude, currentLocationRequest.longitude)
            } else {
                coordinate = try await locationManager.getCurrentCoordinate()
                guard isTokenCurrent(token) else {
                    throw ConditionsError.fetchFailed("Refresh superseded")
                }
            }
            let conditions = try await AsyncTimeout.run(seconds: 20, error: ConditionsError.timeout) { [self] in
                try await computeConditionsLocally(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    locationName: selectedLocation.name
                )
            }
            guard isTokenCurrent(token) else {
                throw ConditionsError.fetchFailed("Refresh superseded")
            }
            // Local compute: no phone OQ / atlas — exact night-only.
            return WatchConditionsFetchResult(
                conditions: conditions,
                transported: nil,
                expectedCurrentLocationRequest: nil,
                selectedLocation: selectedLocation,
                token: token
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
        // Fast path: already superseded before timezone work.
        guard isTokenCurrent(token) else { return }

        let timeZone = await Self.resolveTimeZone(for: conditions)
        // Re-check after timezone await — selection change may have claimed.
        guard isTokenCurrent(token) else { return }

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

    // MARK: - Generation-aware loading / error (atomic with live-token claims)

    /// Best-effort stale check for skipping acquisition work (not a UI/publish authority).
    private func isTokenCurrent(_ token: WatchConditionsLiveUpdateToken) -> Bool {
        token.sequence == updateCoordinator.currentLiveSequence
    }

    /// MainActor hop, then **atomic** currency check + loading mutation under the claim lock.
    private func beginLoadingIfCurrent(token: WatchConditionsLiveUpdateToken) async {
        await MainActor.run {
            _ = self.updateCoordinator.withCurrentLiveTokenForRefreshUI(
                token,
                kind: .beginLoading
            ) {
                self.isLoading = true
                self.error = nil
            }
        }
    }

    /// MainActor hop, then **atomic** currency check + terminal mutation under the claim lock.
    private func applyTerminalUIIfCurrent(
        token: WatchConditionsLiveUpdateToken,
        error: Error?
    ) async {
        await MainActor.run {
            _ = self.updateCoordinator.withCurrentLiveTokenForRefreshUI(
                token,
                kind: .terminal
            ) {
                self.error = error
                self.isLoading = false
            }
        }
    }

    private static func isFresh(_ conditions: ViewingConditions) -> Bool {
        conditions.isFreshForLocalDay(
            within: WatchConditionsPushAcceptance.freshConditionsInterval
        )
    }

    private static func conditions(
        _ conditions: ViewingConditions,
        match selectedLocation: SelectedLocation
    ) -> Bool {
        WatchConditionsPushAcceptance.conditionsMatch(conditions, selected: selectedLocation)
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

// MARK: - Selected location change handling

extension WatchConditionsManager: WatchSelectedLocationChangeHandling {
    /// Synchronous invalidation at the location mutation boundary (before any await/Task).
    func claimSelectedLocationChange() -> WatchConditionsLiveUpdateToken {
        liveIngress.claimLocationSelectionIngress()
    }

    /// Replacement refresh for the new selection using the **same** pre-claimed token.
    func startRefresh(
        for location: SelectedLocation,
        token: WatchConditionsLiveUpdateToken
    ) {
        let context = WatchConditionsRefreshContext(
            token: token,
            selectedLocation: location
        )
        liveIngress.scheduleProcessing { [weak self] in
            await self?.performRefresh(context: context)
        }
    }
}
