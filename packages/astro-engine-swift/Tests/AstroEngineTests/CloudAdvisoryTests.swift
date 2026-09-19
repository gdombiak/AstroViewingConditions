import Foundation
import XCTest
@testable import AstroEngine

final class CloudAdvisoryTests: XCTestCase {
    func testSelectorAppliesSummaryEligibilityGate() {
        let floor = Double(EngineCalibration.current.nightQuality.cloudFloor.cloudCoverMin)
        let timings = CloudTimingClassifier.Classification.allCases
        let ratings: [NightQualityAssessment.Rating] = [.excellent, .good, .fair, .poor]
        for timing in timings {
            for rating in ratings {
                for average in [0.0, floor - 0.25, floor, 100.0] {
                    let expectedHeavy = average >= floor
                    let expectedAdvice: CloudTimingClassifier.Classification? =
                        expectedHeavy || rating == .poor || timing == .none ? nil : timing
                    let actual = CloudAdvisorySelector.select(
                        cloudTiming: timing, rating: rating, averageCloudCover: average
                    )
                    XCTAssertEqual(actual.wholeNightHeavy, expectedHeavy)
                    XCTAssertEqual(actual.advisory, expectedAdvice)
                }
            }
        }
    }

    func testTransportReturnsNullableCodeAndRejectsInvalidInput() throws {
        let floor = Double(EngineCalibration.current.nightQuality.cloudFloor.cloudCoverMin)
        let eligible = try CloudAdvisoryContract.evaluate([
            "cloud_timing": "late_heavy", "rating": "fair",
            "average_cloud_cover": floor - 0.25,
        ])
        XCTAssertEqual(eligible["cloud_advisory"] as? String, "late_heavy")
        let suppressed = try CloudAdvisoryContract.evaluate([
            "cloud_timing": "late_heavy", "rating": "fair",
            "average_cloud_cover": floor,
        ])
        XCTAssertTrue(suppressed["cloud_advisory"] is NSNull)
        XCTAssertThrowsError(try CloudAdvisoryContract.evaluate([
            "cloud_timing": "late_heavy", "rating": "fair",
            "average_cloud_cover": true,
        ]))
    }
}
