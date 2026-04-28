import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class BestSpotSettingsTests: XCTestCase {
    private let testSuiteName = "group.com.astroviewing.conditions"
    
    override func setUp() {
        super.setUp()
        cleanupTestFiles()
    }
    
    override func tearDown() {
        cleanupTestFiles()
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
    
    // MARK: - AppGroupStorage Based Tests
    
    func testAppGroupStorageSearchRadiusDefaultValue() {
        XCTAssertEqual(BestSpotSettings.searchRadius, 30)
    }
    
    func testAppGroupStorageSearchRadiusSettingValidValue() {
        BestSpotSettings.searchRadius = 25
        XCTAssertEqual(BestSpotSettings.searchRadius, 25)
    }
    
    func testAppGroupStorageSearchRadiusClampsBelowMin() {
        BestSpotSettings.searchRadius = 5
        XCTAssertEqual(BestSpotSettings.searchRadius, 10)
    }
    
    func testAppGroupStorageSearchRadiusClampsAboveMax() {
        BestSpotSettings.searchRadius = 100
        XCTAssertEqual(BestSpotSettings.searchRadius, 50)
    }
    
    func testAppGroupStorageGridSpacingDefaultValue() {
        XCTAssertEqual(BestSpotSettings.gridSpacing, 5)
    }
    
    func testAppGroupStorageGridSpacingSettingValidValue() {
        BestSpotSettings.gridSpacing = 7
        XCTAssertEqual(BestSpotSettings.gridSpacing, 7)
    }
    
    func testAppGroupStorageGridSpacingClampsBelowMin() {
        BestSpotSettings.gridSpacing = 1
        XCTAssertEqual(BestSpotSettings.gridSpacing, 3)
    }
    
    func testAppGroupStorageGridSpacingClampsAboveMax() {
        BestSpotSettings.gridSpacing = 20
        XCTAssertEqual(BestSpotSettings.gridSpacing, 10)
    }
    
    func testAppGroupStoragePersistsValues() {
        BestSpotSettings.searchRadius = 40
        BestSpotSettings.gridSpacing = 8
        
        let settings = AppGroupStorage.loadBestSpotSettings()
        XCTAssertEqual(settings?.searchRadius, 40)
        XCTAssertEqual(settings?.gridSpacing, 8)
    }
    
    private func cleanupTestFiles() {
        guard let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: testSuiteName) else { return }
        let fileURL = baseURL.appendingPathComponent("bestSpotSettings.json")
        try? FileManager.default.removeItem(at: fileURL)
    }
}