import SwiftUI
import Combine
import SharedCode
import WidgetKit

enum LocationError: Error, LocalizedError {
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Location access not authorized"
        }
    }
}

class WatchLocationManager: ObservableObject, @unchecked Sendable, WatchConnectivityManagerDelegate {
    static let shared = WatchLocationManager()
    
    @Published var locations: [CachedLocation] = []
    @Published var selectedLocation: SelectedLocation?
    @Published var unitSystem: UnitSystem = .metric
    @Published var isLoading = false
    
    private let connectivityManager = WatchConnectivityManager.shared
    
    private init() {
        connectivityManager.addDelegate(self)
        loadInitialState()
    }
    
    private func loadInitialState() {
        let storedLocations = loadStoredLocations()
        let storedSelected = AppGroupStorage.loadSelectedLocation()
            ?? iCloudKeyValueStorage.shared.loadSelectedLocation()
        let storedUnitSystem = AppGroupStorage.loadUnitSystem()
            .flatMap { UnitSystem(rawValue: $0) }
            ?? iCloudKeyValueStorage.shared.loadUnitSystem()
            .flatMap { UnitSystem(rawValue: $0) }
            ?? .metric
        
        DispatchQueue.main.async {
            self.locations = storedLocations
            self.selectedLocation = storedSelected
            self.unitSystem = storedUnitSystem
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?) {
        AppGroupStorage.saveSavedLocations(locations)
        DispatchQueue.main.async {
            self.locations = locations
            if let selected = selectedLocation {
                self.selectedLocation = selected
            }
            self.isLoading = false
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveConditions conditions: ViewingConditions) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation) {
        AppGroupStorage.saveSelectedLocation(location)
        DispatchQueue.main.async {
            self.selectedLocation = location
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem) {
        AppGroupStorage.saveUnitSystem(unitSystem.rawValue)
        Task { @MainActor in
            self.unitSystem = unitSystem
        }
    }
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        
        do {
            let (locations, selected) = try await connectivityManager.requestLocations()
            await MainActor.run {
                self.locations = locations
                if let selected = selected {
                    self.selectedLocation = selected
                }
            }
            AppGroupStorage.saveSavedLocations(locations)
            if let selected = selected {
                AppGroupStorage.saveSelectedLocation(selected)
            }
        } catch {
            print("WatchLocationManager: Watch connectivity failed for locations: \(error.localizedDescription), using cached")
            let cachedLocations = loadStoredLocations()
            let cachedSelected = AppGroupStorage.loadSelectedLocation()
            await MainActor.run {
                self.locations = cachedLocations
                self.selectedLocation = cachedSelected
            }
        }
        
        await MainActor.run { isLoading = false }
    }
    
    func select(_ location: CachedLocation) {
        let selected = SelectedLocation(
            source: .saved,
            id: location.id,
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude
        )
        selectedLocation = selected
        LocationStorageService.shared.saveSelectedLocation(selected)
        connectivityManager.sendSelectedLocationToiOS(selected)
    }
    
    func selectCurrentLocation() {
        let selected = SelectedLocation(
            source: .currentGPS,
            name: "Current Location",
            latitude: 0,
            longitude: 0
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
        
        let locManager = await MainActor.run { LocationManager() }
        
        if await locManager.authorizationStatus == .notDetermined {
            await locManager.requestAuthorization()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        
        guard await locManager.isAuthorized else {
            throw LocationError.notAuthorized
        }
        
        let coord = try await locManager.getCurrentLocation()
        return (coord.latitude, coord.longitude)
    }
    
    private func loadStoredLocations() -> [CachedLocation] {
        LocationStorageService.shared.loadSavedLocations()
    }
}
