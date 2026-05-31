import Foundation
import WatchConnectivity
import SharedCode

private final class WatchReplyHandler: @unchecked Sendable {
    private let replyHandler: ([String: Any]) -> Void
    
    init(_ replyHandler: @escaping ([String: Any]) -> Void) {
        self.replyHandler = replyHandler
    }
    
    func reply(_ message: [String: Any]) {
        replyHandler(message)
    }
}

@MainActor
public class WatchConnectivityService: NSObject, ObservableObject {
    public static let shared = WatchConnectivityService()
    
    @Published public var isReachable = false
    @Published public var isPaired = false
    
    private var session: WCSession?
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    public func sendLocationsToWatch(_ locations: [CachedLocation]) {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        sendViaApplicationContext(type: "savedLocations", payload: ["locations": data])
    }
    
    public func sendCurrentLocationToWatch(_ location: CachedLocation) {
        guard let data = try? JSONEncoder().encode(location) else { return }
        sendViaApplicationContext(type: "currentLocation", payload: ["location": data])
    }
    
    public func sendConditionsToWatch(_ conditions: ViewingConditions) {
        guard let data = try? JSONEncoder().encode(conditions) else { return }
        sendViaApplicationContext(type: "conditions", payload: ["conditions": data])
    }
    
    public func sendSelectedLocationToWatch(_ location: SelectedLocation) {
        guard let data = try? JSONEncoder().encode(location) else { return }
        sendViaApplicationContext(type: "selectedLocation", payload: ["selectedLocation": data])
    }
    
    public func sendUnitSystemToWatch(_ system: UnitSystem) {
        guard let data = try? JSONEncoder().encode(system.rawValue) else { return }
        sendViaApplicationContext(type: "unitSystem", payload: ["unitSystem": data])
    }
    
    private func sendViaApplicationContext(type: String, payload: [String: Any]) {
        guard let session = session else { return }
        
        var message = payload
        message["type"] = type
        
        do {
            try session.updateApplicationContext(message)
            print("WatchConnectivityService: Updated applicationContext with \(type)")
        } catch {
            print("WatchConnectivityService: Failed to update applicationContext: \(error)")
            sendMessage(type: type, payload: message)
        }
    }
    
    private func sendMessage(type: String, payload: [String: Any]) {
        guard let session = session, session.isReachable else {
            print("WatchConnectivityService: Session not reachable for type: \(type)")
            return
        }
        
        session.sendMessage(
            payload,
            replyHandler: Self.makeReplyHandler(type: type),
            errorHandler: Self.makeErrorHandler(type: type)
        )
    }

    nonisolated private static func makeReplyHandler(type: String) -> ([String: Any]) -> Void {
        { reply in
            print("WatchConnectivityService: Sent \(type), reply: \(reply)")
        }
    }

