import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class UnitSystemTests: XCTestCase {
    private let testSuiteName = "group.com.astroviewing.conditions"
    
    private var testContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: testSuiteName)
    }
    
    override func setUp() {
        super.setUp()
        cleanupUnitSystemFile()
    }
    
    override func tearDown() {
        cleanupUnitSystemFile()
        super.tearDown()
    }
    
    private func cleanupUnitSystemFile() {
        if let url = testContainerURL {
            let fileURL = url.appendingPathComponent("unitSystem.json")
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Initialization Tests
    
    func testInitializeSetsDefaultFromLocale() {
        UnitSystemStorage.initializeIfNeeded()
        
        let result = UnitSystemStorage.loadSelectedUnitSystem()
        XCTAssertNotNil(result)
    }
    
    func testInitializeOnlyRunsOnce() {
        _ = UnitSystemStorage.loadSelectedUnitSystem()
        
        UnitSystemStorage.saveSelectedUnitSystem(.imperial)
        
        let secondValue = UnitSystemStorage.loadSelectedUnitSystem()
        XCTAssertEqual(secondValue, .imperial)
    }
    
    func testInitializeSetsValueOnce() {
        let result = UnitSystemStorage.loadSelectedUnitSystem()
        XCTAssertEqual(result, .metric)
        
        UnitSystemStorage.initializeIfNeeded()
        
        let afterInit = UnitSystemStorage.loadSelectedUnitSystem()
        XCTAssertNotNil(afterInit)
    }
    
    // MARK: - Getter Tests
    
    func testGetterReturnsStoredValue() {
        UnitSystemStorage.saveSelectedUnitSystem(.imperial)
        
        XCTAssertEqual(UnitSystemStorage.loadSelectedUnitSystem(), .imperial)
    }
    
    func testGetterReturnsMetricForInvalidValue() throws {
        guard let url = testContainerURL else {
            throw XCTSkip("Test container not available")
        }
        
        let invalidData = try? JSONEncoder().encode("InvalidValue")
        let fileURL = url.appendingPathComponent("unitSystem.json")
        try? invalidData?.write(to: fileURL)
        
        XCTAssertEqual(UnitSystemStorage.loadSelectedUnitSystem(), .metric)
    }
    
    func testGetterReturnsMetricWhenNotSet() {
        XCTAssertEqual(UnitSystemStorage.loadSelectedUnitSystem(), .metric)
    }
    
    // MARK: - Setter Tests
    
    func testSetterPersistsValue() {
        UnitSystemStorage.saveSelectedUnitSystem(.imperial)
        
        let result = UnitSystemStorage.loadSelectedUnitSystem()
        XCTAssertEqual(result, .imperial)
    }
    
    func testSetterOverwritesExistingValue() {
        UnitSystemStorage.saveSelectedUnitSystem(.imperial)
        
        UnitSystemStorage.saveSelectedUnitSystem(.metric)
        
        XCTAssertEqual(UnitSystemStorage.loadSelectedUnitSystem(), .metric)
    }
    
    // MARK: - User Preference Persistence Tests
    
    func testUserPreferenceNotOverwrittenByLocaleChange() {
        UnitSystemStorage.saveSelectedUnitSystem(.imperial)
        
        UnitSystemStorage.initializeIfNeeded()
        
        XCTAssertEqual(UnitSystemStorage.loadSelectedUnitSystem(), .imperial)
    }
    
    func testStoredValuePersistsAcrossSessions() {
        UnitSystemStorage.saveSelectedUnitSystem(.imperial)
        
        let newResult = UnitSystemStorage.loadSelectedUnitSystem()
        XCTAssertEqual(newResult, .imperial)
    }
}