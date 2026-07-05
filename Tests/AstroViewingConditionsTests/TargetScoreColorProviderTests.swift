import XCTest
@testable import AstroViewingConditions

final class TargetScoreColorProviderTests: XCTestCase {

    func testTargetScoreColorsUseSharedCategories() {
        XCTAssertEqual(TargetScoreColorProvider.category(for: 84), .excellent)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 76), .good)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 55), .fair)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 35), .poor)
    }

}

