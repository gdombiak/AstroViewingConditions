import SharedCode
import XCTest

final class MoonRecommendationTests: XCTestCase {
    func testQuarterPhasesScoreBetterForMoonSurfaceDetail() {
        let firstQuarter = recommendation(phase: 0.25, illumination: 50)
        let lastQuarter = recommendation(phase: 0.75, illumination: 50)
        let gibbous = recommendation(phase: 0.62, illumination: 80)

        XCTAssertGreaterThan(firstQuarter.score, gibbous.score)
        XCTAssertGreaterThan(lastQuarter.score, gibbous.score)
        XCTAssertTrue(firstQuarter.reasons.contains(.excellentMoonCraterDetail))
        XCTAssertTrue(lastQuarter.summary.contains("last quarter"))
    }

    func testFullMoonProducesGoodRecommendationWithDeepSkyWarning() {
        let fullMoon = recommendation(phase: 0.50, illumination: 98)

        XCTAssertGreaterThanOrEqual(fullMoon.score, 70)
        XCTAssertTrue(fullMoon.reasons.contains(.brightFullMoonDeepSkyImpact))
        XCTAssertEqual(
            fullMoon.summary,
            "Bright full Moon; good lunar target but poor for faint deep-sky objects."
        )
    }

    func testNewMoonProducesPoorMoonRecommendationWithDarkSkyContext() {
        let newMoon = recommendation(phase: 0.01, illumination: 2)

        XCTAssertLessThan(newMoon.score, 40)
        XCTAssertTrue(newMoon.reasons.contains(.newMoonDarkSky))
        XCTAssertTrue(newMoon.summary.contains("favorable for deep-sky darkness"))
    }

    func testMoonVisibleScoresBetterThanNotVisibleDuringUsefulWindow() {
        let visible = recommendation(
            phase: 0.25,
            illumination: 50,
            samples: Self.samples(altitudes: [12, 24, 38, 30])
        )
        let notVisible = recommendation(
            phase: 0.25,
            illumination: 50,
            samples: Self.samples(altitudes: [-18, -12, -8, -4])
        )

        XCTAssertGreaterThan(visible.score, notVisible.score)
        XCTAssertTrue(notVisible.reasons.contains(.moonBelowUsefulWindow))
    }

    func testPoorWeatherReducesMoonRecommendationScore() {
        let goodWeather = recommendation(phase: 0.25, illumination: 50, hourlyScore: 0.2)
        let poorWeather = recommendation(phase: 0.25, illumination: 50, hourlyScore: 1.8)

        XCTAssertLessThan(poorWeather.score, goodWeather.score)
        XCTAssertTrue(poorWeather.reasons.contains(.poorWeather))
    }

    func testPoorConditionsSummaryMentionsCloudLimitationForFullMoon() {
        let fullMoon = recommendation(phase: 0.50, illumination: 98, hourlyScore: 1.8)

        XCTAssertEqual(fullMoon.summary, "Bright full Moon; clouds may limit visibility.")
        XCTAssertTrue(fullMoon.reasons.contains(.poorWeather))
    }

