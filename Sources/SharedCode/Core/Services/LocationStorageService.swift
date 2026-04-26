import Foundation
import os.log
#if os(iOS)
import SwiftData

private let storageLogger = Logger(subsystem: "com.astroviewing.conditions", category: "LocationStorage")
#else
private let storageLogger = Logger(subsystem: "com.astroviewing.conditions", category: "LocationStorage")
#endif

#if os(iOS)
public final class LocationStorageService: @unchecked Sendable {
    public static let shared = LocationStorageService()
    
    public init() {}
    
    public func saveSelectedLocation(_ location: SelectedLocation) {
        AppGroupStorage.saveSelectedLocation(location)
        iCloudKeyValueStorage.shared.saveSelectedLocation(location)
    }
    
    public func loadSelectedLocation() -> SelectedLocation? {
        AppGroupStorage.loadSelectedLocation()
            ?? iCloudKeyValueStorage.shared.loadSelectedLocation()
    }
    
    public func saveSavedLocations(_ locations: [CachedLocation]) {
        AppGroupStorage.saveSavedLocations(locations)
        iCloudKeyValueStorage.shared.saveLocations(locations)
    }
    
    public func loadSavedLocations() -> [CachedLocation] {
        AppGroupStorage.loadSavedLocations()
    }
    
    public func getSavedLocations(context: ModelContext) -> [CachedLocation] {
        let descriptor = FetchDescriptor<SavedLocation>()
        do {
            let saved = try context.fetch(descriptor)
            storageLogger.info("Fetched \(saved.count) saved locations")
            return saved.map { CachedLocation(from: $0) }
        } catch {
            storageLogger.error("Failed to fetch locations: \(error.localizedDescription)")
            return []
        }
    }
    
    public func publishLocationsToWatch(context: ModelContext) -> [CachedLocation] {
        let locations = getSavedLocations(context: context)
        saveSavedLocations(locations)
        return locations
    }
}
#else
public final class LocationStorageService: @unchecked Sendable {
    public static let shared = LocationStorageService()
    
    public init() {}
    
    public func saveSelectedLocation(_ location: SelectedLocation) {
        AppGroupStorage.saveSelectedLocation(location)
        iCloudKeyValueStorage.shared.saveSelectedLocation(location)
    }
    
    public func loadSelectedLocation() -> SelectedLocation? {
        AppGroupStorage.loadSelectedLocation()
            ?? iCloudKeyValueStorage.shared.loadSelectedLocation()
    }
    
    public func saveSavedLocations(_ locations: [CachedLocation]) {
        AppGroupStorage.saveSavedLocations(locations)
        iCloudKeyValueStorage.shared.saveLocations(locations)
    }
    
    public func loadSavedLocations() -> [CachedLocation] {
        AppGroupStorage.loadSavedLocations()
    }
    
    public func publishLocationsToWatch(context: Any) -> [CachedLocation] {
        return []
    }
}
#endif
