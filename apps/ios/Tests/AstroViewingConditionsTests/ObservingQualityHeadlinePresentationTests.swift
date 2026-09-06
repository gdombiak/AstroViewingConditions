@testable import SharedCode
import XCTest

final class ObservingQualityHeadlinePresentationTests: XCTestCase {

    func testBandsAtBoundaries() {
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 100), .excellent)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 80), .excellent)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 79), .good)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 60), .good)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 59), .fair)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 40), .fair)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 39), .poor)
        XCTAssertEqual(ObservingQualityScoreBand.from(score: 0), .poor)
    }

    func testPresentationTracksScoreNotForeignNightScore() {
        // Night-like high score band vs LP-adjusted score
        let nightScore = 85
        let observingScore = 78
        XCTAssertNotEqual(
            ObservingQualityScoreBand.from(score: nightScore),
            ObservingQualityScoreBand.from(score: observingScore)
        )
        let headline = ObservingQualityHeadlinePresentation(score: observingScore)
        XCTAssertEqual(headline.score, 78)
        XCTAssertEqual(headline.band, .good)
        XCTAssertNotEqual(headline.band, ObservingQualityScoreBand.from(score: nightScore))
        XCTAssertTrue(headline.accessibilityLabel.contains("78"))
        XCTAssertTrue(headline.accessibilityLabel.contains("good"))
    }

    func testAssessmentInitializer() {
        let assessment = ObservingQualityAssessment(
            score: 86,
            nightConditionsScore: 93,
            lightPollution: LightPollutionAssessment(
                modeledZenithSkyBrightness: 18.54,
                basePenalty: 7,
                appliedPenalty: 7
            )
        )
        let headline = ObservingQualityHeadlinePresentation(assessment: assessment)
        XCTAssertEqual(headline.score, 86)
        XCTAssertEqual(headline.band, .excellent)
    }
}
