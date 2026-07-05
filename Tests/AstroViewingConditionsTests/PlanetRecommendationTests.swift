import SharedCode
import XCTest

final class PlanetRecommendationTests: XCTestCase {
    func testAltitudeScoringImprovesPlanetRecommendation() {
        let low = recommendation(samples: Self.samples(altitudes: [12, 14, 16], azimuths: [160, 170, 180]))
        let high = recommendation(samples: Self.samples(altitudes: [35, 50, 62], azimuths: [160, 170, 180]))

        XCTAssertGreaterThan(high.score, low.score)
        XCTAssertTrue(high.reasons.contains(.highAltitude))
    }

    func testLowAltitudePenalty() {
        let low = recommendation(samples: Self.samples(altitudes: [9, 12, 14], azimuths: [250, 260, 270]))

        XCTAssertTrue(low.reasons.contains(.lowAltitude))
        XCTAssertLessThan(low.score, 55)
    }

    func testNotVisiblePlanetIsNotRecommended() {
        let provider = DefaultPlanetTargetRecommendationProvider(
            planetAstronomyProvider: FakePlanetAstronomyProvider(
                observations: ["jupiter": PlanetObservationData(
                    targetID: "jupiter",
                    samples: Self.samples(altitudes: [-12, -8, 2], azimuths: [90, 100, 110])
                )]
            )
        )

        let recommendation = provider.recommendation(for: Self.jupiterTarget, context: Self.context())

        XCTAssertNil(recommendation)
    }

    func testBestTimeSelectionUsesHighestUsefulSample() {
        let samples = [
            PlanetPositionSample(time: Self.date(hour: 20), altitude: 20, azimuth: 120),
            PlanetPositionSample(time: Self.date(hour: 21), altitude: 35, azimuth: 140),
            PlanetPositionSample(time: Self.date(hour: 22), altitude: 55, azimuth: 180),
            PlanetPositionSample(time: Self.date(hour: 23), altitude: 42, azimuth: 210)
        ]

        let recommendation = recommendation(samples: samples)

        XCTAssertEqual(recommendation.visibilityWindow.bestTime, Self.date(hour: 22))
        XCTAssertEqual(recommendation.visibilityWindow.direction, "S")
    }

    func testMoonlightHasLittleImpactOnPlanetScore() {
        let samples = Self.samples(altitudes: [35, 45, 55], azimuths: [160, 170, 180])
        let darkMoon = recommendation(samples: samples, moonIllumination: 5, moonAltitude: 70)
        let brightMoon = recommendation(samples: samples, moonIllumination: 98, moonAltitude: 70)

        XCTAssertLessThanOrEqual(darkMoon.score - brightMoon.score, 2)
        XCTAssertTrue(brightMoon.reasons.contains(.planetMoonlightResistant))
    }

    func testPoorWeatherReducesPlanetScore() {
        let samples = Self.samples(altitudes: [35, 45, 55], azimuths: [160, 170, 180])
        let clear = recommendation(samples: samples, hourlyScore: 0.2)
        let poor = recommendation(samples: samples, hourlyScore: 1.8)

        XCTAssertLessThan(poor.score, clear.score)
        XCTAssertTrue(poor.reasons.contains(.poorWeather))
    }

