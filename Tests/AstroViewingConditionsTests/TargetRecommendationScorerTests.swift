import SharedCode
import XCTest

final class TargetRecommendationScorerTests: XCTestCase {
    private let scorer = DefaultTargetRecommendationScorer()

    func testHigherAltitudeImprovesScore() {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 5, moonAltitude: -5)
        let lowWindow = makeWindow(maxAltitude: 20)
        let highWindow = makeWindow(maxAltitude: 70)
        let target = makeTarget(type: .planet)

        let low = scorer.recommendation(for: target, window: lowWindow, context: context)
        let high = scorer.recommendation(for: target, window: highWindow, context: context)

        XCTAssertGreaterThan(high.score, low.score)
    }

    func testDeepSkyOutsideAstronomicalDarknessScoresLower() {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 5, moonAltitude: -5)
        let darkWindow = makeWindow(startHour: 22, endHour: 24, maxAltitude: 65)
        let twilightWindow = makeWindow(startHour: 18, endHour: 19, maxAltitude: 65)
        let target = makeTarget(type: .deepSky)

        let dark = scorer.recommendation(for: target, window: darkWindow, context: context)
        let twilight = scorer.recommendation(for: target, window: twilightWindow, context: context)

        XCTAssertGreaterThan(dark.score, twilight.score)
        XCTAssertTrue(twilight.reasons.contains(.outsideAstronomicalDarkness))
    }

    func testStrongMoonlightPenalizesDeepSkyMoreThanPlanets() {
        let lowMoon = makeContext(hourlyScore: 0.2, moonIllumination: 5, moonAltitude: 60)
        let brightMoon = makeContext(hourlyScore: 0.2, moonIllumination: 95, moonAltitude: 60)
        let window = makeWindow(maxAltitude: 65)
        let deepSky = makeTarget(type: .deepSky, difficulty: 0.2)
        let planet = makeTarget(type: .planet, difficulty: 0.2)

        let deepSkyLowMoon = scorer.recommendation(for: deepSky, window: window, context: lowMoon)
        let deepSkyBrightMoon = scorer.recommendation(for: deepSky, window: window, context: brightMoon)
        let planetLowMoon = scorer.recommendation(for: planet, window: window, context: lowMoon)
        let planetBrightMoon = scorer.recommendation(for: planet, window: window, context: brightMoon)

        let deepSkyPenalty = deepSkyLowMoon.score - deepSkyBrightMoon.score
        let planetPenalty = planetLowMoon.score - planetBrightMoon.score

        XCTAssertGreaterThan(deepSkyPenalty, planetPenalty)
    }

    func testM31PrimaryReasonMentionsMoonWashoutUnderFullMoon() {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let window = makeWindow(maxAltitude: 65)
        let m31 = catalogTarget(id: "m31")
        let m13 = catalogTarget(id: "m13")

        let galaxy = scorer.recommendation(for: m31, window: window, context: context)
        let globular = scorer.recommendation(for: m13, window: window, context: context)

        XCTAssertLessThanOrEqual(galaxy.score, globular.score - 20)
        XCTAssertEqual(
            galaxy.summary,
            "High in the sky, but bright Moon will wash out galaxy detail."
        )
    }

    func testM13PrimaryReasonMentionsModerateMoonImpactUnderFullMoon() {
        let fullMoon = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let newMoon = makeContext(hourlyScore: 0.2, moonIllumination: 0, moonAltitude: 70)
        let target = catalogTarget(id: "m13")
        let window = makeWindow(maxAltitude: 65)

        let bright = scorer.recommendation(for: target, window: window, context: fullMoon)
        let dark = scorer.recommendation(for: target, window: window, context: newMoon)

        XCTAssertGreaterThanOrEqual(bright.score, 50)
        XCTAssertLessThan(bright.score, dark.score)
        XCTAssertEqual(bright.summary, "High in the sky; bright Moon has a moderate impact.")
    }

    func testDoubleStarIsBarelyPenalizedByFullMoon() {
        let fullMoon = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let newMoon = makeContext(hourlyScore: 0.2, moonIllumination: 0, moonAltitude: 70)
        let target = makeTarget(type: .deepSky, difficulty: 0.2, deepSkyObjectType: .doubleStar)
        let window = makeWindow(maxAltitude: 65)

        let bright = scorer.recommendation(for: target, window: window, context: fullMoon)
        let dark = scorer.recommendation(for: target, window: window, context: newMoon)

        XCTAssertLessThanOrEqual(dark.score - bright.score, 5)
    }

    func testM31PrimaryReasonRemainsPositiveUnderNewMoonOrMoonBelowHorizon() {
        let fullMoon = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let newMoon = makeContext(hourlyScore: 0.2, moonIllumination: 0, moonAltitude: 70)
        let moonBelowHorizon = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: -5)
        let target = catalogTarget(id: "m31")
        let window = makeWindow(maxAltitude: 65)

        let bright = scorer.recommendation(for: target, window: window, context: fullMoon)
        let dark = scorer.recommendation(for: target, window: window, context: newMoon)
        let moonDown = scorer.recommendation(for: target, window: window, context: moonBelowHorizon)

        XCTAssertGreaterThan(dark.score, bright.score + 40)
        XCTAssertEqual(moonDown.score, dark.score)
        XCTAssertEqual(dark.summary, "High in the sky during the best window.")
    }

    func testCuratedCatalogContainsInitialDeepSkyTargets() {
        let ids = Set(CuratedDeepSkyCatalogProvider().entries().map(\.id))

        XCTAssertTrue([
            "m13", "m31", "m2", "m30", "m52", "m11", "m57", "m27",
            "ngc7009", "ngc7293", "m51", "m64", "m81", "m82", "m92",
            "albireo", "epsilon-lyrae"
        ].allSatisfy(ids.contains))
    }

    func testCuratedTargetsExposeSpecificDisplayTypeNames() {
        let expectedLabels = [
            "epsilon-lyrae": "Double Star",
            "albireo": "Double Star",
            "m57": "Planetary Nebula",
            "m92": "Globular Cluster",
            "m31": "Galaxy"
        ]

        for (id, expectedLabel) in expectedLabels {
            XCTAssertEqual(catalogTarget(id: id).displayTypeName, expectedLabel, id)
        }
    }

    func testBrightMoonPrimaryReasonsUseDeepSkyObjectType() {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let window = makeWindow(maxAltitude: 65)
        let expectedSummaries = [
            "epsilon-lyrae": "Good target even under bright Moon.",
            "albireo": "Good target even under bright Moon.",
            "m57": "Small bright nebula; well placed despite bright Moon.",
            "m92": "High in the sky; bright Moon has a moderate impact.",
            "m31": "High in the sky, but bright Moon will wash out galaxy detail."
        ]

        for (id, expectedSummary) in expectedSummaries {
            let recommendation = scorer.recommendation(
                for: catalogTarget(id: id),
                window: window,
                context: context
            )
            XCTAssertEqual(recommendation.summary, expectedSummary, id)
        }
    }

    func testM57UsesMoonAwareReasonWhenBrightMoonIsLow() {
        let brightMoon = makeContext(hourlyScore: 0.2, moonIllumination: 98, moonAltitude: 5)
        let recommendation = scorer.recommendation(
            for: catalogTarget(id: "m57"),
            window: makeWindow(maxAltitude: 65),
            context: brightMoon
        )

        XCTAssertNotEqual(recommendation.summary, "High in the sky during the best window.")
        XCTAssertTrue(
            recommendation.summary.localizedCaseInsensitiveContains("bright Moon")
                || recommendation.summary.localizedCaseInsensitiveContains("contrast")
        )
    }

    func testM57MayUsePositiveHighAltitudeReasonNearNewMoon() {
        let newMoon = makeContext(hourlyScore: 0.2, moonIllumination: 1, moonAltitude: 65)
        let recommendation = scorer.recommendation(
            for: catalogTarget(id: "m57"),
            window: makeWindow(maxAltitude: 65),
            context: newMoon
        )

        XCTAssertEqual(recommendation.summary, "High in the sky during the best window.")
    }

    func testDeepSkyWindowsUseTargetAltitudeInsteadOfWholeNight() {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 5, moonAltitude: -5)
        let provider = DeepSkyTargetPositionProvider(minimumAltitude: 40)
        let targets = DefaultTargetCatalogProvider().targets(for: context).filter { $0.type == .deepSky }
        let windows = targets.flatMap { provider.visibilityWindows(for: $0, context: context) }

        XCTAssertFalse(windows.isEmpty)
        XCTAssertTrue(windows.allSatisfy { window in
            window.start >= context.astronomicalNightStart
                && window.end <= context.astronomicalNightEnd
                && (window.maxAltitude ?? -.infinity) >= 40
        })
        XCTAssertTrue(windows.contains { window in
            window.start > context.astronomicalNightStart
                || window.end < context.astronomicalNightEnd
        })
    }

    func testDeepSkyWindowMayUseWholeNightWhenEverySampleIsVisible() {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 5, moonAltitude: -5)
        let provider = DeepSkyTargetPositionProvider(minimumAltitude: -90)

        let windows = provider.visibilityWindows(
            for: catalogTarget(id: "m31"),
            context: context
        )

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.start, context.astronomicalNightStart)
        XCTAssertEqual(windows.first?.end, context.astronomicalNightEnd)
    }

    func testOpenClusterRemainsUsableUnderBrightMoon() {
        let fullMoon = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let target = catalogTarget(id: "m11")

        let recommendation = scorer.recommendation(
            for: target,
            window: makeWindow(maxAltitude: 65),
            context: fullMoon
        )

        XCTAssertGreaterThanOrEqual(recommendation.score, 50)
        XCTAssertEqual(recommendation.summary, "Visible despite bright Moon.")
    }

    func testFullMoonRankingFavorsMoonResistantDeepSkyTargets() {
        let fullMoon = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let window = makeWindow(maxAltitude: 65)
        let ids = ["m31", "m13", "m11", "m57", "albireo"]

        let ranked = ids
            .map { scorer.recommendation(for: catalogTarget(id: $0), window: window, context: fullMoon) }
            .sorted { $0.score > $1.score }

        XCTAssertEqual(ranked.first?.target.id, "albireo")
        XCTAssertEqual(ranked.last?.target.id, "m31")
        XCTAssertTrue(ranked.prefix(4).allSatisfy { $0.target.deepSkyObjectType != .galaxy })
    }

    func testCompactPlanetaryNebulaIsLessMoonSensitiveThanHelixNebula() {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let targets = DefaultTargetCatalogProvider().targets(for: context)
        let ring = try! XCTUnwrap(targets.first { $0.id == "m57" })
        let helix = try! XCTUnwrap(targets.first { $0.id == "ngc7293" })

        XCTAssertLessThan(
            try! XCTUnwrap(ring.moonInterferenceSensitivity),
            try! XCTUnwrap(helix.moonInterferenceSensitivity)
        )
    }

    func testM31RecoversNearNewMoon() {
        let fullMoon = makeContext(hourlyScore: 0.2, moonIllumination: 100, moonAltitude: 70)
        let newMoon = makeContext(hourlyScore: 0.2, moonIllumination: 1, moonAltitude: 70)
        let target = catalogTarget(id: "m31")
        let window = makeWindow(maxAltitude: 65)

        let bright = scorer.recommendation(for: target, window: window, context: fullMoon)
        let dark = scorer.recommendation(for: target, window: window, context: newMoon)

        XCTAssertGreaterThanOrEqual(dark.score - bright.score, 45)
    }

    func testPoorWeatherLowersAllTargetRecommendations() {
        let excellent = makeContext(hourlyScore: 0.15, moonIllumination: 5, moonAltitude: -5)
        let poor = makeContext(hourlyScore: 1.8, moonIllumination: 5, moonAltitude: -5)
        let window = makeWindow(maxAltitude: 60)
        let targets = [
            makeTarget(type: .moon),
            makeTarget(type: .planet),
            makeTarget(type: .deepSky),
            makeTarget(type: .satellite),
            makeTarget(type: .meteorShower)
        ]

        for target in targets {
            let excellentRecommendation = scorer.recommendation(for: target, window: window, context: excellent)
            let poorRecommendation = scorer.recommendation(for: target, window: window, context: poor)

            XCTAssertLessThan(
                poorRecommendation.score,
                excellentRecommendation.score,
                "\(target.type.displayName) should score lower in poor weather"
            )
        }
    }

    func testPoorConditionsSummaryMentionsCloudLimitationForDeepSkyTarget() {
        let context = makeContext(hourlyScore: 1.8, moonIllumination: 5, moonAltitude: -5)
        let recommendation = scorer.recommendation(
            for: makeTarget(type: .deepSky),
            window: makeWindow(maxAltitude: 70),
            context: context
        )

        XCTAssertEqual(recommendation.summary, "High in the sky, but clouds may block the view.")
        XCTAssertTrue(recommendation.reasons.contains(.poorWeather))
    }

    func testRecommendationServiceSortsFinalScoresDescendingBeforeLimit() {
        let targets = [
            makeTarget(id: "low", name: "Low", type: .deepSky),
            makeTarget(id: "high", name: "High", type: .deepSky),
            makeTarget(id: "middle", name: "Middle", type: .deepSky)
        ]
        let service = DefaultTargetRecommendationService(
            catalogProvider: FixedCatalogProvider(targets: targets),
            positionProvider: FixedWindowProvider(window: makeWindow(maxAltitude: 50)),
            scorer: FixedRecommendationScorer(scores: [
                "low": 20,
                "high": 90,
                "middle": 60
            ]),
            moonRecommendationProvider: EmptyMoonRecommendationProvider(),
            planetRecommendationProvider: EmptyPlanetRecommendationProvider()
        )

        let recommendations = service.recommendations(
            for: makeContext(hourlyScore: 0.2, moonIllumination: 5, moonAltitude: -5),
            limit: 2
        )

        XCTAssertEqual(recommendations.map(\.target.id), ["high", "middle"])
        XCTAssertEqual(recommendations.map(\.score), [90, 60])
    }

    private func makeTarget(
        id: String? = nil,
        name: String? = nil,
        type: ObservableTargetType,
        difficulty: Double = 0.3,
        deepSkyObjectType: DeepSkyObjectType? = nil
    ) -> ObservableTarget {
        ObservableTarget(
            id: id ?? type.rawValue,
            name: name ?? type.displayName,
            type: type,
            preferredEquipment: .binoculars,
            difficulty: difficulty,
            deepSkyObjectType: deepSkyObjectType
        )
    }

    private func catalogTarget(id: String) -> ObservableTarget {
        let context = makeContext(hourlyScore: 0.2, moonIllumination: 0, moonAltitude: -5)
        return try! XCTUnwrap(
            DefaultTargetCatalogProvider().targets(for: context).first { $0.id == id }
        )
    }

    private func makeContext(
        hourlyScore: Double,
        moonIllumination: Int,
        moonAltitude: Double
    ) -> TargetRecommendationContext {
        TargetRecommendationContext(
            location: CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
            astronomicalNightStart: date(hour: 20),
            astronomicalNightEnd: date(hour: 29),
            nightQuality: NightQualityAssessment(
                rating: NightQualityAssessment.Rating.from(score: hourlyScore),
                summary: "Test conditions",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: hourlyScore >= 1 ? 90 : 5,
                    fogScoreAvg: hourlyScore >= 1 ? 80 : 5,
                    moonIlluminationAvg: moonIllumination,
                    windSpeedAvg: hourlyScore >= 1 ? 18 : 2
                ),
                bestWindow: NightQualityAssessment.TimeWindow(
                    start: date(hour: 21),
                    end: date(hour: 24)
                ),
                hourlyRatings: (20..<29).map { hour in
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

    private func makeWindow(
        startHour: Int = 21,
        endHour: Int = 23,
        maxAltitude: Double
    ) -> TargetVisibilityWindow {
        TargetVisibilityWindow(
            start: date(hour: startHour),
            end: date(hour: endHour),
            bestTime: date(hour: startHour + 1),
            maxAltitude: maxAltitude,
            direction: "S"
        )
    }

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1 + hour / 24
        components.hour = hour % 24
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

private struct FixedCatalogProvider: TargetCatalogProvider {
    let targets: [ObservableTarget]

    func targets(for context: TargetRecommendationContext) -> [ObservableTarget] {
        targets
    }
}

private struct FixedWindowProvider: TargetPositionProvider {
    let window: TargetVisibilityWindow

    func visibilityWindows(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> [TargetVisibilityWindow] {
        [window]
    }
}

private struct FixedRecommendationScorer: TargetRecommendationScoring {
    let scores: [String: Int]

    func recommendation(
        for target: ObservableTarget,
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> TargetRecommendation {
        TargetRecommendation(
            target: target,
            score: scores[target.id, default: 0],
            visibilityWindow: window,
            reasons: [.goodNightQuality],
            summary: "Fixed"
        )
    }
}

private struct EmptyMoonRecommendationProvider: MoonTargetRecommendationProviding {
    func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation? {
        nil
    }
}

private struct EmptyPlanetRecommendationProvider: PlanetTargetRecommendationProviding {
    func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation? {
        nil
    }
}
