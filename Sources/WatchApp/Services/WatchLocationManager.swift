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
        
        // 1. Check iCloud first (source of truth) - fast since it's local cache
        let cloudLocations = iCloudKeyValueStorage.shared.loadLocations()
        let cloudSelected = iCloudKeyValueStorage.shared.loadSelectedLocation()
        
        // 2. Compare with App Group and update if different
        var storedLocations = loadStoredLocations()
        var locationsChanged = false
        
        if !cloudLocations.isEmpty {
            let appGroupNames = storedLocations.map { $0.name }
            let cloudNames = cloudLocations.map { $0.name }
            if appGroupNames != cloudNames {
                print("WatchLocationManager: Updating App Group with iCloud locations")
                AppGroupStorage.saveSavedLocations(cloudLocations)
                storedLocations = cloudLocations
                locationsChanged = true
            }
        }
        
        var storedSelected = connectivityManager.loadSelectedLocationFromStorage()
        
        if let cloudSel = cloudSelected {
            if let stored = storedSelected {
                if stored.name != cloudSel.name || stored.latitude != cloudSel.latitude || stored.longitude != cloudSel.longitude {
                    print("WatchLocationManager: Updating App Group with iCloud selected location")
                    AppGroupStorage.saveSelectedLocation(cloudSel)
                    storedSelected = cloudSel
                }
            } else {
                AppGroupStorage.saveSelectedLocation(cloudSel)
                storedSelected = cloudSel
            }
        }
        
        // 3. Build UI items
        var items: [WatchLocationItem] = [.currentLocation]
        
        if !storedLocations.isEmpty {
            print("WatchLocationManager: Using \(storedLocations.count) stored locations")
            items.append(contentsOf: storedLocations.map { WatchLocationItem.from($0) })
        } else {
            let receivedLocations = connectivityManager.receivedLocations
            if !receivedLocations.isEmpty {
                print("WatchLocationManager: Using \(receivedLocations.count) received locations")
                items.append(contentsOf: receivedLocations.map { WatchLocationItem.from($0) })
            } else {
                print("WatchLocationManager: No locations, requesting from iOS")
                connectivityManager.requestLocations()
            }
        }
        
        if let currentLocation = loadCurrentLocation() ?? connectivityManager.currentLocation {
            print("WatchLocationManager: Using current location: \(currentLocation.name)")
        }
        
        // 4. Determine selected location
        var newSelectedLocation: WatchLocationItem?
        
        if let selected = storedSelected {
            newSelectedLocation = WatchLocationItem.from(selected)
        } else if let selected = connectivityManager.selectedLocation {
            newSelectedLocation = WatchLocationItem.from(selected)
        }
        
        // 5. Update UI
        locations = items
        
        if let newSelected = newSelectedLocation {
            if selectedLocation.name != newSelected.name {
                selectedLocation = newSelected
                loadConditionsIfNeeded()
            } else if locationsChanged {
                // Locations changed, might need to refresh conditions
                loadConditionsIfNeeded()
            }
        } else {
            selectedLocation = items.first ?? .currentLocation
            loadConditionsIfNeeded()
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
        iCloudKeyValueStorage.shared.saveSelectedLocation(cached)
        AppGroupStorage.saveSelectedLocation(cached)
        connectivityManager.sendSelectedLocationToiOS(cached)
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
        AppGroupStorage.loadSavedLocations()
    }
    
    private func loadCurrentLocation() -> CachedLocation? {
        AppGroupStorage.loadCurrentLocation()
    }
    
    func loadConditionsIfNeeded() {
        // 1. Try App Group files first
        if let storedData = loadConditionsFromStorage() {
            if storedData.isStale {
                print("WatchLocationManager: Stored conditions stale, requesting fresh from iOS")
                connectivityManager.requestConditions()
            } else {
                print("WatchLocationManager: Using stored conditions")
                conditions = storedData.conditions
            }
        } else if let receivedConditions = connectivityManager.conditions {
            print("WatchLocationManager: Using received conditions")
            conditions = receivedConditions
        } else {
            print("WatchLocationManager: No conditions, requesting from iOS")
            connectivityManager.requestConditions()
        }
    }
    
    private func loadConditionsFromStorage() -> (conditions: ViewingConditions, isStale: Bool)? {
        guard let result = AppGroupStorage.loadConditionsWithTimestamp() else {
            return nil
        }
        return (conditions: result.conditions, isStale: result.isStale)
    }
    
    var hasConditions: Bool {
        conditions != nil
    }
}
