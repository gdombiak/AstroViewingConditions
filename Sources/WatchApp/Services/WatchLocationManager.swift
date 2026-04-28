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
    @Published var conditions: ViewingConditions?
    @Published var nightQuality: NightQualityAssessment?
    @Published var unitSystem: UnitSystem = .metric
    @Published var isLoading = false
    
    private let connectivityManager = WatchConnectivityManager.shared
    
    private init() {
        connectivityManager.delegate = self
        loadInitialState()
    }
    
    private func loadInitialState() {
        let storedLocations = loadStoredLocations()
        let storedSelected = AppGroupStorage.loadSelectedLocation()
            ?? iCloudKeyValueStorage.shared.loadSelectedLocation()
        let storedConditions = AppGroupStorage.loadConditionsWithTimestamp()
        let storedUnitSystem = AppGroupStorage.loadUnitSystem()
            .flatMap { UnitSystem(rawValue: $0) }
            ?? iCloudKeyValueStorage.shared.loadUnitSystem()
            .flatMap { UnitSystem(rawValue: $0) }
            ?? .metric
        
        DispatchQueue.main.async {
            self.locations = storedLocations
            self.selectedLocation = storedSelected
            self.unitSystem = storedUnitSystem
            if let storedConditions = storedConditions, !storedConditions.isStale {
                self.conditions = storedConditions.conditions
            }
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
        AppGroupStorage.saveConditions(conditions)
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async {
            self.conditions = conditions
            self.isLoading = false
        }
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
        
        async let locationsTask: Void = {
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
                print("WatchLocationManager: Failed to refresh locations: \(error)")
            }
        }()
        
        async let conditionsTask: Void = {
            do {
                let (conditions, selectedLocation) = try await connectivityManager.requestConditions()
                await MainActor.run {
                    self.conditions = conditions
                    if let selected = selectedLocation {
                        self.selectedLocation = selected
                    }
                }
                AppGroupStorage.saveConditions(conditions)
                if let selected = selectedLocation {
                    AppGroupStorage.saveSelectedLocation(selected)
                }
            } catch {
                print("WatchLocationManager: Failed to refresh conditions: \(error)")
            }
        }()
        
        _ = await (locationsTask, conditionsTask)
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
        let appGroupLocations = AppGroupStorage.loadSavedLocations()
        if !appGroupLocations.isEmpty {
            return appGroupLocations
        }
        let iCloudLocations = iCloudKeyValueStorage.shared.loadLocations()
        if !iCloudLocations.isEmpty {
            AppGroupStorage.saveSavedLocations(iCloudLocations)
        }
        return iCloudLocations
    }
}
