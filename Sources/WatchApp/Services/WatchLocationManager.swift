import SwiftUI
import Combine
import SharedCode
import WidgetKit

class WatchLocationManager: ObservableObject, @unchecked Sendable, WatchConnectivityManagerDelegate {
    static let shared = WatchLocationManager()
    
    @Published var locations: [CachedLocation] = []
    @Published var selectedLocation: SelectedLocation?
    @Published var unitSystem: UnitSystem = .metric
    @Published var isLoading = false
    
    private let connectivityManager: WatchConnectivityManager

    /// Authoritative selected-location transitions (not `@Published`).
    /// Seeded synchronously at init before remote callbacks can race.
    private let transitionCoordinator: WatchSelectedLocationTransitionCoordinator

    /// Unified FIFO application for **remote and user** transitions:
    /// MainActor publish → persist → send → refresh.
    private let transitionApplier = WatchSelectedLocationTransitionApplier()

    /// Shared ingress lock for **all** selected-location entry sources.
    ///
    /// Formal order: acquisition order of this lock → transition order.
    private let selectedLocationIngress = WatchSelectedLocationIngressCoordinator()

    /// Atomic list-result accept + selection reservation + serial list apply.
    private let locationsListCoordinator = WatchLocationsListResultCoordinator()
    private let locationsListApplier = WatchLocationsListResultApplier()

    /// Explicit activation: handler install + exactly-once connectivity delegate registration.
    ///
    /// Init does **not** register as a connectivity delegate. Call
    /// ``activateSelectionHandling(handler:)`` once after the conditions manager is ready.
    private let selectionActivation = WatchSelectionHandlingActivation()
    
    /// Production: uses shared connectivity. Tests may inject a non-activating session manager.
    init(connectivityManager: WatchConnectivityManager = .shared) {
        self.connectivityManager = connectivityManager
        // Seed transition authority **before** any connectivity callbacks can be delivered.
        // Delegate registration is deferred until ``activateSelectionHandling(handler:)``.
        let storedSelected = AppGroupStorage.loadSelectedLocation()
            ?? iCloudKeyValueStorage.shared.loadSelectedLocation()
        self.transitionCoordinator = WatchSelectedLocationTransitionCoordinator(seed: storedSelected)
        loadInitialState(storedSelected: storedSelected)
    }
    
    private func loadInitialState(storedSelected: SelectedLocation?) {
        let storedLocations = loadStoredLocations()
        let storedUnitSystem = AppGroupStorage.loadUnitSystem()
            .flatMap { UnitSystem(rawValue: $0) }
            ?? iCloudKeyValueStorage.shared.loadUnitSystem()
            .flatMap { UnitSystem(rawValue: $0) }
            ?? .metric
        
        // Startup MainActor publication only (authority already seeded; not a runtime transition).
        DispatchQueue.main.async {
            self.locations = storedLocations
            self.selectedLocation = storedSelected
            self.unitSystem = storedUnitSystem
        }
    }

    // MARK: - Selection handling activation

    /// Install the conditions invalidation/refresh handler, then enable connectivity selection delivery.
    ///
    /// **Order:** handler is stored (state → activating) before `addDelegate`, so synchronous
    /// callbacks during registration observe a valid handler. Delegate registration is exactly once.
    ///
    /// Idempotent for the same handler. Different-handler reactivation is rejected.
    @discardableResult
    func activateSelectionHandling(
        handler: any WatchSelectedLocationChangeHandling
    ) -> WatchSelectionHandlingActivation.ActivationResult {
        selectionActivation.activate(handler: handler) { [self] in
            self.connectivityManager.addDelegate(self)
        }
    }

    /// Test/diagnostics: activation state.
    var selectionActivationState: WatchSelectionHandlingActivation.State {
        selectionActivation.currentState
    }

    /// Test/diagnostics: whether connectivity selection delivery has been enabled.
    var isConnectivitySelectionDeliveryActive: Bool {
        selectionActivation.currentState == .active
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?) {
        // Strong capture for synchronous prepareSelection + list submit under list lock.
        locationsListCoordinator.acceptConnectivityPush(
            locations: locations,
            selected: selectedLocation,
            prepareSelection: { [self] kind in
                self.prepareSelectionForAcceptedListResult(kind)
            },
            submit: { [self] accepted in
                self.submitLocationsListResult(accepted)
            }
        )
    }
    
