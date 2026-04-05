import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class UnitSystemTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private let unitSystemKey = "selectedUnitSystem"
    
    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "UnitSystemTests")
    }
    
    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "UnitSystemTests")
        testDefaults = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializeSetsDefaultFromLocale() {
        testDefaults.initializeUnitSystemIfNeeded()
        
        XCTAssertNotNil(testDefaults.string(forKey: unitSystemKey))
    }
    
    func testInitializeOnlyRunsOnce() {
        testDefaults.initializeUnitSystemIfNeeded()
        let firstValue = testDefaults.string(forKey: unitSystemKey)
        
        testDefaults.set("Imperial", forKey: unitSystemKey)
        
        testDefaults.initializeUnitSystemIfNeeded()
        
        XCTAssertEqual(testDefaults.string(forKey: unitSystemKey), "Imperial")
        if let first = firstValue, first != "Imperial" {
            XCTAssertNotEqual(testDefaults.string(forKey: unitSystemKey), firstValue)
        }
    }
    
    func testInitializeSetsValueOnce() {
        XCTAssertNil(testDefaults.string(forKey: unitSystemKey))
        
        testDefaults.initializeUnitSystemIfNeeded()
        
        XCTAssertNotNil(testDefaults.string(forKey: unitSystemKey))
    }
    
    // MARK: - Getter Tests
    
    func testGetterReturnsStoredValue() {
        testDefaults.set("Imperial", forKey: unitSystemKey)
        
        XCTAssertEqual(testDefaults.selectedUnitSystem, .imperial)
    }
    
    func testGetterReturnsMetricForInvalidValue() {
        testDefaults.set("InvalidValue", forKey: unitSystemKey)
        
        XCTAssertEqual(testDefaults.selectedUnitSystem, .metric)
    }
    
    func testGetterReturnsMetricWhenNotSet() {
        XCTAssertEqual(testDefaults.selectedUnitSystem, .metric)
    }
    
    // MARK: - Setter Tests
    
    func testSetterPersistsValue() {
        testDefaults.selectedUnitSystem = .imperial
        
        XCTAssertEqual(testDefaults.string(forKey: unitSystemKey), "Imperial")
    }
    
    func testSetterOverwritesExistingValue() {
        testDefaults.set("Imperial", forKey: unitSystemKey)
        
        testDefaults.selectedUnitSystem = .metric
        
        XCTAssertEqual(testDefaults.string(forKey: unitSystemKey), "Metric")
    }
    
    // MARK: - User Preference Persistence Tests
    
    func testUserPreferenceNotOverriddenByLocaleChange() {
        testDefaults.set("Imperial", forKey: unitSystemKey)
        
        testDefaults.initializeUnitSystemIfNeeded()
        
        XCTAssertEqual(testDefaults.selectedUnitSystem, .imperial)
    }
    
    func testStoredValuePersistsAcrossSessions() {
        testDefaults.selectedUnitSystem = .imperial
        
        let newDefaults = UserDefaults(suiteName: "UnitSystemTests")
        
        XCTAssertEqual(newDefaults?.selectedUnitSystem, .imperial)
        newDefaults?.removePersistentDomain(forName: "UnitSystemTests")
    }
}
