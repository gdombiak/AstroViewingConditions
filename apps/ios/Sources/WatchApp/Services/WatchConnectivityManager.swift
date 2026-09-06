import Foundation
import WatchConnectivity
import WidgetKit
import SharedCode

enum WatchConnectivityError: Error, LocalizedError {
    case sessionNotReachable
    case requestFailed(String)
    case decodeFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotReachable: return "Watch not connected"
        case .requestFailed(let msg): return msg
        case .decodeFailed(let msg): return msg
        }
    }
}

protocol WatchConnectivityManagerDelegate: AnyObject {
    func connectivityManager(
        _ manager: WatchConnectivityManager,
        didReceiveLocations locations: [CachedLocation],
        selectedLocation: SelectedLocation?,
        modeledBrightnessSamples: [ModeledZenithBrightnessSample]
    )
    func connectivityManager(
        _ manager: WatchConnectivityManager,
        didReceiveConditions conditions: ViewingConditions,
        observingQuality: WatchObservingQualityPayload?
    )
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation)
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem)
}

private struct WeakWatchConnectivityDelegate {
    weak var value: WatchConnectivityManagerDelegate?
}

class WatchConnectivityManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager(activateSession: true)

    /// Production conditions reply timeout (seconds).
    static let conditionsRequestTimeout: TimeInterval = 4
    /// Production locations reply timeout (seconds).
    static let locationsRequestTimeout: TimeInterval = 10

    typealias ConditionsReply = (ViewingConditions, SelectedLocation?, WatchObservingQualityPayload?)
    typealias LocationsReply = ([CachedLocation], SelectedLocation?, [ModeledZenithBrightnessSample])

    private var delegates: [WeakWatchConnectivityDelegate] = []

    /// Production single-completion + timeout lifecycle for conditions requests.
    private let conditionsLifecycle: WatchRequestLifecycleController<ConditionsReply>
    /// Production single-completion + timeout lifecycle for location requests.
    private let locationsLifecycle: WatchRequestLifecycleController<LocationsReply>

    /// - Parameters:
    ///   - timeoutScheduler: Injectable timeout scheduler (deterministic tests / production queue).
    ///   - activateSession: When true, activates `WCSession` (production shared instance only).
    init(
        timeoutScheduler: (any WatchRequestTimeoutScheduling)? = nil,
        activateSession: Bool = false
    ) {
        let queue = DispatchQueue(label: "com.astroviewing.conditions.watchconnectivity.continuations")
        let scheduler = timeoutScheduler
            ?? DispatchQueueWatchRequestTimeoutScheduler(queue: queue)
        self.conditionsLifecycle = WatchRequestLifecycleController(scheduler: scheduler)
        self.locationsLifecycle = WatchRequestLifecycleController(scheduler: scheduler)
        super.init()
        if activateSession, WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Outstanding conditions requests (diagnostics).
    var outstandingConditionsRequestCount: Int { conditionsLifecycle.outstandingCount }

    func addDelegate(_ delegate: WatchConnectivityManagerDelegate) {
        removeReleasedDelegates()
        guard !delegates.contains(where: { $0.value === delegate }) else { return }
        delegates.append(WeakWatchConnectivityDelegate(value: delegate))
    }
    
    func removeDelegate(_ delegate: WatchConnectivityManagerDelegate) {
        delegates.removeAll { $0.value == nil || $0.value === delegate }
    }
    
    private func notifyDelegates(_ block: (WatchConnectivityManagerDelegate) -> Void) {
        removeReleasedDelegates()
        for delegate in delegates.compactMap(\.value) {
            block(delegate)
        }
    }

    private func removeReleasedDelegates() {
        delegates.removeAll { $0.value == nil }
    }
    
    func requestLocations() async throws -> (
        [CachedLocation],
        SelectedLocation?,
        [ModeledZenithBrightnessSample]
    ) {
        guard WCSession.default.isReachable else {
            throw WatchConnectivityError.sessionNotReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            locationsLifecycle.begin(
                id: id,
                timeout: Self.locationsRequestTimeout,
                timeoutError: { WatchConnectivityError.requestFailed("Request timed out") },
                continuation: continuation
            )
            
            WCSession.default.sendMessage(
                ["type": "requestLocations", "id": id.uuidString],
                replyHandler: { [weak self] reply in
                    self?.handleLocationReply(reply, id: id)
                },
                errorHandler: { [weak self] error in
                    _ = self?.locationsLifecycle.complete(id, with: .failure(error))
                }
            )
        }
    }
    
    /// Request conditions from the phone.
    ///
    /// - Parameter currentLocationRequest: Phase 4C correlation context when the watch
    ///   supplies authoritative Current Location coordinates. Nil for saved locations.
    func requestConditions(
        currentLocationRequest: WatchCurrentLocationRequestContext? = nil
    ) async throws -> (ViewingConditions, SelectedLocation?, WatchObservingQualityPayload?) {
        guard WCSession.default.isReachable else {
            throw WatchConnectivityError.sessionNotReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            conditionsLifecycle.begin(
                id: id,
                timeout: Self.conditionsRequestTimeout,
                timeoutError: { WatchConnectivityError.requestFailed("Request timed out") },
                continuation: continuation
            )

            let message = WatchConditionsRequestMessageBuilder.makeMessage(
                requestID: id,
                currentLocationRequest: currentLocationRequest
            )
            
            WCSession.default.sendMessage(
                message,
                replyHandler: { [weak self] reply in
                    self?.handleConditionsReply(reply, id: id)
                },
                errorHandler: { [weak self] error in
                    _ = self?.conditionsLifecycle.complete(id, with: .failure(error))
                }
            )
        }
    }
    
    func sendSelectedLocationToiOS(_ location: SelectedLocation) {
        print("WatchConnectivityManager: Sending selected location to iOS: \(location.name)")
        
        guard let data = try? JSONEncoder().encode(location) else { return }
        let message: [String: Any] = ["type": "selectedLocationFromWatch", "selectedLocation": data]
        
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                message,
                replyHandler: { _ in },
                errorHandler: { error in
                    print("WatchConnectivityManager: sendMessage failed: \(error.localizedDescription), falling back to transferUserInfo")
                    WCSession.default.transferUserInfo(message)
                }
            )
        } else {
            print("WatchConnectivityManager: Session not reachable, using transferUserInfo")
            WCSession.default.transferUserInfo(message)
        }
    }
    
    private func handleLocationReply(_ reply: [String: Any], id: UUID) {
        guard let status = reply["status"] as? String, status == "ok" else {
            let message = reply["message"] as? String ?? "Unknown error"
            _ = locationsLifecycle.complete(
                id,
                with: .failure(WatchConnectivityError.requestFailed(message))
            )
            return
        }
        
        var locations: [CachedLocation] = []
        var selected: SelectedLocation?
        
        if let data = reply["locations"] as? Data,
           let decoded = try? JSONDecoder().decode([CachedLocation].self, from: data) {
            locations = decoded
        }
        
        if let selectedData = reply["selectedLocation"] as? Data,
           let decoded = try? JSONDecoder().decode(SelectedLocation.self, from: selectedData) {
            selected = decoded
        }

        let brightnessSamples = WatchLocationsBrightnessPriming.decodeSamples(from: reply)
        
        _ = locationsLifecycle.complete(
            id,
            with: .success((locations, selected, brightnessSamples))
        )
    }
    
    private func handleConditionsReply(_ reply: [String: Any], id: UUID) {
        guard let status = reply["status"] as? String, status == "ok" else {
            let message = reply["message"] as? String ?? "Unknown error"
            _ = conditionsLifecycle.complete(
                id,
                with: .failure(WatchConnectivityError.requestFailed(message))
            )
            return
        }
        
        if let data = reply["conditions"] as? Data,
           let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
            var selectedLocation: SelectedLocation?
            if let selectedData = reply["selectedLocation"] as? Data,
               let location = try? JSONDecoder().decode(SelectedLocation.self, from: selectedData) {
                print("WatchConnectivityManager: Received selected location with conditions: \(location.name)")
                selectedLocation = location
                DispatchQueue.main.async {
                    self.notifyDelegates { $0.connectivityManager(self, didReceiveSelectedLocation: location) }
                }
            }
            // Optional OQ block — decode failure must not lose conditions.
            let oq: WatchObservingQualityPayload?
            if let oqData = reply["observingQuality"] as? Data {
                oq = try? JSONDecoder().decode(WatchObservingQualityPayload.self, from: oqData)
            } else {
                oq = nil
            }
            _ = conditionsLifecycle.complete(id, with: .success((conditions, selectedLocation, oq)))
        } else {
            _ = conditionsLifecycle.complete(
                id,
                with: .failure(WatchConnectivityError.decodeFailed("Failed to decode conditions"))
            )
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("WatchConnectivityManager: Activation complete: \(activationState.rawValue)")
        Task { await processPendingApplicationContext() }
    }

    /// Apply the latest received application context and return only after
    /// selection/locations/units (and accepted conditions) have been delivered to
    /// the existing delegate/transition path.
    ///
    /// Background refresh must `await` this before `refreshIfNeeded()` so it cannot
    /// bind a pre-snapshot selected location.
    func processPendingApplicationContext() async {
        guard WCSession.isSupported() else { return }
        let context = WCSession.default.receivedApplicationContext
        guard !context.isEmpty else { return }
        let snapshot = WatchCompanionSnapshotCodec.decodeAny(context)
        await applyDecodedSnapshot(snapshot, source: "pending app context")
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("WatchConnectivityManager: Received application context: \(applicationContext)")
        let snapshot = WatchCompanionSnapshotCodec.decodeAny(applicationContext)
        Task { await self.applyDecodedSnapshot(snapshot, source: "app context") }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("WatchConnectivityManager: Received message: \(message)")
        let snapshot = WatchCompanionSnapshotCodec.decodeAny(message)
        Task { await self.applyDecodedSnapshot(snapshot, source: "message") }
    }

    private func applyDecodedSnapshot(_ snapshot: WatchCompanionSnapshot?, source: String) async {
        guard let snapshot else {
            print("WatchConnectivityManager: Unknown \(source) companion payload")
            return
        }
        await MainActor.run {
            // Legacy `"conditions"` contexts often omit selectedLocation. Associate
            // them with the existing Watch selection authority — same as the old
            // receiver's `shouldAccept` against `authoritativeSelectedLocation`.
            // Snapshot-provided selection still wins inside consumeThenBind.
            _ = WatchCompanionPendingContext.consumeThenBind(
                snapshot: snapshot,
                currentSelectedLocation: WatchLocationManager.shared.authoritativeSelectedLocation
            ) { plan in
                self.applyPlan(plan, source: source)
            }
        }
    }

    /// Existing delegate/transition infrastructure — called only from
    /// ``WatchCompanionPendingContext/consumeThenBind`` after planning.
    private func applyPlan(_ plan: WatchCompanionSnapshotApplyPlan, source: String) {
        print("WatchConnectivityManager: Applying companion snapshot from \(source)")
        if let locations = plan.locations {
            notifyDelegates {
                $0.connectivityManager(
                    self,
                    didReceiveLocations: locations,
                    selectedLocation: plan.selectedLocation,
                    modeledBrightnessSamples: plan.modeledBrightnessSamples
                )
            }
        }

        if let location = plan.selectedLocation {
            notifyDelegates { $0.connectivityManager(self, didReceiveSelectedLocation: location) }
        }

        if let unitSystem = plan.unitSystem {
            notifyDelegates { $0.connectivityManager(self, didReceiveUnitSystem: unitSystem) }
        }

        if let conditions = plan.conditions {
            notifyDelegates {
                $0.connectivityManager(
                    self,
                    didReceiveConditions: conditions,
                    observingQuality: plan.observingQuality
                )
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WatchConnectivityManager: Reachability changed: \(session.isReachable)")
    }
}
