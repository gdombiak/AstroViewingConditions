import SwiftUI
import Combine
import SharedCode

class WatchLocationManager: ObservableObject, @unchecked Sendable, WatchConnectivityManagerDelegate {
    static let shared = WatchLocationManager()
    
    @Published var locations: [WatchLocationItem] = [.currentLocation]
    @Published var selectedLocation: WatchLocationItem = .currentLocation
    @Published var conditions: ViewingConditions?
    @Published var isLoading = false
    
    private let connectivityManager = WatchConnectivityManager.shared
    
    private init() {
        connectivityManager.delegate = self
        loadLocations()
        loadConditionsIfNeeded()
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateLocations locations: [CachedLocation]) {
        print("WatchLocationManager: Received didUpdateLocations delegate call")
        loadLocations()
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateConditions conditions: ViewingConditions) {
        print("WatchLocationManager: Received didUpdateConditions delegate call")
        self.conditions = conditions
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateSelectedLocation location: CachedLocation) {
        print("WatchLocationManager: Received didUpdateSelectedLocation delegate call for \(location.name)")
        handleSelectedLocationChanged(location)
    }
    
    private func handleSelectedLocationChanged(_ location: CachedLocation) {
        let watchItem = WatchLocationItem.from(location)
        if locations.contains(where: { $0.name == location.name }) {
            selectedLocation = watchItem
        }
    }
    
    func loadLocations() {
        print("WatchLocationManager: loadLocations called")
        var items: [WatchLocationItem] = [.currentLocation]
        
        let receivedLocations = connectivityManager.receivedLocations
        if !receivedLocations.isEmpty {
            print("WatchLocationManager: Using \(receivedLocations.count) received locations")
            items.append(contentsOf: receivedLocations.map { WatchLocationItem.from($0) })
        } else {
            let storedLocations = loadStoredLocations()
            if !storedLocations.isEmpty {
                print("WatchLocationManager: Using \(storedLocations.count) stored locations")
                items.append(contentsOf: storedLocations.map { WatchLocationItem.from($0) })
            } else {
                print("WatchLocationManager: No locations, requesting from iOS")
                connectivityManager.requestLocations()
            }
        }
        
        if let currentLocation = connectivityManager.currentLocation ?? loadCurrentLocation() {
            print("WatchLocationManager: Using current location: \(currentLocation.name)")
        }
        
        locations = items
        
        if items.contains(where: { $0.name == selectedLocation.name }) {
            // Keep the current selection
        } else if let selected = connectivityManager.selectedLocation {
            let watchItem = WatchLocationItem.from(selected)
            selectedLocation = watchItem
        } else if let storedSelected = connectivityManager.loadSelectedLocationFromStorage() {
            selectedLocation = WatchLocationItem.from(storedSelected)
        } else {
            selectedLocation = items.first ?? .currentLocation
        }
    }
    
    func refresh() {
        isLoading = true
        connectivityManager.requestLocations()
        connectivityManager.requestConditions()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.loadLocations()
            self.loadConditionsIfNeeded()
            self.isLoading = false
        }
    }
    
    func select(_ location: WatchLocationItem) {
        selectedLocation = location
        
        guard location.name != "Current Location" else { return }
        
        let cached = CachedLocation(
            name: location.name,
            latitude: location.coordinate?.latitude ?? 0,
            longitude: location.coordinate?.longitude ?? 0,
            elevation: nil
        )
        connectivityManager.sendSelectedLocationToWatch(cached)
    }
    
    var activeCoordinate: Coordinate? {
        if selectedLocation.name == "Current Location" {
            return nil
        }
        return selectedLocation.coordinate
    }
    
    func getCurrentCoordinate() async throws -> (latitude: Double, longitude: Double) {
        if let coord = activeCoordinate {
            return (coord.latitude, coord.longitude)
        }
        
        let locManager = LocationManager()
        
        if locManager.authorizationStatus == .notDetermined {
            locManager.requestAuthorization()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        guard locManager.isAuthorized else {
            throw LocationError.notAuthorized
        }
        
        let coord = try await locManager.getCurrentLocation()
        return (coord.latitude, coord.longitude)
    }
    
    private func loadStoredLocations() -> [CachedLocation] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "savedLocations"),
              let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) else {
            return []
        }
        return locations
    }
    
    private func loadCurrentLocation() -> CachedLocation? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "currentLocation"),
              let location = try? JSONDecoder().decode(CachedLocation.self, from: data) else {
            return nil
        }
        return location
    }
    
    func loadConditionsIfNeeded() {
        if let receivedConditions = connectivityManager.conditions {
            print("WatchLocationManager: Using received conditions")
            conditions = receivedConditions
            return
        }
        
        if let storedData = loadConditionsFromStorage() {
            if storedData.isStale {
                print("WatchLocationManager: Conditions stale, requesting fresh from iOS")
                connectivityManager.requestConditions()
            } else {
                print("WatchLocationManager: Using stored conditions")
                conditions = storedData.conditions
            }
        } else {
            print("WatchLocationManager: No conditions, requesting from iOS")
            connectivityManager.requestConditions()
        }
    }
    
    private func loadConditionsFromStorage() -> (conditions: ViewingConditions, isStale: Bool)? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: "conditions"),
              let storedConditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) else {
            return nil
        }
        
        let timestamp = defaults.object(forKey: "conditionsTimestamp") as? Date ?? Date.distantPast
        let isStale = Date().timeIntervalSince(timestamp) > 3600
        return (storedConditions, isStale)
    }
    
    var hasConditions: Bool {
        conditions != nil
    }
}
