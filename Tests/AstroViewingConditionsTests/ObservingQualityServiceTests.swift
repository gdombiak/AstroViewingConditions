@testable import SharedCode
import XCTest

/// Fixed brightness provider for deterministic unit tests.
private struct FixedLightPollutionProvider: LightPollutionProviding {
    let value: Double?
    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        value
    }
}

/// Returns brightness only near a target coordinate.
private struct LocationGatedLightPollutionProvider: LightPollutionProviding {
    let latitude: Double
    let longitude: Double
    let value: Double
    let tolerance: Double

    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        guard abs(latitude - self.latitude) <= tolerance,
              abs(longitude - self.longitude) <= tolerance else {
            return nil
        }
        return value
    }
}

final class ObservingQualityServiceTests: XCTestCase {

    func testBrightUrbanHighNightAppliesNearFullPenalty() {
        let service = ObservingQualityService(
            lightPollutionProvider: FixedLightPollutionProvider(value: 18.5)
        )
        let assessment = service.assess(
            nightConditionsScore: 93,
            latitude: 45.5,
            longitude: -122.7
        )
        // base 7 at 18.5, weight 1.0 → score 93-7=86
        XCTAssertEqual(assessment.nightConditionsScore, 93)
        XCTAssertEqual(assessment.score, 86)
        XCTAssertEqual(assessment.lightPollution?.basePenalty ?? -1, 7.0, accuracy: 1e-9)
        XCTAssertEqual(assessment.lightPollution?.appliedPenalty ?? -1, 7.0, accuracy: 1e-9)
    }

    func testDarkSiteHighNightAppliesSmallPenalty() {
        let service = ObservingQualityService(
            lightPollutionProvider: FixedLightPollutionProvider(value: 21.3)
        )
        let assessment = service.assess(
            nightConditionsScore: 93,
            latitude: 45.7,
            longitude: -123.2
        )
        // base 1.0 → 92
        XCTAssertEqual(assessment.score, 92)
        XCTAssertEqual(assessment.lightPollution?.basePenalty ?? -1, 1.0, accuracy: 1e-9)
    }

    func testPristineNoPenalty() {
        let service = ObservingQualityService(
            lightPollutionProvider: FixedLightPollutionProvider(value: 21.75)
        )
        let assessment = service.assess(
            nightConditionsScore: 90,
            latitude: 0,
            longitude: 0
        )
        XCTAssertEqual(assessment.score, 90)
        XCTAssertEqual(assessment.lightPollution?.appliedPenalty ?? -1, 0.0, accuracy: 1e-9)
    }

    func testPoorNightAttenuatesPenalty() {
        let service = ObservingQualityService(
            lightPollutionProvider: FixedLightPollutionProvider(value: 18.5)
        )
        // weight at 35 is 0 → no penalty
        let assessment = service.assess(
            nightConditionsScore: 35,
            latitude: 0,
            longitude: 0
        )
        XCTAssertEqual(assessment.score, 35)
        XCTAssertEqual(assessment.lightPollution?.appliedPenalty ?? -1, 0.0, accuracy: 1e-9)
    }

    func testMissingProviderPreservesNightScore() {
        let service = ObservingQualityService(lightPollutionProvider: nil)
        let assessment = service.assess(
            nightConditionsScore: 77,
            latitude: 45.45,
            longitude: -122.75
        )
        XCTAssertEqual(assessment.score, 77)
        XCTAssertEqual(assessment.nightConditionsScore, 77)
        XCTAssertNil(assessment.lightPollution)
        XCTAssertTrue(assessment.lightPollutionDataUnavailable)
    }

    func testNilBrightnessFromProviderPreservesNightScore() {
        let service = ObservingQualityService(
            lightPollutionProvider: FixedLightPollutionProvider(value: nil)
        )
        let assessment = service.assess(
            nightConditionsScore: 81,
            latitude: 80,
            longitude: 0
        )
        XCTAssertEqual(assessment.score, 81)
        XCTAssertNil(assessment.lightPollution)
    }

    func testOutOfCoverageIsExactFallback() {
        let service = ObservingQualityService(
            lightPollutionProvider: LocationGatedLightPollutionProvider(
                latitude: 45.45,
                longitude: -122.75,
                value: 18.5,
                tolerance: 0.01
            )
        )
        let covered = service.assess(nightConditionsScore: 90, latitude: 45.45, longitude: -122.75)
        XCTAssertNotNil(covered.lightPollution)
        XCTAssertLessThan(covered.score, 90)

        let out = service.assess(nightConditionsScore: 90, latitude: 80.0, longitude: 0.0)
        XCTAssertEqual(out.score, 90)
        XCTAssertNil(out.lightPollution)
    }

    func testDeterministicRepeatedAssessment() {
        let service = ObservingQualityService(
            lightPollutionProvider: FixedLightPollutionProvider(value: 19.5)
        )
        let a = service.assess(nightConditionsScore: 85, latitude: 1, longitude: 2)
        let b = service.assess(nightConditionsScore: 85, latitude: 1, longitude: 2)
        XCTAssertEqual(a, b)
    }

    func testProviderSwapDoesNotLeaveStaleBrightness() {
        let service = ObservingQualityService(
            lightPollutionProvider: LocationGatedLightPollutionProvider(
                latitude: 45.0,
                longitude: -122.0,
                value: 18.5,
                tolerance: 0.05
            )
        )
        let urban = service.assess(nightConditionsScore: 90, latitude: 45.0, longitude: -122.0)
        XCTAssertNotNil(urban.lightPollution)

        service.setLightPollutionProvider(
            LocationGatedLightPollutionProvider(
                latitude: 46.0,
                longitude: -123.0,
                value: 21.3,
                tolerance: 0.05
            )
        )
        // Old location must not still get urban brightness
        let stale = service.assess(nightConditionsScore: 90, latitude: 45.0, longitude: -122.0)
        XCTAssertNil(stale.lightPollution)
        XCTAssertEqual(stale.score, 90)

        let dark = service.assess(nightConditionsScore: 90, latitude: 46.0, longitude: -123.0)
        XCTAssertEqual(dark.score, 89) // base 1.0
    }

    func testSetProviderNilFallsBack() {
        let service = ObservingQualityService(
            lightPollutionProvider: FixedLightPollutionProvider(value: 18.5)
        )
        XCTAssertLessThan(
            service.assess(nightConditionsScore: 90, latitude: 0, longitude: 0).score,
            90
        )
        service.setLightPollutionProvider(nil)
        let fallback = service.assess(nightConditionsScore: 90, latitude: 0, longitude: 0)
        XCTAssertEqual(fallback.score, 90)
        XCTAssertNil(fallback.lightPollution)
    }
}
