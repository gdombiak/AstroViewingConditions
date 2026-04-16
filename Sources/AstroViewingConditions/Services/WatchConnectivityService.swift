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
    
    public func sendSelectedLocationToWatch(_ location: CachedLocation) {
        guard let data = try? JSONEncoder().encode(location) else { return }
        sendViaApplicationContext(type: "selectedLocation", payload: ["selectedLocation": data])
    }
    
    public func sendLocationSyncToWatch(locations: [CachedLocation], selectedLocation: CachedLocation?) {
        guard let locationsData = try? JSONEncoder().encode(locations) else { return }
        var payload: [String: Any] = ["locations": locationsData]
        if let selectedLocation = selectedLocation, let data = try? JSONEncoder().encode(selectedLocation) {
            payload["selectedLocation"] = data
        }
        sendViaApplicationContext(type: "locationSync", payload: payload)
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
    
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("WatchConnectivityService: Received message: \(message)")
        handleMessage(message)
    }
    
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        print("WatchConnectivityService: Received userInfo: \(userInfo)")
        handleMessage(userInfo)
    }
    
    private func handleMessage(_ message: [String: Any]) {
        if let type = message["type"] as? String {
            switch type {
            case "requestLocations":
                handleRequestLocations()
            case "requestConditions":
                handleRequestConditions()
            case "selectedLocation":
                if let data = message["selectedLocation"] as? Data,
                   let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                    print("WatchConnectivityService: Received location selection from Watch: \(location.name)")
                    SharedStorage.saveWidgetLocation(location)
                    refreshForLocation(location: location)
                }
            default:
                print("WatchConnectivityService: Unknown message type: \(type)")
            }
        }
    }
    
    private func refreshForLocation(location: CachedLocation) {
        let savedLocation = SavedLocation(
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        NotificationCenter.default.post(
            name: .watchLocationSelected,
            object: savedLocation
        )
    }
    
    private func handleRequestLocations() {
        print("WatchConnectivityService: Handling request for locations")
        guard let session = session, session.isReachable else { return }
        
        let locations = LocationSyncService.shared.getSavedLocationsFromAppGroup()
        var selectedLoc: CachedLocation? = nil
        if let widgetLoc = SharedStorage.loadWidgetLocation() {
            selectedLoc = CachedLocation(
                name: widgetLoc.name,
                latitude: widgetLoc.latitude,
                longitude: widgetLoc.longitude,
                elevation: nil
            )
        }
        sendLocationSyncToWatch(locations: locations, selectedLocation: selectedLoc)
    }
    
    private func handleRequestConditions() {
        print("WatchConnectivityService: Handling request for conditions")
        guard let session = session, session.isReachable else { return }
        
        let cacheService = CacheService()
        if let conditions = cacheService.load() {
            sendConditionsToWatch(conditions)
        }
    }
}