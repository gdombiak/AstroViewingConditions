import SharedCode
import XCTest

final class SeeingCalculatorTests: XCTestCase {
    func testStableTemperatureAndWeakUpperWind() {
        XCTAssertEqual(
            SeeingCalculator.penalty(currentTemperature: 10, previousTemperature: 9.5, windSpeed200hPa: 50),
            0
        )
    }

    func testTemperatureThresholdBoundaries() {
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 11, previousTemperature: 10, windSpeed200hPa: nil), 0)
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 12, previousTemperature: 10, windSpeed200hPa: nil), 0.5)
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 13, previousTemperature: 10, windSpeed200hPa: nil), 1)
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 15, previousTemperature: 10, windSpeed200hPa: nil), 1.5)
    }

    func testUpperWindThresholdBoundaries() {
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 10, previousTemperature: nil, windSpeed200hPa: 50), 0)
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 10, previousTemperature: nil, windSpeed200hPa: 100), 0.5)
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 10, previousTemperature: nil, windSpeed200hPa: 150), 1)
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 10, previousTemperature: nil, windSpeed200hPa: 200), 1.5)
    }

    func testRapidTemperatureChangeAndStrongUpperWind() {
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 16, previousTemperature: 10, windSpeed200hPa: 250), 2)
    }

    func testOnlyTemperatureAvailable() {
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 13, previousTemperature: 10, windSpeed200hPa: nil), 1)
    }

    func testOnlyUpperWindAvailable() {
        XCTAssertEqual(SeeingCalculator.penalty(currentTemperature: 10, previousTemperature: nil, windSpeed200hPa: 150), 1)
    }

    func testNeitherComponentAvailableReturnsNil() {
        XCTAssertNil(SeeingCalculator.penalty(currentTemperature: 10, previousTemperature: nil, windSpeed200hPa: nil))
    }
}
