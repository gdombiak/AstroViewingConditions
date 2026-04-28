import Foundation
import WatchConnectivity
import SharedCode

public class WatchConnectivityService: NSObject, ObservableObject, @unchecked Sendable {
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
            sendMessage(type: type, payload: payload)
        }
    }
    
    private func sendMessage(type: String, payload: [String: Any]) {
        guard let session = session, session.isReachable else {
            print("WatchConnectivityService: Session not reachable for type: \(type)")
            return
        }
        
        session.sendMessage(payload, replyHandler: { reply in
            print("WatchConnectivityService: Sent \(type), reply: \(reply)")
        }, errorHandler: { error in
            print("WatchConnectivityService: Failed to send \(type): \(error.localizedDescription)")
        })
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let isPaired = session.isPaired
        print("WatchConnectivityService: Activation state: \(activationState.rawValue)")
        DispatchQueue.main.async {
            self.isPaired = isPaired
        }
    }
    
    public func sessionDidBecomeInactive(_ session: WCSession) {
        print("WatchConnectivityService: Session became inactive")
    }
    
    public func sessionDidDeactivate(_ session: WCSession) {
        print("WatchConnectivityService: Session deactivated")
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        print("WatchConnectivityService: Reachability changed: \(isReachable)")
        DispatchQueue.main.async {
            self.isReachable = isReachable
        }
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        print("WatchConnectivityService: Received message: \(message)")
        handleMessage(message, replyHandler: replyHandler)
    }
    
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        print("WatchConnectivityService: Received userInfo: \(userInfo)")
        handleMessage(userInfo)
    }
    
    private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
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
    
    private func refreshForLocation(location: SelectedLocation) {
        LocationStorageService.shared.saveSelectedLocation(location)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .watchLocationSelected,
                object: location
            )
        }
    }
    
    private func handleRequestLocations(replyHandler: (([String: Any]) -> Void)?) {
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
    
    private func handleRequestConditions(replyHandler: (([String: Any]) -> Void)?) {
        print("WatchConnectivityService: Handling request for conditions")
        
        let cacheService = CacheService()
        var reply: [String: Any] = ["status": "ok"]
        
        if let conditions = cacheService.load() {
            if let data = try? JSONEncoder().encode(conditions) {
                reply["conditions"] = data
            } else {
                replyHandler?(["status": "error", "message": "Failed to encode conditions"])
                return
            }
        } else {
            replyHandler?(["status": "error", "message": "No cached conditions"])
            return
        }
        
        if let selectedLoc = LocationStorageService.shared.loadSelectedLocation(),
           let data = try? JSONEncoder().encode(selectedLoc) {
            reply["selectedLocation"] = data
        }
        
        replyHandler?(reply)
    }
}
