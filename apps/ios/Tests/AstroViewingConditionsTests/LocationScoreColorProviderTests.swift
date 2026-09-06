import SharedCode
import SwiftUI
import UIKit
import XCTest
@testable import AstroViewingConditions

final class LocationScoreColorProviderTests: XCTestCase {

    func testLocationThresholdsUseSharedCategoriesAndNormalPaletteColors() throws {
        let cases: [
            (
                score: Int,
                category: LocationScoreCategory,
                tone: AppStatusTone
            )
        ] = [
            (39, .poor, .negative),
            (40, .fair, .caution),
            (59, .fair, .caution),
            (60, .good, .informational),
            (64, .good, .informational),
            (65, .good, .informational),
            (79, .good, .informational),
            (80, .excellent, .positive),
            (100, .excellent, .positive)
        ]

        for testCase in cases {
            XCTAssertEqual(
                LocationScoreCategory.resolve(testCase.score),
                testCase.category
            )
            XCTAssertEqual(
                LocationScoreColorProvider.category(for: testCase.score),
                testCase.category
            )
            try assertColor(
                LocationScoreColorProvider.color(for: testCase.score),
                equals: AppPalette.normal.statusColor(testCase.tone)
            )
        }
    }

    func testLocationScoreColorsRespectFieldPalette() throws {
        let cases: [(score: Int, tone: AppStatusTone)] = [
            (80, .positive),
            (60, .informational),
            (40, .caution),
            (39, .negative)
        ]

        for testCase in cases {
            try assertColor(
                LocationScoreColorProvider.color(
                    for: testCase.score,
                    palette: .field
                ),
                equals: AppPalette.field.statusColor(testCase.tone)
            )
        }
    }

    func testLocationAndTargetScalesAreIntentionallyDifferent() {
        XCTAssertEqual(LocationScoreCategory.resolve(62), .good)
        XCTAssertEqual(TargetScoreCategory.resolve(62), .fair)
        XCTAssertEqual(LocationScoreCategory.resolve(42), .fair)
        XCTAssertEqual(TargetScoreCategory.resolve(42), .poor)

        let targetCases: [(Int, TargetScoreCategory)] = [
            (44, .poor),
            (45, .fair),
            (64, .fair),
            (65, .good),
            (79, .good),
            (80, .excellent)
        ]
        for (score, category) in targetCases {
            XCTAssertEqual(TargetScoreCategory.resolve(score), category)
        }
    }

    private func assertColor(
        _ actual: Color,
        equals expected: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actualComponents = try rgbaComponents(of: actual)
        let expectedComponents = try rgbaComponents(of: expected)

        XCTAssertEqual(actualComponents.red, expectedComponents.red, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(actualComponents.green, expectedComponents.green, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(actualComponents.blue, expectedComponents.blue, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(actualComponents.alpha, expectedComponents.alpha, accuracy: 0.000_1, file: file, line: line)
    }

    private func rgbaComponents(
        of color: Color
    ) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let uiColor = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )

        XCTAssertTrue(uiColor.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ))
        return (red, green, blue, alpha)
    }
}
