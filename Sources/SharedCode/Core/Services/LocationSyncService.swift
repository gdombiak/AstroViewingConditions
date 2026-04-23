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
    
    private func syncLocationsToCloud(_ locations: [CachedLocation]) {
        AppGroupStorage.saveSavedLocations(locations)
        iCloudKeyValueStorage.shared.saveLocations(locations)
    }
    
    private func syncSelectedLocationToCloud(_ location: CachedLocation) {
        AppGroupStorage.saveSelectedLocation(location)
        iCloudKeyValueStorage.shared.saveSelectedLocation(location)
    }
    
    public func getSavedLocationsFromAppGroup() -> [CachedLocation] {
        AppGroupStorage.loadSavedLocations()
    }
    
    public func publishLocationsToWatch(context: ModelContext) -> [CachedLocation] {
        let locations = getSavedLocations(context: context)
        syncLocationsToCloud(locations)
        return locations
    }
    
    public func publishSelectedLocationToWatch(location: CachedLocation) {
        syncSelectedLocationToCloud(location)
    }
}
#else
public final class LocationSyncService: @unchecked Sendable {
    public static let shared = LocationSyncService()
    
    public init() {}
    
    public func publishLocationsToWatch(context: Any) -> [CachedLocation] {
        return []
    }
    
    public func publishSelectedLocationToWatch(location: CachedLocation) {}
    
    public func getSavedLocations(context: Any) -> [CachedLocation] {
        return []
    }
    
    public func getSavedLocationsFromAppGroup() -> [CachedLocation] {
        AppGroupStorage.loadSavedLocations()
    }
}
#endif

