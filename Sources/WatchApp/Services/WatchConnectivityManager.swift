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
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateSelectedLocation location: SelectedLocation)
}

class WatchConnectivityManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager()
    
    weak var delegate: WatchConnectivityManagerDelegate?
    
    @Published var receivedLocations: [CachedLocation] = []
    @Published var selectedLocation: SelectedLocation?
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
        let conditionsData = applicationContext["conditions"] as? Data
        let selectedLocationData = applicationContext["selectedLocation"] as? Data
        let unitSystemData = applicationContext["unitSystem"] as? Data
        
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
                
            case "conditions":
                if let data = conditionsData,
                   let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                    print("WatchConnectivityManager: Received conditions from app context")
                    self.conditions = conditions
                    AppGroupStorage.saveConditions(conditions)
                    self.reloadComplications()
                    self.delegate?.connectivityManager(self, didUpdateConditions: conditions)
                }
                
            case "locationSync", "selectedLocation":
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(SelectedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location: \(location.name)")
                    self.selectedLocation = location
                    AppGroupStorage.saveSelectedLocation(location)
                    self.delegate?.connectivityManager(self, didUpdateSelectedLocation: location)
                }
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received location sync: \(locations.count) locations")
                    self.receivedLocations = locations
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didUpdateLocations: locations)
                }
                
            case "unitSystem":
                if let data = unitSystemData,
                   let unitSystem = try? JSONDecoder().decode(String.self, from: data) {
                    print("WatchConnectivityManager: Received unit system: \(unitSystem)")
                    AppGroupStorage.saveUnitSystem(unitSystem)
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
        let conditionsData = message["conditions"] as? Data
        let selectedLocationData = message["selectedLocation"] as? Data
        let unitSystemData = message["unitSystem"] as? Data
        
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
                
            case "conditions":
                if let data = conditionsData,
                   let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                    print("WatchConnectivityManager: Received conditions")
                    self.conditions = conditions
                    AppGroupStorage.saveConditions(conditions)
                    self.reloadComplications()
                    self.delegate?.connectivityManager(self, didUpdateConditions: conditions)
                }
                
            case "locationSync", "selectedLocation":
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(SelectedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location: \(location.name)")
                    self.selectedLocation = location
                    AppGroupStorage.saveSelectedLocation(location)
                    self.delegate?.connectivityManager(self, didUpdateSelectedLocation: location)
                }
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received location sync: \(locations.count) locations")
                    self.receivedLocations = locations
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didUpdateLocations: locations)
                }
                
            case "unitSystem":
                if let data = unitSystemData,
                   let unitSystem = try? JSONDecoder().decode(String.self, from: data) {
                    print("WatchConnectivityManager: Received unit system: \(unitSystem)")
                    AppGroupStorage.saveUnitSystem(unitSystem)
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
    
    func loadSelectedLocationFromStorage() -> SelectedLocation? {
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
