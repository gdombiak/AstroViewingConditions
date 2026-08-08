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
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?)
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
    typealias LocationsReply = ([CachedLocation], SelectedLocation?)

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
    
    func requestLocations() async throws -> ([CachedLocation], SelectedLocation?) {
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
        
        _ = locationsLifecycle.complete(id, with: .success((locations, selected)))
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
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("WatchConnectivityManager: Received application context: \(applicationContext)")
        handleIncomingData(applicationContext, source: "app context")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("WatchConnectivityManager: Received message: \(message)")
        handleIncomingData(message, source: "message")
    }
    
    private func handleIncomingData(_ incomingData: [String: Any], source: String) {
        guard let type = incomingData["type"] as? String else { return }
        
        let locationsData = incomingData["locations"] as? Data
        let conditionsData = incomingData["conditions"] as? Data
        let selectedLocationData = incomingData["selectedLocation"] as? Data
        let unitSystemData = incomingData["unitSystem"] as? Data
        let observingQualityData = incomingData["observingQuality"] as? Data
        
        DispatchQueue.main.async {
            switch type {
            case "savedLocations":
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received \(locations.count) locations from \(source)")
                    self.notifyDelegates { $0.connectivityManager(self, didReceiveLocations: locations, selectedLocation: nil) }
                }
                
            case "conditions":
                if let data = conditionsData,
                   let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                    print("WatchConnectivityManager: Received conditions from \(source)")
                    let oq: WatchObservingQualityPayload?
                    if let oqData = observingQualityData {
                        oq = try? JSONDecoder().decode(WatchObservingQualityPayload.self, from: oqData)
                    } else {
                        oq = nil
                    }
                    self.notifyDelegates {
                        $0.connectivityManager(self, didReceiveConditions: conditions, observingQuality: oq)
                    }
                }
                
            case "locationSync", "selectedLocation":
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(SelectedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location from \(source): \(location.name)")
                    self.notifyDelegates { $0.connectivityManager(self, didReceiveSelectedLocation: location) }
                }
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received location sync from \(source): \(locations.count) locations")
                    self.notifyDelegates { $0.connectivityManager(self, didReceiveLocations: locations, selectedLocation: nil) }
                }
                
            case "unitSystem":
                if let data = unitSystemData,
                   let unitSystem = try? JSONDecoder().decode(String.self, from: data) {
                    print("WatchConnectivityManager: Received unit system: \(unitSystem)")
                    if let system = UnitSystem(rawValue: unitSystem) {
                        self.notifyDelegates { $0.connectivityManager(self, didReceiveUnitSystem: system) }
                    }
                }
                
            default:
                print("WatchConnectivityManager: Unknown \(source) type: \(type)")
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WatchConnectivityManager: Reachability changed: \(session.isReachable)")
    }
}
