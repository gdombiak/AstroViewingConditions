import Foundation
import os

public struct MigrationHelper {
    private static let migrationVersionKey = "appGroupMigrationVersion"
    private static let currentMigrationVersion = 2
    private static let logger = Logger(subsystem: "com.astroviewing.conditions", category: "Migration")
    
    public static func migrateIfNeeded() {
        let lastVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        
        guard lastVersion < currentMigrationVersion else { return }
        
        logger.info("Starting migration from version \(lastVersion) to \(self.currentMigrationVersion)")
        
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
                logger.info("Migrated unit system: \(unitRaw)")
            }
            
            if let selectedLocationID = old.string(forKey: "selectedLocationID"), !selectedLocationID.isEmpty {
                AppGroupStorage.saveSelectedLocationID(selectedLocationID)
                logger.info("Migrated selectedLocationID")
            }
            
            if let data = old.data(forKey: "savedLocations"),
               let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) {
                AppGroupStorage.saveSavedLocations(locations)
                iCloudKeyValueStorage.shared.saveLocations(locations)
                logger.info("Migrated \(locations.count) saved locations")
            }
            
            if let data = old.data(forKey: "currentLocation"),
               let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                AppGroupStorage.saveCurrentLocation(location)
                logger.info("Migrated current location")
            }
            
            if let data = old.data(forKey: "selectedLocation"),
               let location = try? JSONDecoder().decode(CachedLocation.self, from: data) {
                AppGroupStorage.saveSelectedLocation(location)
                iCloudKeyValueStorage.shared.saveSelectedLocation(location)
                logger.info("Migrated selected location")
            }
            
            if let data = old.data(forKey: "conditions"),
               let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) {
                AppGroupStorage.saveConditions(conditions)
                logger.info("Migrated viewing conditions")
            }
        }
        
        UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
        logger.info("Migration complete. Set version to \(self.currentMigrationVersion)")
    }
}