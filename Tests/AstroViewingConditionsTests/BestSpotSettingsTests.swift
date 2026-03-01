import XCTest
import Foundation
@testable import AstroViewingConditions

final class BestSpotSettingsTests: XCTestCase {
    
    var userDefaults: UserDefaults!
    
    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "test.bestSpot.settings")
        userDefaults.removePersistentDomain(forName: "test.bestSpot.settings")
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "test.bestSpot.settings")
        userDefaults = nil
        super.tearDown()
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultSearchRadius() {
        XCTAssertEqual(BestSpotSettings.defaultSearchRadius, 30)
    }
    
    func testDefaultGridSpacing() {
        XCTAssertEqual(BestSpotSettings.defaultGridSpacing, 5)
    }
    
    func testMinSearchRadius() {
        XCTAssertEqual(BestSpotSettings.minSearchRadius, 10)
    }
    
    func testMaxSearchRadius() {
        XCTAssertEqual(BestSpotSettings.maxSearchRadius, 50)
    }
    
    func testMinGridSpacing() {
        XCTAssertEqual(BestSpotSettings.minGridSpacing, 3)
    }
    
    func testMaxGridSpacing() {
        XCTAssertEqual(BestSpotSettings.maxGridSpacing, 10)
    }
    
    // MARK: - Validation Tests
    
    func testValidateSearchRadiusWithinRange() {
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(15), 15)
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(30), 30)
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(45), 45)
    }
    
    func testValidateSearchRadiusBelowMin() {
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(5), 10)
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(0), 10)
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(-10), 10)
    }
    
    func testValidateSearchRadiusAboveMax() {
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(60), 50)
        XCTAssertEqual(BestSpotSettings.validateSearchRadius(100), 50)
    }
    
    func testValidateGridSpacingWithinRange() {
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(3), 3)
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(5), 5)
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(10), 10)
    }
    
    func testValidateGridSpacingBelowMin() {
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(1), 3)
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(0), 3)
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(-5), 3)
    }
    
    func testValidateGridSpacingAboveMax() {
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(15), 10)
        XCTAssertEqual(BestSpotSettings.validateGridSpacing(20), 10)
    }
    
    // MARK: - UserDefaults Extension Tests
    
    func testUserDefaultsSearchRadiusDefaultValue() {
        XCTAssertEqual(userDefaults.bestSpotSearchRadius, 30)
    }
    
    func testUserDefaultsSearchRadiusSettingValidValue() {
        userDefaults.bestSpotSearchRadius = 25
        XCTAssertEqual(userDefaults.bestSpotSearchRadius, 25)
    }
    
    func testUserDefaultsSearchRadiusClampsBelowMin() {
        userDefaults.bestSpotSearchRadius = 5
        XCTAssertEqual(userDefaults.bestSpotSearchRadius, 10)
    }
    
    func testUserDefaultsSearchRadiusClampsAboveMax() {
        userDefaults.bestSpotSearchRadius = 100
        XCTAssertEqual(userDefaults.bestSpotSearchRadius, 50)
    }
    
    func testUserDefaultsGridSpacingDefaultValue() {
        XCTAssertEqual(userDefaults.bestSpotGridSpacing, 5)
    }
    
    func testUserDefaultsGridSpacingSettingValidValue() {
        userDefaults.bestSpotGridSpacing = 7
        XCTAssertEqual(userDefaults.bestSpotGridSpacing, 7)
    }
    
    func testUserDefaultsGridSpacingClampsBelowMin() {
        userDefaults.bestSpotGridSpacing = 1
        XCTAssertEqual(userDefaults.bestSpotGridSpacing, 3)
    }
    
    func testUserDefaultsGridSpacingClampsAboveMax() {
        userDefaults.bestSpotGridSpacing = 20
        XCTAssertEqual(userDefaults.bestSpotGridSpacing, 10)
    }
    
    func testUserDefaultsPersistsValues() {
        userDefaults.bestSpotSearchRadius = 40
        userDefaults.bestSpotGridSpacing = 8
        
        // Create new UserDefaults instance with same suite
        let newDefaults = UserDefaults(suiteName: "test.bestSpot.settings")
        XCTAssertEqual(newDefaults?.bestSpotSearchRadius, 40)
        XCTAssertEqual(newDefaults?.bestSpotGridSpacing, 8)
    }
    
    func testUserDefaultsResetToDefaults() {
        userDefaults.bestSpotSearchRadius = 45
        userDefaults.bestSpotGridSpacing = 9
        
        userDefaults.removeObject(forKey: BestSpotSettings.searchRadiusKey)
        userDefaults.removeObject(forKey: BestSpotSettings.gridSpacingKey)
        
        XCTAssertEqual(userDefaults.bestSpotSearchRadius, 30)
        XCTAssertEqual(userDefaults.bestSpotGridSpacing, 5)
    }
}