    func testRecommendationServiceUsesInjectedMoonProvider() {
        let fakeMoonProvider = FakeMoonAstronomyProvider(
            observation: Self.observation(phase: 0.01, illumination: 2),
            onObservation: {}
        )
        let service = DefaultTargetRecommendationService(
            catalogProvider: MoonCatalogProvider(),
            positionProvider: DeepSkyTargetPositionProvider(),
            moonRecommendationProvider: DefaultMoonTargetRecommendationProvider(
                moonAstronomyProvider: fakeMoonProvider
            )
        )

        let recommendations = service.recommendations(for: Self.context(), limit: 5)

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations.first?.target.type, .moon)
        XCTAssertTrue(recommendations.first?.reasons.contains(.newMoonDarkSky) == true)
        XCTAssertEqual(fakeMoonProvider.callCount, 1)
    }

    private func recommendation(
        phase: Double,
        illumination: Int,
        hourlyScore: Double = 0.2,
        samples: [MoonPositionSample]? = nil
    ) -> TargetRecommendation {
        let samples = samples ?? Self.samples(altitudes: [18, 35, 48, 30])
        let provider = DefaultMoonTargetRecommendationProvider(
            moonAstronomyProvider: FakeMoonAstronomyProvider(
                observation: Self.observation(
                    phase: phase,
                    illumination: illumination,
                    samples: samples
                ),
                onObservation: {}
            )
        )

        return provider.recommendation(
            for: Self.moonTarget,
            context: Self.context(hourlyScore: hourlyScore)
        )!
    }

    private static let moonTarget = ObservableTarget(
        id: "moon",
        name: "Moon",
        type: .moon,
        preferredEquipment: .nakedEye,
        difficulty: 0.1
    )

    private static func observation(
        phase: Double,
        illumination: Int,
        samples: [MoonPositionSample]? = nil
    ) -> MoonObservationData {
        let samples = samples ?? Self.samples(altitudes: [18, 35, 48, 30])
        return MoonObservationData(
            phase: phase,
            phaseName: phaseName(for: phase, illumination: illumination),
            illumination: illumination,
            rise: date(hour: 19),
            set: date(hour: 27),
            alwaysUp: false,
            alwaysDown: samples.allSatisfy { $0.altitude <= 0 },
            positionSamples: samples
        )
    }

    private static func samples(altitudes: [Double]) -> [MoonPositionSample] {
        altitudes.enumerated().map { index, altitude in
            MoonPositionSample(
                time: date(hour: 21 + index),
                altitude: altitude,
                azimuth: 160 + Double(index * 10)
            )
        }
    }

    private static func context(hourlyScore: Double = 0.2) -> TargetRecommendationContext {
        TargetRecommendationContext(
            location: CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
            astronomicalNightStart: date(hour: 20),
            astronomicalNightEnd: date(hour: 29),
            nightQuality: NightQualityAssessment(
                rating: NightQualityAssessment.Rating.from(score: hourlyScore),
                summary: "Test",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: hourlyScore >= 1 ? 90 : 5,
                    fogScoreAvg: hourlyScore >= 1 ? 80 : 5,
                    moonIlluminationAvg: 50,
                    windSpeedAvg: hourlyScore >= 1 ? 18 : 2
                ),
                bestWindow: NightQualityAssessment.TimeWindow(
                    start: date(hour: 21),
                    end: date(hour: 25)
                ),
                hourlyRatings: (20..<29).map { hour in
                    NightQualityAssessment.HourlyRating(
                        time: date(hour: hour),
                        score: hourlyScore,
                        cloudCover: hourlyScore >= 1 ? 90 : 5,
                        fogScore: hourlyScore >= 1 ? 80 : 5,
                        moonIllumination: 50,
                        moonAltitude: 35,
                        windSpeed: hourlyScore >= 1 ? 18 : 2
                    )
                },
                nightStart: date(hour: 20),
                nightEnd: date(hour: 29)
            ),
            moonInfo: MoonInfo(
                phase: 0.25,
                phaseName: "First Quarter",
                altitude: 35,
                illumination: 50,
                emoji: ""
            )
        )
    }

    private static func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1 + hour / 24
        components.hour = hour % 24
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private static func phaseName(for phase: Double, illumination: Int) -> String {
        if illumination <= 8 { return "New Moon" }
        if abs(phase - 0.25) <= 0.08 { return "First Quarter" }
        if abs(phase - 0.75) <= 0.08 { return "Last Quarter" }
        if illumination >= 90 { return "Full Moon" }
        return "Moon"
    }
}

private final class FakeMoonAstronomyProvider: MoonAstronomyProviding, @unchecked Sendable {
    private let observation: MoonObservationData
    private let onObservation: () -> Void
    private(set) var callCount = 0

    init(observation: MoonObservationData, onObservation: @escaping () -> Void) {
        self.observation = observation
        self.onObservation = onObservation
    }

    func moonObservation(for context: TargetRecommendationContext) -> MoonObservationData {
        callCount += 1
        onObservation()
        return observation
    }
}

private struct MoonCatalogProvider: TargetCatalogProvider {
    private let catalog = DefaultTargetCatalogProvider()

    func targets(for context: TargetRecommendationContext) -> [ObservableTarget] {
        catalog.targets(for: context).filter { $0.type == .moon }
    }
}
