import SharedCode
import XCTest

final class TransparencyCalculatorTests: XCTestCase {
    func testClearAtAllCloudLevels() {
        XCTAssertEqual(
            TransparencyCalculator.penalty(totalCloudCover: 0, lowCloudCover: 0, midCloudCover: 0, highCloudCover: 0, visibilityMeters: 20_000),
            0
        )
    }

    func testHighCloudReceivesLessWeightThanEquivalentLowCloud() {
        let highCloud = TransparencyCalculator.penalty(totalCloudCover: 0, lowCloudCover: 0, midCloudCover: 0, highCloudCover: 100, visibilityMeters: nil)
        let lowCloud = TransparencyCalculator.penalty(totalCloudCover: 0, lowCloudCover: 100, midCloudCover: 0, highCloudCover: 0, visibilityMeters: nil)
        XCTAssertLessThan(highCloud!, lowCloud!)
    }

    func testTotalCloudCoverIsAnObstructionFloor() {
        XCTAssertEqual(
            TransparencyCalculator.penalty(totalCloudCover: 100, lowCloudCover: 0, midCloudCover: 0, highCloudCover: 100, visibilityMeters: 20_000),
            2
        )
    }

    func testGoodVisibilityDoesNotReduceOvercastPenalty() {
        XCTAssertEqual(
            TransparencyCalculator.penalty(totalCloudCover: 100, lowCloudCover: 100, midCloudCover: 100, highCloudCover: 100, visibilityMeters: 20_000),
            2
        )
    }

    func testPoorVisibilityWorsensClearConditions() {
        let result = TransparencyCalculator.penalty(
            totalCloudCover: 0,
            lowCloudCover: 0,
            midCloudCover: 0,
            highCloudCover: 0,
            visibilityMeters: 1_000
        )

        XCTAssertGreaterThan(result!, 0)
        XCTAssertEqual(result, 0.5)
    }

    func testFullyCloudyResult() {
        XCTAssertEqual(
            TransparencyCalculator.penalty(totalCloudCover: 100, lowCloudCover: 100, midCloudCover: 100, highCloudCover: 100, visibilityMeters: nil),
            2
        )
    }

    func testMissingLayerDataFallsBackToTotalCloudCover() {
        XCTAssertEqual(
            TransparencyCalculator.penalty(totalCloudCover: 60, lowCloudCover: 0, midCloudCover: nil, highCloudCover: 0, visibilityMeters: nil),
            1
        )
    }

    func testVisibilityHazeAddsPenalty() {
        XCTAssertEqual(
            TransparencyCalculator.penalty(totalCloudCover: 0, lowCloudCover: nil, midCloudCover: nil, highCloudCover: nil, visibilityMeters: 1_000),
            0.5
        )
    }

    func testMissingVisibilityUsesCloudComponentOnly() {
        XCTAssertEqual(
            TransparencyCalculator.penalty(totalCloudCover: 30, lowCloudCover: nil, midCloudCover: nil, highCloudCover: nil, visibilityMeters: nil),
            0.5
        )
    }

    func testThresholdBoundariesAndInputClamping() {
        XCTAssertEqual(TransparencyCalculator.penalty(totalCloudCover: 10, lowCloudCover: nil, midCloudCover: nil, highCloudCover: nil, visibilityMeters: nil), 0)
        XCTAssertEqual(TransparencyCalculator.penalty(totalCloudCover: 80, lowCloudCover: nil, midCloudCover: nil, highCloudCover: nil, visibilityMeters: nil), 1.5)
        XCTAssertEqual(TransparencyCalculator.penalty(totalCloudCover: -10, lowCloudCover: nil, midCloudCover: nil, highCloudCover: nil, visibilityMeters: nil), 0)
        XCTAssertEqual(TransparencyCalculator.penalty(totalCloudCover: 150, lowCloudCover: nil, midCloudCover: nil, highCloudCover: nil, visibilityMeters: nil), 2)
    }
}
