import SwiftUI
import Combine
import SharedCode

class WatchLocationManager: ObservableObject, @unchecked Sendable, WatchConnectivityManagerDelegate {
    static let shared = WatchLocationManager()
    
    @Published var locations: [WatchLocationItem] = [.currentLocation]
    @Published var selectedLocation: SelectedLocation?
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
    
    func connectivityManager(_ manager: WatchConnectivityManager, didUpdateSelectedLocation location: SelectedLocation) {
        print("WatchLocationManager: Received didUpdateSelectedLocation delegate call for \(location.name)")
        handleSelectedLocationChanged(location)
    }
    
    private func handleSelectedLocationChanged(_ location: SelectedLocation) {
        selectedLocation = location
        loadConditionsIfNeeded()
    }
    
    func loadLocations() {
        print("WatchLocationManager: loadLocations called")
        
        let storedLocations = loadStoredLocations()
        let storedSelected = AppGroupStorage.loadSelectedLocation()
            ?? iCloudKeyValueStorage.shared.loadSelectedLocation()
        
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
        
        locations = items
        
        if let selected = storedSelected {
            if selectedLocation?.id != selected.id {
                selectedLocation = selected
                loadConditionsIfNeeded()
            }
        } else if let selected = connectivityManager.selectedLocation {
            selectedLocation = selected
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
        guard location.name != "Current Location" else {
            let selected = SelectedLocation(
                source: .currentGPS,
                name: location.name,
                latitude: location.coordinate?.latitude ?? 0,
                longitude: location.coordinate?.longitude ?? 0
            )
            selectedLocation = selected
            LocationStorageService.shared.saveSelectedLocation(selected)
            connectivityManager.sendSelectedLocationToiOS(selected)
            return
        }
        
        let selected = SelectedLocation(
            source: .saved,
            id: location.id,
            name: location.name,
            latitude: location.coordinate?.latitude ?? 0,
            longitude: location.coordinate?.longitude ?? 0
        )
        selectedLocation = selected
        LocationStorageService.shared.saveSelectedLocation(selected)
        connectivityManager.sendSelectedLocationToiOS(selected)
    }
    
    var activeCoordinate: Coordinate? {
        guard let selected = selectedLocation else { return nil }
        if selected.source == .currentGPS {
            return nil
        }
        return Coordinate(latitude: selected.latitude, longitude: selected.longitude)
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
    
    func loadConditionsIfNeeded() {
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