    func connectivityManager(
        _ manager: WatchConnectivityManager,
        didReceiveConditions conditions: ViewingConditions,
        observingQuality: WatchObservingQualityPayload?
    ) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation) {
        // No phone echo. Shared ingress then transition apply-and-submit.
        ingressRemoteSelection(location)
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem) {
        AppGroupStorage.saveUnitSystem(unitSystem.rawValue)
        Task { @MainActor in
            self.unitSystem = unitSystem
        }
    }
    
    func refresh() async {
        // Claim epoch + loading ownership before any loading UI mutation so older accepted
        // results cannot clear this refresh's loading.
        let epoch = locationsListCoordinator.beginRefresh()
        await MainActor.run { isLoading = true }
        
        do {
            let (locations, selected) = try await connectivityManager.requestLocations()
            _ = locationsListCoordinator.acceptIfCurrent(
                epoch: epoch,
                kind: .success(locations: locations, selected: selected),
                prepareSelection: { [self] kind in
                    self.prepareSelectionForAcceptedListResult(kind)
                },
                submit: { [self] accepted in
                    self.submitLocationsListResult(accepted)
                }
            )
        } catch {
            print("WatchLocationManager: Watch connectivity failed for locations: \(error.localizedDescription), using cached")
            let cachedLocations = loadStoredLocations()
            let cachedSelected = AppGroupStorage.loadSelectedLocation()
            _ = locationsListCoordinator.acceptIfCurrent(
                epoch: epoch,
                kind: .failure(cachedLocations: cachedLocations, cachedSelected: cachedSelected),
                prepareSelection: { [self] kind in
                    self.prepareSelectionForAcceptedListResult(kind)
                },
                submit: { [self] accepted in
                    self.submitLocationsListResult(accepted)
                }
            )
        }
    }

    // MARK: - Locations list acceptance (selection reserved via shared ingress)

    /// Reserve selected-location order during list-result acceptance.
    ///
    /// Called **under the list-result coordinator lock**. Enters shared selected-location
    /// ingress, then transition apply-and-submit.
    private func prepareSelectionForAcceptedListResult(_ kind: WatchLocationsListResultKind) {
        selectedLocationIngress.perform {
            if let remote = kind.remoteSelected {
                applyRemoteSelectionAlreadyInsideIngress(remote)
                return
            }
            if let cached = kind.failureCachedSelected {
                applyRestoreAlreadyInsideIngress(cached)
            }
        }
    }

    /// Nonblocking list-result enqueue — safe under the list coordinator lock.
    private func submitLocationsListResult(_ result: WatchLocationsListAcceptedResult) {
        locationsListApplier.enqueue(
            result,
            persistList: { locations in
                AppGroupStorage.saveSavedLocations(locations)
            },
            publishListOnMain: { [weak self] accepted in
                guard let self else { return }
                self.locations = accepted.kind.locationsToPublish
                _ = self.locationsListCoordinator.clearLoadingIfOwner(accepted.epoch) {
                    self.isLoading = false
                }
            }
        )
    }
    
    func select(_ location: CachedLocation) {
        let selected = SelectedLocation(
            source: .saved,
            id: location.id,
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        ingressUserSelection(selected, sendToPhone: true)
    }
    
    func selectCurrentLocation() {
        let selected = SelectedLocation(
            source: .currentGPS,
            name: "Current Location",
            latitude: 0,
            longitude: 0
        )
        ingressUserSelection(selected, sendToPhone: true)
    }

    // MARK: - Shared ingress entry (enters ingress)

    private func ingressRemoteSelection(_ incoming: SelectedLocation) {
        selectedLocationIngress.perform {
            applyRemoteSelectionAlreadyInsideIngress(incoming)
        }
    }

    private func ingressUserSelection(_ incoming: SelectedLocation, sendToPhone: Bool) {
        selectedLocationIngress.perform {
            applyUserSelectionAlreadyInsideIngress(incoming, sendToPhone: sendToPhone)
        }
    }

    // MARK: - Already inside ingress (must not call ingress wrappers)

    /// Snapshot one stable handler for claim + startRefresh of this transition.
    /// Fail closed when inactive or handler deallocated.
    private func resolvedHandlerForTransition() -> (any WatchSelectedLocationChangeHandling)? {
        selectionActivation.resolvedHandlerForTransition()
    }

    /// Remote transition apply-and-submit. **Caller must hold shared ingress.**
    private func applyRemoteSelectionAlreadyInsideIngress(_ incoming: SelectedLocation) {
        // Require activation before any runtime selection classification.
        guard let handler = resolvedHandlerForTransition() else {
            print("WatchLocationManager: rejecting remote selection — selection handling not active")
            return
        }
        // Stable snapshot for claim + queued startRefresh (same instance).
        let stableHandler = handler
        transitionCoordinator.applyRemote(
            incoming,
            claimRefresh: {
                stableHandler.claimSelectedLocationChange()
            },
            submit: { [self] transition in
                self.submitToApplier(transition, handler: stableHandler)
            }
        )
    }

    /// User transition apply-and-submit. **Caller must hold shared ingress.**
    private func applyUserSelectionAlreadyInsideIngress(
        _ incoming: SelectedLocation,
        sendToPhone: Bool
    ) {
        guard let handler = resolvedHandlerForTransition() else {
            print("WatchLocationManager: rejecting user selection — selection handling not active")
            return
        }
        let stableHandler = handler
        transitionCoordinator.applyUser(
            incoming,
            sendToPhone: sendToPhone,
            claimRefresh: {
                stableHandler.claimSelectedLocationChange()
            },
            submit: { [self] transition in
                self.submitToApplier(transition, handler: stableHandler)
            }
        )
    }

    /// Runtime restore apply-and-submit. **Caller must hold shared ingress.**
    private func applyRestoreAlreadyInsideIngress(_ cachedSelected: SelectedLocation) {
        guard let handler = resolvedHandlerForTransition() else {
            print("WatchLocationManager: rejecting restore — selection handling not active")
            return
        }
        let stableHandler = handler
        transitionCoordinator.restoreIfUninitialized(
            cachedSelected,
            claimRefresh: {
                stableHandler.claimSelectedLocationChange()
            },
            submit: { [self] transition in
                self.submitToApplier(transition, handler: stableHandler)
            }
        )
    }

    /// Nonblocking selection-applier submission — safe under transition coordinator lock.
    ///
    /// Uses the same `handler` snapshot that performed the live claim for this transition.
    private func submitToApplier(
        _ transition: WatchSelectedLocationTransition,
        handler: any WatchSelectedLocationChangeHandling
    ) {
        transitionApplier.enqueue(
            transition,
            publish: { [weak self] location in
                self?.selectedLocation = location
            },
            persist: { location in
                LocationStorageService.shared.saveSelectedLocation(location)
                AppGroupStorage.saveSelectedLocation(location)
            },
            sendToPhone: { [weak self] location in
                self?.connectivityManager.sendSelectedLocationToiOS(location)
            },
            startRefresh: { location, token in
                handler.startRefresh(for: location, token: token)
            }
        )
    }
    
    /// Prefer transition authority for coordinate identity (may lead `@Published` briefly).
    var activeCoordinate: Coordinate? {
        guard let selected = transitionCoordinator.currentAuthoritative ?? selectedLocation else {
            return nil
        }
        if selected.source == .currentGPS {
            return nil
        }
        return Coordinate(latitude: selected.latitude, longitude: selected.longitude)
    }
    
    func getCurrentCoordinate() async throws -> (latitude: Double, longitude: Double) {
        if let coord = activeCoordinate {
            return (coord.latitude, coord.longitude)
        }
        
        let locManager = await MainActor.run { LocationManager() }
        
        if await locManager.authorizationStatus == .notDetermined {
            await locManager.requestAuthorization()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        guard await locManager.isAuthorized else {
            throw LocationError.notAuthorized
        }
        
        let coord = try await locManager.getCurrentLocation()
        return (coord.latitude, coord.longitude)
    }
    
    private func loadStoredLocations() -> [CachedLocation] {
        LocationStorageService.shared.loadSavedLocations()
    }
}
