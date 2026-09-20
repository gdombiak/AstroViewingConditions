import SharedCode
import XCTest

final class AstroUnitConverterTests: XCTestCase {
    private let metric = AstroUnitConverter(unitSystem: .metric)
    private let imperial = AstroUnitConverter(unitSystem: .imperial)

    func testFormatElevationUsesMetersAndFeetForReportedValue() {
        XCTAssertEqual(metric.formatElevation(1165), "1165 m")
        XCTAssertEqual(imperial.formatElevation(1165), "3822 ft")
    }

    func testFormatElevationRoundsToNearestInteger() {
        XCTAssertEqual(metric.formatElevation(1165.6), "1166 m")
        XCTAssertEqual(imperial.formatElevation(0.4), "1 ft")
    }

    func testFormatElevationDoesNotUseKilometersOrMiles() {
        XCTAssertEqual(metric.formatElevation(4000), "4000 m")
        XCTAssertEqual(imperial.formatElevation(4000), "13123 ft")
    }

    func testFormatElevationFormatsNegativeValues() {
        XCTAssertEqual(metric.formatElevation(-86), "-86 m")
        XCTAssertEqual(imperial.formatElevation(-86), "-282 ft")
    }
}
