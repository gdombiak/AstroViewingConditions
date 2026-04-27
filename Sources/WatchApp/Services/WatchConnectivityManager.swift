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
        case .sessionNotReachable: return "Watch not connected to iPhone"
        case .requestFailed(let msg): return msg
        case .decodeFailed(let msg): return msg
        }
    }
}

protocol WatchConnectivityManagerDelegate: AnyObject {
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?)
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveConditions conditions: ViewingConditions)
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation)
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem)
}

class WatchConnectivityManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = WatchConnectivityManager()
    
    weak var delegate: WatchConnectivityManagerDelegate?
    
    private var locationContinuations: [UUID: CheckedContinuation<([CachedLocation], SelectedLocation?), Error>] = [:]
    private var conditionsContinuations: [UUID: CheckedContinuation<ViewingConditions, Error>] = [:]
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func requestLocations() async throws -> ([CachedLocation], SelectedLocation?) {
        guard WCSession.default.isReachable else {
            throw WatchConnectivityError.sessionNotReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            locationContinuations[id] = continuation
            
            WCSession.default.sendMessage(
                ["type": "requestLocations", "id": id.uuidString],
                replyHandler: { [weak self] reply in
                    self?.handleLocationReply(reply, id: id)
                },
                errorHandler: { [weak self] error in
                    self?.locationContinuations.removeValue(forKey: id)?.resume(throwing: error)
                }
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.locationContinuations.removeValue(forKey: id)?.resume(throwing: WatchConnectivityError.requestFailed("Request timed out"))
            }
        }
    }
    
    func requestConditions() async throws -> ViewingConditions {
        guard WCSession.default.isReachable else {
            throw WatchConnectivityError.sessionNotReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            conditionsContinuations[id] = continuation
            
            WCSession.default.sendMessage(
                ["type": "requestConditions", "id": id.uuidString],
                replyHandler: { [weak self] reply in
                    self?.handleConditionsReply(reply, id: id)
                },
                errorHandler: { [weak self] error in
                    self?.conditionsContinuations.removeValue(forKey: id)?.resume(throwing: error)
                }
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.conditionsContinuations.removeValue(forKey: id)?.resume(throwing: WatchConnectivityError.requestFailed("Request timed out"))
            }
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
            locationContinuations.removeValue(forKey: id)?.resume(throwing: WatchConnectivityError.requestFailed(message))
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
        
        locationContinuations.removeValue(forKey: id)?.resume(returning: (locations, selected))
    }
    
    private func handleConditionsReply(_ reply: [String: Any], id: UUID) {
        guard let status = reply["status"] as? String, status == "ok" else {
            let message = reply["message"] as? String ?? "Unknown error"
            conditionsContinuations.removeValue(forKey: id)?.resume(throwing: WatchConnectivityError.requestFailed(message))
            return
        }
        
        if let data = reply["conditions"] as? Data,
           let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
            conditionsContinuations.removeValue(forKey: id)?.resume(returning: conditions)
        } else {
            conditionsContinuations.removeValue(forKey: id)?.resume(throwing: WatchConnectivityError.decodeFailed("Failed to decode conditions"))
        }
    }
    
    private func reloadComplications() {
        print("WatchConnectivityManager: Reloading complications")
        WidgetCenter.shared.reloadAllTimelines()
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
        
        DispatchQueue.main.async {
            switch type {
            case "savedLocations":
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received \(locations.count) locations from \(source)")
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didReceiveLocations: locations, selectedLocation: nil)
                }
                
            case "conditions":
                if let data = conditionsData,
                   let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                    print("WatchConnectivityManager: Received conditions from \(source)")
                    AppGroupStorage.saveConditions(conditions)
                    self.reloadComplications()
                    self.delegate?.connectivityManager(self, didReceiveConditions: conditions)
                }
                
            case "locationSync", "selectedLocation":
                if let data = selectedLocationData,
                   let location = try? JSONDecoder().decode(SelectedLocation.self, from: data) {
                    print("WatchConnectivityManager: Received selected location from \(source): \(location.name)")
                    AppGroupStorage.saveSelectedLocation(location)
                    self.delegate?.connectivityManager(self, didReceiveSelectedLocation: location)
                }
                if let data = locationsData,
                   let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                    print("WatchConnectivityManager: Received location sync from \(source): \(locations.count) locations")
                    AppGroupStorage.saveSavedLocations(locations)
                    self.delegate?.connectivityManager(self, didReceiveLocations: locations, selectedLocation: nil)
                }
                
            case "unitSystem":
                if let data = unitSystemData,
                   let unitSystem = try? JSONDecoder().decode(String.self, from: data) {
                    print("WatchConnectivityManager: Received unit system: \(unitSystem)")
                    AppGroupStorage.saveUnitSystem(unitSystem)
                    if let system = UnitSystem(rawValue: unitSystem) {
                        self.delegate?.connectivityManager(self, didReceiveUnitSystem: system)
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
