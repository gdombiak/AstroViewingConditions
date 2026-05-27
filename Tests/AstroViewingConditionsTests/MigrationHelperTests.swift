import XCTest
@testable import SharedCode

final class MigrationHelperTests: XCTestCase {
    private let versionKey = "appGroupMigrationVersion"
    private let testSuiteName = "group.com.astroviewing.conditions"
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: versionKey)
        cleanupAppGroupFiles()
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: versionKey)
        cleanupAppGroupFiles()
        super.tearDown()
    }
    
    func testMigrationRunsOnce() {
        UserDefaults.standard.set(25.0, forKey: "bestSpotSearchRadius")
        UserDefaults.standard.set(6.0, forKey: "bestSpotGridSpacing")
        UserDefaults.standard.set("imperial", forKey: "selectedUnitSystem")
        
        MigrationHelper.migrateIfNeeded()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: versionKey), 2)
        
        let settings = AppGroupStorage.loadBestSpotSettings()
        XCTAssertEqual(settings?.searchRadius, 25.0)
        
        AppGroupStorage.saveBestSpotSettings(searchRadius: 30.0, gridSpacing: 8.0)
        
        MigrationHelper.migrateIfNeeded()
        
        let settingsAfter = AppGroupStorage.loadBestSpotSettings()
        XCTAssertEqual(settingsAfter?.searchRadius, 30.0)
    }
    
    func testMigrationMigratesAllData() {
        UserDefaults.standard.set(25.0, forKey: "bestSpotSearchRadius")
        UserDefaults.standard.set(6.0, forKey: "bestSpotGridSpacing")
        UserDefaults.standard.set("imperial", forKey: "selectedUnitSystem")
        UserDefaults.standard.set("current", forKey: "selectedLocationID")
        
        MigrationHelper.migrateIfNeeded()
        
        XCTAssertNotNil(AppGroupStorage.loadBestSpotSettings())
        XCTAssertEqual(AppGroupStorage.loadUnitSystem(), "imperial")
        let selected = AppGroupStorage.loadSelectedLocation()
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.source, .currentGPS)
    }
    
    private func cleanupAppGroupFiles() {
        guard let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: testSuiteName) else { return }
        let files = ["savedLocations.json", "selectedLocation.json", "currentLocation.json",
                    "conditions.json", "bestSpotSettings.json", "unitSystem.json",
                    "widgetLocation.json", "widgetConditions.json"]
        
        for file in files {
            try? FileManager.default.removeItem(at: baseURL.appendingPathComponent(file))
        }
    }
}