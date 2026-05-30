import Foundation
import os

private let logger = Logger(subsystem: "com.astroviewing.conditions", category: "AppGroupStorage")

extension Notification.Name {
    public static let watchLocationSelected = Notification.Name("watchLocationSelected")
    public static let selectedLocationDidChange = Notification.Name("selectedLocationDidChange")
    public static let widgetConditionsDidChange = Notification.Name("widgetConditionsDidChange")
}

public struct AppGroupStorage: Sendable {
    public static let suiteName = "group.com.astroviewing.conditions"
    
    private static let fileQueueKey = DispatchSpecificKey<Void>()
    private static let fileQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.astroviewing.storage", qos: .utility)
        queue.setSpecific(key: fileQueueKey, value: ())
        return queue
    }()
    
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }
    
    private static func performFileAccess<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: fileQueueKey) != nil {
            return work()
        }
        return fileQueue.sync(execute: work)
    }

    private static func performFileAccessAsync<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        if DispatchQueue.getSpecific(key: fileQueueKey) != nil {
            return work()
        }
        return await withCheckedContinuation { continuation in
            fileQueue.async {
                continuation.resume(returning: work())
            }
        }
    }
    
    // MARK: - Selected Location (unified)
    
    public static func saveSelectedLocation(_ location: SelectedLocation) {
        performFileAccess {
            guard let baseURL = containerURL else { return }
            do {
                let data = try JSONEncoder().encode(location)
                let fileURL = baseURL.appendingPathComponent("selectedLocation.json")
                try data.write(to: fileURL, options: .atomic)
            } catch {
                logger.error("Failed to save selected location: \(error.localizedDescription)")
            }
        }
    }
    
    public static func loadSelectedLocation() -> SelectedLocation? {
        performFileAccess {
            guard let baseURL = containerURL else { return nil }
            let fileURL = baseURL.appendingPathComponent("selectedLocation.json")
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            
            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(SelectedLocation.self, from: data)
            } catch {
                logger.warning("Failed to load selected location: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    public static func loadSelectedLocationForWidget() -> (latitude: Double, longitude: Double, name: String)? {
        guard let selected = loadSelectedLocation() else { return nil }
        return (selected.latitude, selected.longitude, selected.name)
    }
    
    private static func writeWidgetConditions(_ conditions: ViewingConditions) -> Bool {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return false
        }

        do {
            let data = try JSONEncoder().encode(conditions)
            let fileURL = baseURL.appendingPathComponent("widgetConditions.json")
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save widget conditions: \(error.localizedDescription)")
            return false
        }
    }

    private static func readWidgetConditions() -> ViewingConditions? {
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

    private static func postWidgetConditionsDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .widgetConditionsDidChange, object: nil)
        }
    }

    public static func saveWidgetConditions(_ conditions: ViewingConditions) {
        let didSave = performFileAccess {
            writeWidgetConditions(conditions)
        }

        if didSave {
            postWidgetConditionsDidChange()
        }
    }

    public static func saveWidgetConditionsAsync(_ conditions: ViewingConditions) async {
        let didSave = await performFileAccessAsync {
            writeWidgetConditions(conditions)
        }

        if didSave {
            await MainActor.run {
                NotificationCenter.default.post(name: .widgetConditionsDidChange, object: nil)
            }
        }
    }

    public static func loadWidgetConditions() -> ViewingConditions? {
        performFileAccess {
            readWidgetConditions()
        }
    }

    public static func loadWidgetConditionsAsync() async -> ViewingConditions? {
        await performFileAccessAsync {
            readWidgetConditions()
        }
    }
    
    // MARK: - Saved Locations
    
    public static func saveSavedLocations(_ locations: [CachedLocation]) {
        performFileAccess {
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
    }
    
    public static func loadSavedLocations() -> [CachedLocation] {
        performFileAccess {
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
    }
    
    // MARK: - Conditions

    private static func writeConditions(_ conditions: ViewingConditions, timestamp: Date) {
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

    private static func readConditions() -> ViewingConditions? {
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

    private static func readConditionsTimestamp() -> Date? {
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
    
    public static func saveConditions(_ conditions: ViewingConditions, timestamp: Date = Date()) {
        performFileAccess {
            writeConditions(conditions, timestamp: timestamp)
        }
    }

    public static func saveConditionsAsync(_ conditions: ViewingConditions, timestamp: Date = Date()) async {
        await performFileAccessAsync {
            writeConditions(conditions, timestamp: timestamp)
        }
    }
    
    public static func loadConditions() -> ViewingConditions? {
        performFileAccess {
            readConditions()
        }
    }

    public static func loadConditionsAsync() async -> ViewingConditions? {
        await performFileAccessAsync {
            readConditions()
        }
    }
    
    public static func loadConditionsTimestamp() -> Date? {
        performFileAccess {
            readConditionsTimestamp()
        }
    }

    public static func loadConditionsTimestampAsync() async -> Date? {
        await performFileAccessAsync {
            readConditionsTimestamp()
        }
    }
    
    public static func loadConditionsWithTimestamp() -> (conditions: ViewingConditions, timestamp: Date, isStale: Bool)? {
        performFileAccess {
            guard let conditions = readConditions(),
                  let timestamp = readConditionsTimestamp() else {
                return nil
            }
            
            let isStale = Date().timeIntervalSince(timestamp) > 3600
            return (conditions, timestamp, isStale)
        }
    }

    public static func loadConditionsWithTimestampAsync() async -> (conditions: ViewingConditions, timestamp: Date, isStale: Bool)? {
        await performFileAccessAsync {
            guard let conditions = readConditions(),
                  let timestamp = readConditionsTimestamp() else {
                return nil
            }

            let isStale = Date().timeIntervalSince(timestamp) > 3600
            return (conditions, timestamp, isStale)
        }
    }
    
    public static func clearConditions() {
        performFileAccess {
            guard let baseURL = containerURL else { return }
            
            let conditionsFile = baseURL.appendingPathComponent("conditions.json")
            let timestampFile = baseURL.appendingPathComponent("conditionsTimestamp.json")
            
            try? FileManager.default.removeItem(at: conditionsFile)
            try? FileManager.default.removeItem(at: timestampFile)
            logger.info("Cleared conditions cache")
        }
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
    
}
