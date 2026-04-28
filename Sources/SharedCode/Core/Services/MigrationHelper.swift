import Foundation
import os

public struct MigrationHelper {
    private static let migrationVersionKey = "appGroupMigrationVersion"
    private static let currentMigrationVersion = 2
    private static let logger = Logger(subsystem: "com.astroviewing.conditions", category: "Migration")
    
    public static func migrateIfNeeded() {
        let lastVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        
        guard lastVersion < currentMigrationVersion else { return }
        
        logger.info("Starting migration from version \(lastVersion) to \(Self.currentMigrationVersion)")
        
        let old = UserDefaults.standard
        
        if lastVersion < 2 {
            let searchRadius = old.double(forKey: BestSpotSettings.searchRadiusKey)
            let gridSpacing = old.double(forKey: BestSpotSettings.gridSpacingKey)
            let validatedRadius = searchRadius > 0 ? searchRadius : BestSpotSettings.defaultSearchRadius
            let validatedSpacing = gridSpacing > 0 ? gridSpacing : BestSpotSettings.defaultGridSpacing
            AppGroupStorage.saveBestSpotSettings(
                searchRadius: validatedRadius,
                gridSpacing: validatedSpacing
            )
            logger.info("Migrated BestSpot settings")
            
            if let unitRaw = old.string(forKey: "selectedUnitSystem") {
                AppGroupStorage.saveUnitSystem(unitRaw)
                iCloudKeyValueStorage.shared.saveUnitSystem(unitRaw)
                logger.info("Migrated unit system: \(unitRaw)")
            }
            
            if let data = old.data(forKey: "savedLocations"),
               let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                AppGroupStorage.saveSavedLocations(locations)
                iCloudKeyValueStorage.shared.saveLocations(locations)
                logger.info("Migrated \(locations.count) saved locations")
            }
            
            if let data = old.data(forKey: "conditions"),
               let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                AppGroupStorage.saveConditions(conditions)
                logger.info("Migrated viewing conditions")
            }
            
            migrateSelectedLocationToUnifiedFormat(old: old)
        }
        
        UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
        logger.info("Migration complete. Set version to \(Self.currentMigrationVersion)")
    }
    
    private static func migrateSelectedLocationToUnifiedFormat(old: UserDefaults) {
        if AppGroupStorage.loadSelectedLocation() != nil {
            logger.info("Unified selected location already exists, skipping migration")
            return
        }
        
        let oldID = old.string(forKey: "selectedLocationID") ?? "current"
        
        if let uuid = UUID(uuidString: oldID) {
            let location = SelectedLocation(
                source: .saved,
                id: uuid,
                name: "",
                latitude: 0,
                longitude: 0
            )
            AppGroupStorage.saveSelectedLocation(location)
            logger.info("Migrated selected location (UUID only, iOS will resolve on launch)")
        } else {
            let location = SelectedLocation(
                source: .currentGPS,
                id: nil,
                name: "Current Location",
                latitude: 0,
                longitude: 0
            )
            AppGroupStorage.saveSelectedLocation(location)
            iCloudKeyValueStorage.shared.saveSelectedLocation(location)
            logger.info("Migrated selected location to unified format: \(location.source.rawValue)")
        }
        
        deleteOldLocationFiles()
    }
    
    private static func deleteOldLocationFiles() {
        guard let baseURL = AppGroupStorage.containerURL else { return }
        let filesToDelete = ["selectedLocationID.json", "currentLocation.json", "widgetLocation.json"]
        for fileName in filesToDelete {
            let fileURL = baseURL.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted old file: \(fileName)")
        }
    }
}
