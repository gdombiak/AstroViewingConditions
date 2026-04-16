import Foundation
import os.log
#if os(iOS)
import SwiftData

private let syncLogger = Logger(subsystem: "com.astroviewing.conditions", category: "LocationSync")
#else
private let syncLogger = Logger(subsystem: "com.astroviewing.conditions", category: "LocationSync")
#endif

private let appGroupSuiteName = "group.com.astroviewing.conditions"

private var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)
}

#if os(iOS)
public final class LocationSyncService: @unchecked Sendable {
    public static let shared = LocationSyncService()
    
    public init() {}
    
    public func getSavedLocations(context: ModelContext) -> [CachedLocation] {
        let descriptor = FetchDescriptor<SavedLocation>()
        do {
            let saved = try context.fetch(descriptor)
            syncLogger.info("Fetched \(saved.count) saved locations")
            return saved.map { CachedLocation(from: $0) }
        } catch {
            syncLogger.error("Failed to fetch locations: \(error.localizedDescription)")
            return []
        }
    }
    
    public func getSavedLocationsFromAppGroup() -> [CachedLocation] {
        guard let baseURL = containerURL else { return [] }
        
        let fileURL = baseURL.appendingPathComponent("savedLocations.json")
        guard let data = try? Data(contentsOf: fileURL),
              let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) else {
            return []
        }
        return locations
    }
    
    public func publishLocationsToWatch(context: ModelContext) -> [CachedLocation] {
        return getSavedLocations(context: context)
    }
}
#else
public final class LocationSyncService: @unchecked Sendable {
    public static let shared = LocationSyncService()
    
    public init() {}
    
    public func publishLocationsToWatch(context: Any) -> [CachedLocation] {
        return []
    }
    
    public func getSavedLocations(context: Any) -> [CachedLocation] {
        return []
    }
    
    public func getSavedLocationsFromAppGroup() -> [CachedLocation] {
        guard let baseURL = containerURL else { return [] }
        
        let fileURL = baseURL.appendingPathComponent("savedLocations.json")
        guard let data = try? Data(contentsOf: fileURL),
              let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) else {
            return []
        }
        return locations
    }
}
#endif

public struct SavedLocationStorage {
    public static func saveLocations(_ locations: [CachedLocation]) {
        guard let baseURL = containerURL else {
            syncLogger.error("App Group container not available")
            return
        }
        
        let fileURL = baseURL.appendingPathComponent("savedLocations.json")
        
        do {
            let data = try JSONEncoder().encode(locations)
            try data.write(to: fileURL)
        } catch {
            syncLogger.error("Failed to save locations: \(error.localizedDescription)")
        }
    }
    
    public static func loadLocations() -> [CachedLocation] {
        guard let baseURL = containerURL else {
            syncLogger.error("App Group container not available")
            return []
        }
        
        let fileURL = baseURL.appendingPathComponent("savedLocations.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([CachedLocation].self, from: data)
        } catch {
            syncLogger.warning("Failed to load locations: \(error.localizedDescription)")
            return []
        }
    }
}