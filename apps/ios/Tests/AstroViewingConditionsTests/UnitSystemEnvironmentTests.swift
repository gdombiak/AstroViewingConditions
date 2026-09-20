import SharedCode
import SwiftUI
import XCTest
@testable import AstroViewingConditions

@MainActor
final class UnitSystemEnvironmentTests: XCTestCase {
    func testUnitSystemEnvironmentValuesDefaultAndAssignment() {
        var values = EnvironmentValues()
        XCTAssertEqual(values.unitSystem, .metric)

        values.unitSystem = .imperial
        XCTAssertEqual(values.unitSystem, .imperial)

        values.unitSystem = .metric
        XCTAssertEqual(values.unitSystem, .metric)
    }
}
