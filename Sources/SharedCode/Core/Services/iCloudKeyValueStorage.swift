import Foundation
import os

public final class iCloudKeyValueStorage: @unchecked Sendable {
    public static let shared = iCloudKeyValueStorage()
    
    private let store = NSUbiquitousKeyValueStore.default
    private let logger = Logger(subsystem: "com.astroviewing.conditions", category: "iCloudKeyValue")
    
    public static let syncErrorNotification = Notification.Name("iCloudKeyValueSyncError")
    
    private struct Keys {
        static let savedLocations = "iCloud_savedLocations"
        static let selectedLocation = "iCloud_selectedLocation"
        static let bestSpotSettings = "iCloud_bestSpotSettings"
        static let unitSystem = "iCloud_unitSystem"
    }
    
    private init() {}
    
    public var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
    
    public func synchronize() {
        store.synchronize()
    }
    
    public func saveLocations(_ locations: [CachedLocation]) {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        store.set(data, forKey: Keys.savedLocations)
        logger.info("Saved \(locations.count) locations to iCloud")
    }
    
    public func loadLocations() -> [CachedLocation] {
        guard let data = store.data(forKey: Keys.savedLocations),
              let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) else {
            return []
        }
        logger.info("Loaded \(locations.count) locations from iCloud")
        return locations
    }
    
    public func saveSelectedLocation(_ location: SelectedLocation) {
        guard let data = try? JSONEncoder().encode(location) else { return }
        store.set(data, forKey: Keys.selectedLocation)
        logger.info("Saved selected location to iCloud")
    }
    
    public func loadSelectedLocation() -> SelectedLocation? {
        guard let data = store.data(forKey: Keys.selectedLocation),
              let location = try? JSONDecoder().decode(SelectedLocation.self, from: data) else {
            return nil
        }
        logger.info("Loaded selected location from iCloud")
        return location
    }
    
    public func saveBestSpotSettings(searchRadius: Double, gridSpacing: Double) {
        let data: [String: Any] = [
            "searchRadius": searchRadius,
            "gridSpacing": gridSpacing
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return }
        store.set(jsonData, forKey: Keys.bestSpotSettings)
        logger.info("Saved best spot settings to iCloud")
    }
    
    public func loadBestSpotSettings() -> (searchRadius: Double, gridSpacing: Double)? {
        guard let data = store.data(forKey: Keys.bestSpotSettings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let searchRadius = json["searchRadius"] as? Double,
              let gridSpacing = json["gridSpacing"] as? Double else {
            return nil
        }
        logger.info("Loaded best spot settings from iCloud")
        return (searchRadius, gridSpacing)
    }
    
    public func saveUnitSystem(_ unitSystem: String) {
        store.set(unitSystem, forKey: Keys.unitSystem)
        logger.info("Saved unit system to iCloud")
    }
    
    public func loadUnitSystem() -> String? {
        store.string(forKey: Keys.unitSystem)
    }
}