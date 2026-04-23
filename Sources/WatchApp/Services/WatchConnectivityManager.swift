import Foundation
import WatchConnectivity
import WidgetKit
import SharedCode

extension Notification.Name {
    static let selectedLocationChanged = Notification.Name("selectedLocationChanged")
    static let locationsUpdated = Notification.Name("locationsUpdated")
    static let conditionsUpdated = Notification.Name("conditionsUpdated")
}

protocol WatchConnectivityManagerDelegate: AnyObject {
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateLocations locations: [CachedLocation])
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateConditions conditions: ViewingConditions)
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateSelectedLocation location: CachedLocation)
}

class WatchConnectivityManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager()
    
    weak var delegate: WatchConnectivityManagerDelegate?
    
    @Published var receivedLocations: [CachedLocation] = []
    @Published var selectedLocation: CachedLocation?
    @Published var currentLocation: CachedLocation?
    @Published var conditions: ViewingConditions?
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func requestLocations() {
        print("WatchConnectivityManager: Requesting locations from iOS")
        guard WCSession.default.isReachable else {
            print("WatchConnectivityManager: Session not reachable")
            return
        }
        
        WCSession.default.sendMessage(["type": "requestLocations"], replyHandler: { reply in
            print("WatchConnectivityManager: Request locations reply: \(reply)")
        }, errorHandler: { error in
            print("WatchConnectivityManager: Failed to request locations: \(error)")
        })
    }
    
    func sendSelectedLocationToiOS(_ location: CachedLocation) {
        print("WatchConnectivityManager: Sending selected location to iOS: \(location.name)")
        guard WCSession.default.isReachable else {
            print("WatchConnectivityManager: Session not reachable, saved to iCloud only")
            return
        }
        
        guard let data = try? JSONEncoder().encode(location) else { return }
        WCSession.default.sendMessage(
            ["type": "selectedLocationFromWatch", "selectedLocation": data],
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
    }
    
    func requestConditions() {
        print("WatchConnectivityManager: Requesting conditions from iOS")
        guard WCSession.default.isReachable else {
            print("WatchConnectivityManager: Session not reachable")
            return
        }
        
        WCSession.default.sendMessage(["type": "requestConditions"], replyHandler: { reply in
            print("WatchConnectivityManager: Request conditions reply: \(reply)")
        }, errorHandler: { error in
            print("WatchConnectivityManager: Failed to request conditions: \(error)")
        })
    }
    
    func sendSelectedLocationToWatch(_ location: CachedLocation) {
        print("WatchConnectivityManager: Sending selected location to iOS: \(location.name)")
        guard let data = try? JSONEncoder().encode(location) else { return }
        
        WCSession.default.sendMessage(["type": "selectedLocation", "selectedLocation": data], replyHandler: { reply in
            print("WatchConnectivityManager: Sent selected location, reply: \(reply)")
        }, errorHandler: { error in
            print("WatchConnectivityManager: Failed to send selected location: \(error)")
        })
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("WatchConnectivityManager: Activation complete: \(activationState.rawValue)")
        
        if activationState == .activated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.requestLocations()
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("WatchConnectivityManager: Received application context: \(applicationContext)")
        
        guard let type = applicationContext["type"] as? String else { return }
        
        let locationsData = applicationContext["locations"] as? Data
        let locationData = applicationContext["location"] as? Data
        let conditionsData = applicationContext["conditions"] as? Data
        let selectedLocationData = applicationContext["selectedLocation"] as? Data
        
        DispatchQueue.main.async {
            switch type {
            case "savedLocations":
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received \(locations.count) locations from app context")
                    self.receivedLocations = locations
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didUpdateLocations: locations)
                }
                
            case "currentLocation":
                if let data = locationData,
                   let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received current location from app context: \(location.name)")
                    self.currentLocation = location
                    AppGroupStorage.saveCurrentLocation(location)
                }
                
            case "conditions":
                if let data = conditionsData,
                   let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                    print("WatchConnectivityManager: Received conditions from app context")
                    self.conditions = conditions
                    AppGroupStorage.saveConditions(conditions)
                    self.reloadComplications()
                    self.delegate?.connectivityManager(self, didUpdateConditions: conditions)
                }
                
            case "locationSync":
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received location sync: \(locations.count) locations")
                    self.receivedLocations = locations
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didUpdateLocations: locations)
                }
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location: \(location.name)")
                    self.selectedLocation = location
                    AppGroupStorage.saveSelectedLocation(location)
                    self.delegate?.connectivityManager(self, didUpdateSelectedLocation: location)
                }
                
            case "selectedLocation":
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location: \(location.name)")
                    self.selectedLocation = location
                    AppGroupStorage.saveSelectedLocation(location)
                    self.delegate?.connectivityManager(self, didUpdateSelectedLocation: location)
                }
                
            default:
                print("WatchConnectivityManager: Unknown application context type: \(type)")
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        print("WatchConnectivityManager: Received message: \(message)")
        
        guard let type = message["type"] as? String else { return }
        
        let locationsData = message["locations"] as? Data
        let locationData = message["location"] as? Data
        let conditionsData = message["conditions"] as? Data
        let selectedLocationData = message["selectedLocation"] as? Data
        
        DispatchQueue.main.async {
            switch type {
            case "savedLocations":
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received \(locations.count) locations")
                    self.receivedLocations = locations
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didUpdateLocations: locations)
                }
                
            case "currentLocation":
                if let data = locationData,
                   let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received current location: \(location.name)")
                    self.currentLocation = location
                    AppGroupStorage.saveCurrentLocation(location)
                }
                
            case "conditions":
                if let data = conditionsData,
                   let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                    print("WatchConnectivityManager: Received conditions")
                    self.conditions = conditions
                    AppGroupStorage.saveConditions(conditions)
                    self.reloadComplications()
                    self.delegate?.connectivityManager(self, didUpdateConditions: conditions)
                }
                
            case "locationSync":
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received location sync: \(locations.count) locations")
                    self.receivedLocations = locations
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didUpdateLocations: locations)
                }
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location: \(location.name)")
                    self.selectedLocation = location
                    AppGroupStorage.saveSelectedLocation(location)
                    self.delegate?.connectivityManager(self, didUpdateSelectedLocation: location)
                }
                
            case "selectedLocation":
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location: \(location.name)")
                    self.selectedLocation = location
                    AppGroupStorage.saveSelectedLocation(location)
                    self.delegate?.connectivityManager(self, didUpdateSelectedLocation: location)
                }
                
            default:
                print("WatchConnectivityManager: Unknown message type: \(type)")
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WatchConnectivityManager: Reachability changed: \(session.isReachable)")
        if session.isReachable {
            requestLocations()
        }
    }
    
    func loadSelectedLocationFromStorage() -> CachedLocation? {
        return AppGroupStorage.loadSelectedLocation()
    }
    
    func loadConditionsFromStorage() -> (conditions: ViewingConditions, isStale: Bool)? {
        guard let result = AppGroupStorage.loadConditionsWithTimestamp() else {
            return nil
        }
        return (conditions: result.conditions, isStale: result.isStale)
    }
    
    private func reloadComplications() {
        print("WatchConnectivityManager: Reloading complications")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