    nonisolated private static func makeErrorHandler(type: String) -> (any Error) -> Void {
        { error in
            print("WatchConnectivityService: Failed to send \(type): \(error.localizedDescription)")
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let isPaired = session.isPaired
        print("WatchConnectivityService: Activation state: \(activationState.rawValue)")
        Task { @MainActor in
            self.isPaired = isPaired
        }
    }
    
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        print("WatchConnectivityService: Session became inactive")
    }
    
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        print("WatchConnectivityService: Session deactivated")
    }
    
    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        print("WatchConnectivityService: Reachability changed: \(isReachable)")
        Task { @MainActor in
            self.isReachable = isReachable
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        print("WatchConnectivityService: Received message: \(message)")
        handleMessage(message, replyHandler: replyHandler)
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        print("WatchConnectivityService: Received userInfo: \(userInfo)")
        handleMessage(userInfo)
    }
    
    nonisolated private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        if let type = message["type"] as? String {
            switch type {
            case "requestLocations":
                handleRequestLocations(replyHandler: replyHandler)
            case "requestConditions":
                handleRequestConditions(replyHandler: replyHandler)
            case "selectedLocationFromWatch":
                if let data = message["selectedLocation"] as? Data,
                   let location = try? JSONDecoder().decode(SelectedLocation.self, from: data) {
                    print("WatchConnectivityService: Received location selection from Watch: \(location.name)")
                    refreshForLocation(location: location)
                }
                replyHandler?(["status": "ok"])
            default:
                print("WatchConnectivityService: Unknown message type: \(type)")
            }
        }
    }
    
    nonisolated private func refreshForLocation(location: SelectedLocation) {
        LocationStorageService.shared.saveSelectedLocation(location)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .watchLocationSelected,
                object: location
            )
        }
    }
    
    nonisolated private func handleRequestLocations(replyHandler: (([String: Any]) -> Void)?) {
        print("WatchConnectivityService: Handling request for locations")
        
        let locations = LocationStorageService.shared.loadSavedLocations()
        let selectedLoc = LocationStorageService.shared.loadSelectedLocation()
        
        var reply: [String: Any] = ["status": "ok"]
        if let data = try? JSONEncoder().encode(locations) {
            reply["locations"] = data
        }
        if let selectedLoc = selectedLoc, let data = try? JSONEncoder().encode(selectedLoc) {
            reply["selectedLocation"] = data
        }
        replyHandler?(reply)
    }
    
    nonisolated private func handleRequestConditions(replyHandler: (([String: Any]) -> Void)?) {
        print("WatchConnectivityService: Handling request for conditions")
        
        guard let replyHandler else { return }
        let replyHandlerBox = WatchReplyHandler(replyHandler)
        
        Task {
            let cacheService = CacheService()
            var reply: [String: Any] = ["status": "ok"]
            
            var conditions = await fetchFreshConditionsForWatchRequest()
            if conditions == nil {
                conditions = await cacheService.loadAsync()
            }

            if let conditions {
                let watchConditions = conditions.limitedToTonightCache()
                if let data = try? JSONEncoder().encode(watchConditions) {
                    reply["conditions"] = data
                } else {
                    replyHandlerBox.reply(["status": "error", "message": "Failed to encode conditions"])
                    return
                }
            } else {
                replyHandlerBox.reply(["status": "error", "message": "No cached conditions"])
                return
            }
            
            if let selectedLoc = LocationStorageService.shared.loadSelectedLocation(),
               let data = try? JSONEncoder().encode(selectedLoc) {
                reply["selectedLocation"] = data
            }
            
            replyHandlerBox.reply(reply)
        }
    }

    @MainActor
    private func fetchFreshConditionsForWatchRequest() async -> ViewingConditions? {
        guard let location = watchRequestLocation() else { return nil }

        let viewModel = DashboardViewModel(
            apiKey: UserDefaults.standard.string(forKey: "n2yoApiKey") ?? ""
        )
        await viewModel.refresh(for: location)

        guard viewModel.error == nil, let conditions = viewModel.viewingConditions else {
            return nil
        }

        await viewModel.saveToCache()
        return conditions
    }

    @MainActor
    private func watchRequestLocation() -> SavedLocation? {
        let selectedLocation = LocationStorageService.shared.loadSelectedLocation()
        let savedLocations = LocationStorageService.shared.loadSavedLocations()

        if let selectedLocation,
           selectedLocation.source == .saved,
           let selectedID = selectedLocation.id,
           let savedLocation = savedLocations.first(where: { $0.id == selectedID }) {
            return SavedLocation(cachedLocation: savedLocation)
        }

        if let selectedLocation, selectedLocation.latitude != 0, selectedLocation.longitude != 0 {
            return SavedLocation(
                name: selectedLocation.name,
                latitude: selectedLocation.latitude,
                longitude: selectedLocation.longitude
            )
        }

        if let cachedConditions = CacheService().load() {
            return SavedLocation(cachedLocation: cachedConditions.location)
        }

        return nil
    }
}

private extension SavedLocation {
    convenience init(cachedLocation: CachedLocation) {
        self.init(
            name: cachedLocation.name,
            latitude: cachedLocation.latitude,
            longitude: cachedLocation.longitude,
            elevation: cachedLocation.elevation
        )
        if let id = cachedLocation.id {
            self.id = id
        }
    }
}