    func testRecommendationServiceUsesInjectedPlanetProvider() {
        let fakeProvider = FakePlanetAstronomyProvider(
            observations: [
                "jupiter": PlanetObservationData(
                    targetID: "jupiter",
                    samples: Self.samples(altitudes: [20, 35, 50], azimuths: [120, 150, 180])
                )
            ]
        )
        let service = DefaultTargetRecommendationService(
            catalogProvider: JupiterCatalogProvider(),
            positionProvider: DeepSkyTargetPositionProvider(),
            planetRecommendationProvider: DefaultPlanetTargetRecommendationProvider(
                planetAstronomyProvider: fakeProvider
            )
        )

        let recommendations = service.recommendations(for: Self.context(), limit: 5)

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations.first?.target.id, "jupiter")
        XCTAssertEqual(fakeProvider.requestedTargetIDs, ["jupiter"])
    }

    func testAzimuthToCompassDirectionFormatting() {
        XCTAssertEqual(DefaultPlanetTargetRecommendationProvider.compassDirection(for: 0), "N")
        XCTAssertEqual(DefaultPlanetTargetRecommendationProvider.compassDirection(for: 44), "NE")
        XCTAssertEqual(DefaultPlanetTargetRecommendationProvider.compassDirection(for: 91), "E")
        XCTAssertEqual(DefaultPlanetTargetRecommendationProvider.compassDirection(for: 181), "S")
        XCTAssertEqual(DefaultPlanetTargetRecommendationProvider.compassDirection(for: 269), "W")
        XCTAssertEqual(DefaultPlanetTargetRecommendationProvider.compassDirection(for: 315), "NW")
    }

    func testRecommendationSummaryUsesUppercaseCompassDirection() {
        let recommendation = recommendation(
            samples: [
                PlanetPositionSample(time: Self.date(hour: 28), altitude: 31, azimuth: 135)
            ]
        )

        XCTAssertEqual(recommendation.summary, "Best before dawn; only moderately high.")
        XCTAssertEqual(recommendation.visibilityWindow.direction, "SE")
    }

    func testLowVenusAfterSunsetMentionsWesternHorizonObstructions() {
        let recommendation = recommendation(
            target: Self.venusTarget,
            samples: [
                PlanetPositionSample(time: Self.date(hour: 19), altitude: 14, azimuth: 270)
            ]
        )

        XCTAssertEqual(
            recommendation?.summary,
            "Low in the W shortly after sunset; horizon obstructions may matter."
        )
    }

    func testPoorConditionsSummaryMentionsCloudLimitationForBeforeDawnPlanet() {
        let recommendation = recommendation(
            samples: [
                PlanetPositionSample(time: Self.date(hour: 28), altitude: 31, azimuth: 135)
            ],
            hourlyScore: 1.8
        )

        XCTAssertEqual(recommendation.summary, "Well placed before dawn, but clouds may block the view.")
        XCTAssertTrue(recommendation.reasons.contains(.poorWeather))
    }

    func testVenusEveningOnlyVisibilityUsesOnlyVisibleSamples() {
        let recommendation = recommendation(
            target: Self.venusTarget,
            samples: [
                PlanetPositionSample(time: Self.date(hour: 18), altitude: 22, azimuth: 260),
                PlanetPositionSample(time: Self.date(hour: 19), altitude: 12, azimuth: 270),
                PlanetPositionSample(time: Self.date(hour: 20), altitude: 7.9, azimuth: 280),
                PlanetPositionSample(time: Self.date(hour: 21), altitude: -2, azimuth: 290)
            ]
        )

        XCTAssertNotNil(recommendation)
        XCTAssertEqual(recommendation?.visibilityWindow.start, Self.date(hour: 18))
        XCTAssertEqual(
            recommendation!.visibilityWindow.end.timeIntervalSince(Self.date(hour: 19)),
            3_600 * (4 / 4.1),
            accuracy: 0.001
        )
        XCTAssertEqual(recommendation?.visibilityWindow.bestTime, Self.date(hour: 18))
    }

    func testVenusMorningOnlyVisibilityUsesOnlyVisibleSamples() {
        let recommendation = recommendation(
            target: Self.venusTarget,
            samples: [
                PlanetPositionSample(time: Self.date(hour: 21), altitude: -5, azimuth: 80),
                PlanetPositionSample(time: Self.date(hour: 24), altitude: 4, azimuth: 90),
                PlanetPositionSample(time: Self.date(hour: 27), altitude: 12, azimuth: 105),
                PlanetPositionSample(time: Self.date(hour: 28), altitude: 31, azimuth: 120)
            ]
        )

        XCTAssertNotNil(recommendation)
        XCTAssertEqual(recommendation?.visibilityWindow.start, Self.date(hour: 25).addingTimeInterval(30 * 60))
        XCTAssertEqual(recommendation?.visibilityWindow.end, Self.date(hour: 28).addingTimeInterval(15 * 60))
        XCTAssertEqual(recommendation?.visibilityWindow.bestTime, Self.date(hour: 28))
    }

    func testVenusNotVisibleWhenAllSamplesAreBelowVisibleAltitude() {
        let recommendation = recommendation(
            target: Self.venusTarget,
            samples: [
                PlanetPositionSample(time: Self.date(hour: 18), altitude: -8, azimuth: 90),
                PlanetPositionSample(time: Self.date(hour: 21), altitude: 0, azimuth: 100),
                PlanetPositionSample(time: Self.date(hour: 28), altitude: 7.9, azimuth: 110)
            ]
        )

        XCTAssertNil(recommendation)
    }

    func testVenusIsNotTreatedAsVisibleAllNightForShortEveningWindow() {
        let recommendation = recommendation(
            target: Self.venusTarget,
            samples: [
                PlanetPositionSample(time: Self.date(hour: 18), altitude: 24, azimuth: 260),
                PlanetPositionSample(time: Self.date(hour: 19), altitude: 13, azimuth: 270),
                PlanetPositionSample(time: Self.date(hour: 22), altitude: -10, azimuth: 285),
                PlanetPositionSample(time: Self.date(hour: 28), altitude: -30, azimuth: 300)
            ]
        )

        XCTAssertLessThan(recommendation!.visibilityWindow.end, Self.context().astronomicalNightEnd)
        XCTAssertNotEqual(recommendation?.visibilityWindow.start, Self.context().astronomicalNightStart)
        XCTAssertNotEqual(recommendation?.visibilityWindow.end, Self.context().astronomicalNightEnd)
    }

    func testVenusVisibilityWindowExcludesLowAltitudeAndBelowHorizonSamples() {
        let recommendation = recommendation(
            target: Self.venusTarget,
            samples: [
                PlanetPositionSample(time: Self.date(hour: 19), altitude: 6, azimuth: 250),
                PlanetPositionSample(time: Self.date(hour: 20), altitude: 8, azimuth: 260),
                PlanetPositionSample(time: Self.date(hour: 21), altitude: 9, azimuth: 270),
                PlanetPositionSample(time: Self.date(hour: 22), altitude: -1, azimuth: 280)
            ]
        )

        XCTAssertEqual(recommendation?.visibilityWindow.start, Self.date(hour: 20))
        XCTAssertEqual(recommendation?.visibilityWindow.end, Self.date(hour: 21).addingTimeInterval(6 * 60))
        XCTAssertEqual(recommendation?.visibilityWindow.bestTime, Self.date(hour: 21))
    }

    func testVisibilityWindowInterpolatesStartBeforeFirstVisibleSample() {
        let recommendation = recommendation(samples: [
            PlanetPositionSample(time: Self.date(hour: 20), altitude: 6, azimuth: 120),
            PlanetPositionSample(time: Self.date(hour: 20).addingTimeInterval(15 * 60), altitude: 10, azimuth: 125),
            PlanetPositionSample(time: Self.date(hour: 20).addingTimeInterval(30 * 60), altitude: 12, azimuth: 130)
        ])

        XCTAssertEqual(
            recommendation.visibilityWindow.start,
            Self.date(hour: 20).addingTimeInterval(7.5 * 60)
        )
        XCTAssertLessThan(
            recommendation.visibilityWindow.start,
            Self.date(hour: 20).addingTimeInterval(15 * 60)
        )
    }

    func testVisibilityWindowInterpolatesEndAfterLastVisibleSample() {
        let recommendation = recommendation(samples: [
            PlanetPositionSample(time: Self.date(hour: 20), altitude: 12, azimuth: 120),
            PlanetPositionSample(time: Self.date(hour: 20).addingTimeInterval(15 * 60), altitude: 10, azimuth: 125),
            PlanetPositionSample(time: Self.date(hour: 20).addingTimeInterval(30 * 60), altitude: 4, azimuth: 130)
        ])

        XCTAssertEqual(
            recommendation.visibilityWindow.end,
            Self.date(hour: 20).addingTimeInterval(20 * 60)
        )
        XCTAssertGreaterThan(
            recommendation.visibilityWindow.end,
            Self.date(hour: 20).addingTimeInterval(15 * 60)
        )
        XCTAssertLessThan(
            recommendation.visibilityWindow.end,
            Self.date(hour: 20).addingTimeInterval(30 * 60)
        )
    }

    func testLowPrecisionProviderMapsSupportedPlanetTargetsAndReturnsHorizontalCoordinates() {
        let provider = LowPrecisionPlanetAstronomyProvider(sampleInterval: 2 * 3600)
        let targets = [
            Self.venusTarget,
            Self.marsTarget,
            Self.jupiterTarget,
            Self.saturnTarget
        ]

        for target in targets {
            let observation = provider.planetObservation(for: target, context: Self.cupertinoJune2026Context())

            XCTAssertEqual(observation?.targetID, target.id)
            XCTAssertFalse(observation?.samples.isEmpty ?? true, "\(target.name) should produce samples")
            XCTAssertTrue(
                observation?.samples.allSatisfy { sample in
                    (-90...90).contains(sample.altitude)
                        && (0..<360).contains(sample.azimuth)
                        && (0...180).contains(sample.solarElongation ?? -1)
                } == true,
                "\(target.name) samples should be topocentric horizontal coordinates with solar elongation"
            )
        }
    }

    func testLowPrecisionProviderUsesSchlyterDayNumberConvention() throws {
        let provider = LowPrecisionPlanetAstronomyProvider(sampleInterval: 2 * 3600)
        let observation = try XCTUnwrap(
            provider.planetObservation(for: Self.jupiterTarget, context: Self.cupertinoJune2026Context())
        )
        let sample = try XCTUnwrap(observation.samples.first)

        XCTAssertEqual(sample.time, Self.date(year: 2026, month: 6, day: 30, hour: 1, minute: 26))
        XCTAssertEqual(sample.altitude, 39.532_328_397_078_97, accuracy: 0.001)
        XCTAssertEqual(sample.azimuth, 266.782_421_342_379_17, accuracy: 0.001)
    }

    func testUnknownPlanetTargetDoesNotMapToConcreteProviderBody() {
        let provider = LowPrecisionPlanetAstronomyProvider()
        let target = ObservableTarget(
            id: "pluto",
            name: "Pluto",
            type: .planet,
            preferredEquipment: .telescope,
            difficulty: 0.8
        )

        XCTAssertNil(provider.planetObservation(for: target, context: Self.cupertinoJune2026Context()))
    }

    func testVenusIsNotRecommendedDeepIntoNightWhenSolarElongationPrecludesMidnightVisibility() {
        let context = Self.cupertinoJune2026Context()
        let astronomyProvider = LowPrecisionPlanetAstronomyProvider(sampleInterval: 30 * 60)
        let recommendationProvider = DefaultPlanetTargetRecommendationProvider(
            planetAstronomyProvider: astronomyProvider
        )
        let observation = astronomyProvider.planetObservation(for: Self.venusTarget, context: context)
        let recommendation = recommendationProvider.recommendation(for: Self.venusTarget, context: context)
        let deepNightStart = context.astronomicalNightStart.addingTimeInterval(3 * 3600)

        XCTAssertNotNil(recommendation)
        XCTAssertLessThanOrEqual(
            observation?.samples.compactMap(\.solarElongation).max() ?? 180,
            45,
            "Fixture should represent an inner-planet elongation case that cannot support midnight visibility"
        )
        XCTAssertTrue(
            observation?.samples.filter { $0.time >= deepNightStart }
                .allSatisfy { $0.altitude < 8 } == true,
            "Small-elongation Venus should not remain above the visible altitude threshold deep into the night"
        )
        XCTAssertLessThan(
            recommendation!.visibilityWindow.end,
            deepNightStart,
            "Venus visibility window should come from above-horizon samples near twilight, not the broader night"
        )
    }

    private func recommendation(
        samples: [PlanetPositionSample],
        hourlyScore: Double = 0.2,
        moonIllumination: Int = 20,
        moonAltitude: Double = -5
    ) -> TargetRecommendation {
        recommendation(
            target: Self.jupiterTarget,
            samples: samples,
            hourlyScore: hourlyScore,
            moonIllumination: moonIllumination,
            moonAltitude: moonAltitude
        )!
    }

    private func recommendation(
        target: ObservableTarget,
        samples: [PlanetPositionSample],
        hourlyScore: Double = 0.2,
        moonIllumination: Int = 20,
        moonAltitude: Double = -5
    ) -> TargetRecommendation? {
        let provider = DefaultPlanetTargetRecommendationProvider(
            planetAstronomyProvider: FakePlanetAstronomyProvider(
                observations: [
                    target.id: PlanetObservationData(targetID: target.id, samples: samples)
                ]
            )
        )

        return provider.recommendation(
            for: target,
            context: Self.context(
                hourlyScore: hourlyScore,
                moonIllumination: moonIllumination,
                moonAltitude: moonAltitude
            )
        )
    }

    private static let jupiterTarget = ObservableTarget(
        id: "jupiter",
        name: "Jupiter",
        type: .planet,
        preferredEquipment: .smallTelescope,
        difficulty: 0.25
    )

    private static let venusTarget = ObservableTarget(
        id: "venus",
        name: "Venus",
        type: .planet,
        preferredEquipment: .nakedEye,
        difficulty: 0.1
    )

    private static let marsTarget = ObservableTarget(
        id: "mars",
        name: "Mars",
        type: .planet,
        preferredEquipment: .nakedEye,
        difficulty: 0.2
    )

    private static let saturnTarget = ObservableTarget(
        id: "saturn",
        name: "Saturn",
        type: .planet,
        preferredEquipment: .smallTelescope,
        difficulty: 0.35
    )

    private static func samples(
        altitudes: [Double],
        azimuths: [Double]
    ) -> [PlanetPositionSample] {
        zip(altitudes.indices, altitudes).map { index, altitude in
            PlanetPositionSample(
                time: date(hour: 21 + index),
                altitude: altitude,
                azimuth: azimuths[index]
            )
        }
    }

    private static func context(
        hourlyScore: Double = 0.2,
        moonIllumination: Int = 20,
        moonAltitude: Double = -5
    ) -> TargetRecommendationContext {
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
                    moonIlluminationAvg: moonIllumination,
                    windSpeedAvg: hourlyScore >= 1 ? 18 : 2
                ),
                bestWindow: NightQualityAssessment.TimeWindow(
                    start: date(hour: 21),
                    end: date(hour: 25)
                ),
                hourlyRatings: (18..<30).map { hour in
                    NightQualityAssessment.HourlyRating(
                        time: date(hour: hour),
                        score: hourlyScore,
                        cloudCover: hourlyScore >= 1 ? 90 : 5,
                        fogScore: hourlyScore >= 1 ? 80 : 5,
                        moonIllumination: moonIllumination,
                        moonAltitude: moonAltitude,
                        windSpeed: hourlyScore >= 1 ? 18 : 2
                    )
                },
                nightStart: date(hour: 20),
                nightEnd: date(hour: 29)
            ),
            moonInfo: MoonInfo(
                phase: Double(moonIllumination) / 100,
                phaseName: "Test Moon",
                altitude: moonAltitude,
                illumination: moonIllumination,
                emoji: ""
            )
        )
    }

    private static func cupertinoJune2026Context() -> TargetRecommendationContext {
        let start = date(year: 2026, month: 6, day: 30, hour: 3, minute: 26)
        let end = date(year: 2026, month: 6, day: 30, hour: 11, minute: 26)

        return TargetRecommendationContext(
            location: CachedLocation(
                name: "Cupertino",
                latitude: 37.323,
                longitude: -122.032,
                elevation: 72
            ),
            astronomicalNightStart: start,
            astronomicalNightEnd: end,
            nightQuality: NightQualityAssessment(
                rating: .good,
                summary: "Test",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: 5,
                    fogScoreAvg: 5,
                    moonIlluminationAvg: 20,
                    windSpeedAvg: 2
                ),
                bestWindow: NightQualityAssessment.TimeWindow(start: start, end: end),
                hourlyRatings: stride(from: 0, through: 8, by: 1).map { hourOffset in
                    NightQualityAssessment.HourlyRating(
                        time: start.addingTimeInterval(Double(hourOffset) * 3600),
                        score: 0.2,
                        cloudCover: 5,
                        fogScore: 5,
                        moonIllumination: 20,
                        moonAltitude: -5,
                        windSpeed: 2
                    )
                },
                nightStart: start,
                nightEnd: end
            ),
            moonInfo: MoonInfo(
                phase: 0.2,
                phaseName: "Waxing Crescent",
                altitude: -5,
                illumination: 20,
                emoji: ""
            )
        )
    }

    private static func date(hour: Int) -> Date {
        date(
            year: 2026,
            month: 3,
            day: 1 + hour / 24,
            hour: hour % 24
        )
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

private final class FakePlanetAstronomyProvider: PlanetAstronomyProviding, @unchecked Sendable {
    private let observations: [String: PlanetObservationData]
    private(set) var requestedTargetIDs: [String] = []

    init(observations: [String: PlanetObservationData]) {
        self.observations = observations
    }

    func planetObservation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> PlanetObservationData? {
        requestedTargetIDs.append(target.id)
        return observations[target.id]
    }
}

private struct JupiterCatalogProvider: TargetCatalogProvider {
    private let catalog = DefaultTargetCatalogProvider()

    func targets(for context: TargetRecommendationContext) -> [ObservableTarget] {
        catalog.targets(for: context).filter { $0.id == "jupiter" }
    }
}
