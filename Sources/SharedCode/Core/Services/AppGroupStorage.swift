import Foundation
import os

private let logger = Logger(subsystem: "com.astroviewing.conditions", category: "AppGroupStorage")

extension Notification.Name {
    public static let watchLocationSelected = Notification.Name("watchLocationSelected")
    public static let widgetLocationDidChange = Notification.Name("widgetLocationDidChange")
    public static let widgetConditionsDidChange = Notification.Name("widgetConditionsDidChange")
}

public struct AppGroupStorage: Sendable {
    public static let suiteName = "group.com.astroviewing.conditions"
    
    private static let fileQueue = DispatchQueue(label: "com.astroviewing.storage", qos: .utility)
    
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }
    
    // MARK: - Widget Location
    
    public static func saveWidgetLocation(_ location: CachedLocation) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        let data: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "name": location.name
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let fileURL = baseURL.appendingPathComponent("widgetLocation.json")
            try jsonData.write(to: fileURL, options: .atomic)
            
            NotificationCenter.default.post(name: .widgetLocationDidChange, object: nil)
        } catch {
            logger.error("Failed to save widget location: \(error.localizedDescription)")
        }
    }

    public static func loadWidgetLocation() -> (latitude: Double, longitude: Double, name: String)? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("widgetLocation.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let lat = json?["latitude"] as? Double,
                  let lon = json?["longitude"] as? Double,
                  let name = json?["name"] as? String else {
                logger.warning("Widget location data is incomplete")
                return nil
            }
            return (lat, lon, name)
        } catch {
            logger.warning("Failed to load widget location: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Widget Conditions
    
    public static func saveWidgetConditions(_ conditions: ViewingConditions) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(conditions)
            let fileURL = baseURL.appendingPathComponent("widgetConditions.json")
            try data.write(to: fileURL, options: .atomic)
            
            NotificationCenter.default.post(name: .widgetConditionsDidChange, object: nil)
        } catch {
            logger.error("Failed to save widget conditions: \(error.localizedDescription)")
        }
    }

    public static func loadWidgetConditions() -> ViewingConditions? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("widgetConditions.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ViewingConditions.self, from: data)
        } catch {
            logger.warning("Failed to load widget conditions: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Saved Locations
    
    public static func saveSavedLocations(_ locations: [CachedLocation]) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(locations)
            let fileURL = baseURL.appendingPathComponent("savedLocations.json")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save locations: \(error.localizedDescription)")
        }
    }
    
    public static func loadSavedLocations() -> [CachedLocation] {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return []
        }
        
        let fileURL = baseURL.appendingPathComponent("savedLocations.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([CachedLocation].self, from: data)
        } catch {
            logger.warning("Failed to load locations: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Selected Location
    
    public static func saveSelectedLocation(_ location: CachedLocation) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(location)
            let fileURL = baseURL.appendingPathComponent("selectedLocation.json")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save selected location: \(error.localizedDescription)")
        }
    }
    
    public static func loadSelectedLocation() -> CachedLocation? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("selectedLocation.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(CachedLocation.self, from: data)
        } catch {
            logger.warning("Failed to load selected location: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Current Location
    
    public static func saveCurrentLocation(_ location: CachedLocation) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(location)
            let fileURL = baseURL.appendingPathComponent("currentLocation.json")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save current location: \(error.localizedDescription)")
        }
    }
    
    public static func loadCurrentLocation() -> CachedLocation? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("currentLocation.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(CachedLocation.self, from: data)
        } catch {
            logger.warning("Failed to load current location: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Conditions
    
    public static func saveConditions(_ conditions: ViewingConditions, timestamp: Date = Date()) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(conditions)
            let fileURL = baseURL.appendingPathComponent("conditions.json")
            try data.write(to: fileURL, options: .atomic)
            
            let tsData = try JSONEncoder().encode(timestamp)
            let tsFileURL = baseURL.appendingPathComponent("conditionsTimestamp.json")
            try tsData.write(to: tsFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save conditions: \(error.localizedDescription)")
        }
    }
    
    public static func loadConditions() -> ViewingConditions? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("conditions.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ViewingConditions.self, from: data)
        } catch {
            logger.warning("Failed to load conditions: \(error.localizedDescription)")
            return nil
        }
    }
    
    public static func loadConditionsTimestamp() -> Date? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("conditionsTimestamp.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Date.self, from: data)
        } catch {
            return nil
        }
    }
    
    public static func loadConditionsWithTimestamp() -> (conditions: ViewingConditions, timestamp: Date, isStale: Bool)? {
        guard let conditions = loadConditions(),
              let timestamp = loadConditionsTimestamp() else {
            return nil
        }
        
        let isStale = Date().timeIntervalSince(timestamp) > 3600
        return (conditions, timestamp, isStale)
    }
    
    public static func clearConditions() {
        guard let baseURL = containerURL else { return }
        
        let conditionsFile = baseURL.appendingPathComponent("conditions.json")
        let timestampFile = baseURL.appendingPathComponent("conditionsTimestamp.json")
        
        try? FileManager.default.removeItem(at: conditionsFile)
        try? FileManager.default.removeItem(at: timestampFile)
        logger.info("Cleared conditions cache")
    }
    
    // MARK: - Best Spot Settings
    
    public static func saveBestSpotSettings(searchRadius: Double, gridSpacing: Double) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        let data: [String: Any] = [
            "searchRadius": searchRadius,
            "gridSpacing": gridSpacing
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let fileURL = baseURL.appendingPathComponent("bestSpotSettings.json")
            try jsonData.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save best spot settings: \(error.localizedDescription)")
        }
    }
    
    public static func loadBestSpotSettings() -> (searchRadius: Double, gridSpacing: Double)? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("bestSpotSettings.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let searchRadius = json["searchRadius"] as? Double,
                  let gridSpacing = json["gridSpacing"] as? Double else {
                return nil
            }
            
            let validatedRadius = BestSpotSettings.validateSearchRadius(searchRadius)
            let validatedSpacing = BestSpotSettings.validateGridSpacing(gridSpacing)
            
            return (validatedRadius, validatedSpacing)
        } catch {
            return nil
        }
    }
    
    // MARK: - Unit System
    
    public static func saveUnitSystem(_ unitSystem: String) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(unitSystem)
            let fileURL = baseURL.appendingPathComponent("unitSystem.json")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save unit system: \(error.localizedDescription)")
        }
    }
    
    public static func loadUnitSystem() -> String? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("unitSystem.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(String.self, from: data)
        } catch {
            return nil
        }
    }
    
    // MARK: - Selected Location ID
    
    public static func saveSelectedLocationID(_ id: String) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(id)
            let fileURL = baseURL.appendingPathComponent("selectedLocationID.json")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save selected location ID: \(error.localizedDescription)")
        }
    }
    
    public static func loadSelectedLocationID() -> String? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("selectedLocationID.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(String.self, from: data)
        } catch {
            return nil
        }
    }
}