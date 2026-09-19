import AstroEngine
@testable import SharedCode
import XCTest

/// Migration equivalence for the planet recommendation slice.
///
/// `LegacyPlanetRecommendationOracle` and `LegacyPlanetOrbitalElements` are
/// verbatim copies of the pre-migration production math in
/// `PlanetRecommendationService.swift` — the low-precision orbital-element
/// astronomy, best-sample weighting, visibility window, Venus twilight
/// suitability, scoring and reasons. They keep their own literals on purpose:
/// they must not read the new planet calibration file or call any shared engine
/// helper, or a mistake in the extraction could make both sides wrong together.
final class PlanetRecommendationMigrationTests: XCTestCase {
    func testEngineMatchesLegacyImplementationAcrossDecisionBoundaries() {
        var comparisons = 0
        var produced = 0
        var nilAgreements = 0

        for (profileIndex, samples) in Self.sampleProfiles.enumerated() {
            for target in Self.targets {
                for (weatherIndex, weather) in Self.weatherCases.enumerated() {
                    let context = Self.context(
                        hourlyScore: weather.hourlyScore,
                        cloudCoverScore: weather.cloudCoverScore,
                        includeRatings: weather.includeRatings,
                        ratingsStartHour: weather.ratingsStartHour
                    )
                    comparisons += 1
                    _ = profileIndex
                    _ = weatherIndex

                    let provider = DefaultPlanetTargetRecommendationProvider(
                        planetAstronomyProvider: StubPlanetAstronomyProvider(
                            observation: PlanetObservationData(targetID: target.id, samples: samples)
                        )
                    )
                    let actual = provider.recommendation(for: target, context: context)
                    let legacy = LegacyPlanetRecommendationOracle.recommendation(
                        target: target,
                        samples: samples,
                        context: context
                    )

                    guard let actual, let legacy else {
                        XCTAssertEqual(
                            actual == nil, legacy == nil,
                            "nil disagreement for \(target.id) profile \(profileIndex) weather \(weatherIndex)"
                        )
                        nilAgreements += 1
                        continue
                    }
                    produced += 1
                    let label = "\(target.id) profile \(profileIndex) weather \(weatherIndex)"
                    XCTAssertEqual(actual.score, legacy.score, label)
                    XCTAssertEqual(actual.reasons, legacy.reasons, label)
                    XCTAssertEqual(actual.visibilityWindow.start, legacy.window.start, label)
                    XCTAssertEqual(actual.visibilityWindow.end, legacy.window.end, label)
                    XCTAssertEqual(actual.visibilityWindow.bestTime, legacy.window.bestTime, label)
                    XCTAssertEqual(actual.visibilityWindow.maxAltitude, legacy.window.maxAltitude, label)
                    XCTAssertEqual(actual.visibilityWindow.azimuth, legacy.window.azimuth, label)
                    XCTAssertEqual(actual.visibilityWindow.direction, legacy.window.direction, label)
                    XCTAssertEqual(actual.visibilityWindow.id, legacy.window.id, label)
                    XCTAssertEqual(actual.summary, legacy.summary, label)
                }
            }
        }

        XCTAssertEqual(comparisons, Self.sampleProfiles.count * Self.targets.count * Self.weatherCases.count)
        XCTAssertGreaterThan(produced, 200)
        XCTAssertGreaterThan(nilAgreements, 0, "the no-visible-sample branch must be exercised")
    }

    /// The extracted orbital-element astronomy must reproduce the pre-migration
    /// provider bit for bit, including the Schlyter day number, Earth's role in
    /// the geocentric vector and the azimuth normalization.
    func testMigratedAstronomyProviderMatchesLegacyOrbitalElements() {
        var samplesCompared = 0

        for target in Self.targets {
            for context in Self.astronomyContexts {
                let provider = LowPrecisionPlanetAstronomyProvider(sampleInterval: 37 * 60)
                let observation = provider.planetObservation(for: target, context: context)
                let legacy = LegacyPlanetOrbitalElements.observation(
                    targetID: target.id,
                    context: context,
                    sampleInterval: 37 * 60
                )

                XCTAssertEqual(observation?.targetID, legacy?.targetID)
                XCTAssertEqual(observation?.samples.count, legacy?.samples.count)
                guard let observation, let legacy else { continue }
                for (actual, expected) in zip(observation.samples, legacy.samples) {
                    XCTAssertEqual(actual.time, expected.time)
                    XCTAssertEqual(actual.altitude, expected.altitude)
                    XCTAssertEqual(actual.azimuth, expected.azimuth)
                    XCTAssertEqual(actual.solarElongation, expected.solarElongation)
                    samplesCompared += 1
                }
            }
        }

        XCTAssertGreaterThan(samplesCompared, 200)
    }

    func testUnsupportedTargetIDStillYieldsNoObservation() {
        let provider = LowPrecisionPlanetAstronomyProvider()
        let target = ObservableTarget(
            id: "mercury",
            name: "Mercury",
            type: .planet,
            preferredEquipment: .telescope,
            difficulty: 0.8
        )

        XCTAssertNil(provider.planetObservation(for: target, context: Self.astronomyContexts[0]))
        XCTAssertNil(
            LegacyPlanetOrbitalElements.observation(
                targetID: target.id,
                context: Self.astronomyContexts[0],
                sampleInterval: 15 * 60
            )
        )
    }

    func testInvertedNightBeyondLeadAndTrailYieldsNoObservationOnBothPaths() {
        let context = Self.context(
            astronomicalNightStart: Self.date(hour: 20),
            astronomicalNightEnd: Self.date(hour: 20).addingTimeInterval(-3 * 3600)
        )
        let provider = LowPrecisionPlanetAstronomyProvider()

        XCTAssertNil(provider.planetObservation(for: Self.targets[0], context: context))
        XCTAssertNil(
            LegacyPlanetOrbitalElements.observation(
                targetID: Self.targets[0].id,
                context: context,
                sampleInterval: 15 * 60
            )
        )
    }

    func testPlanetCalibrationIsTheOnlySourceOfTheProductionConstants() {
        let calibration = EngineCalibration.current.planetRecommendation

        XCTAssertEqual(calibration.visibility.minimum_altitude_degrees, 8)
        XCTAssertEqual(calibration.visibility.altitude_normalization_degrees, 70)
        XCTAssertEqual(calibration.visibility.window_extension_seconds, 900)
        XCTAssertEqual(calibration.weights.altitude, 45)
        XCTAssertEqual(calibration.weights.weather, 30)
        XCTAssertEqual(calibration.weights.visibility, 12)
        XCTAssertEqual(calibration.weights.convenience, 13)
        XCTAssertEqual(calibration.low_altitude.below_degrees, 15)
        XCTAssertEqual(calibration.low_altitude.penalty, 18)
        XCTAssertEqual(calibration.venus_twilight.eligibility_window_seconds, 2 * 3600)
        XCTAssertEqual(calibration.venus_twilight.useful_duration_seconds, 45 * 60)
        XCTAssertEqual(calibration.venus_twilight.altitude_weight, 0.45)
        XCTAssertEqual(calibration.venus_twilight.duration_weight, 0.30)
        XCTAssertEqual(calibration.venus_twilight.elongation_weight, 0.25)
    }

    // MARK: - Matrix

    private struct WeatherCase {
        let hourlyScore: Double
        let cloudCoverScore: Double
        let includeRatings: Bool
        let ratingsStartHour: Int
    }

    /// Boundary-first, not volume-first. Each profile sits on or immediately
    /// beside a production decision boundary.
    private static let sampleProfiles: [[PlanetPositionSample]] = [
        // Exactly at, and immediately below, the inclusive visible-altitude threshold.
        [sample(hour: 22, altitude: 8, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 7.999_999_999, azimuth: 180, elongation: 45)],
        // Low-altitude penalty boundary.
        [sample(hour: 22, altitude: 15, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 14.999_999_999, azimuth: 180, elongation: 45)],
        // Low/high altitude reason boundaries.
        [sample(hour: 22, altitude: 20, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 19.999_999_999, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 45, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 44.999_999_999, azimuth: 180, elongation: 45)],
        // Altitude normalization / saturation.
        [sample(hour: 22, altitude: 70, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 70.000_000_1, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 89.9, azimuth: 180, elongation: 45)],
        // Score-rounding half boundaries.
        [sample(hour: 22, altitude: 51.333_333_333_333_336, azimuth: 180, elongation: 45)],
        [sample(hour: 22, altitude: 52.888_888_888_888_89, azimuth: 180, elongation: 45)],
        // Best-sample weighted ties: identical weighted scores at two instants.
        [
            sample(hour: 22, altitude: 40, azimuth: 90, elongation: 45),
            sample(hour: 23, altitude: 40, azimuth: 270, elongation: 45),
        ],
        // Weighted selection preferring darkness/convenience over raw altitude.
        [
            sample(hour: 19, altitude: 30, azimuth: 260, elongation: 45),
            sample(hour: 22, altitude: 29, azimuth: 180, elongation: 45),
        ],
        // Interior interpolation on both ends.
        [
            sample(hour: 20, altitude: 6, azimuth: 120, elongation: 30),
            sample(hourMinutes: 20 * 60 + 15, altitude: 10, azimuth: 125, elongation: 30),
            sample(hourMinutes: 20 * 60 + 30, altitude: 12, azimuth: 130, elongation: 30),
            sample(hourMinutes: 20 * 60 + 45, altitude: 4, azimuth: 135, elongation: 30),
        ],
        // Flat crossing inside the interpolation epsilon.
        [
            sample(hour: 20, altitude: 8.000_05, azimuth: 120, elongation: 30),
            sample(hour: 21, altitude: 8.000_1, azimuth: 125, elongation: 30),
            sample(hour: 22, altitude: 8.000_15, azimuth: 130, elongation: 30),
        ],
        // Final-sample fallback extension: the run ends on the last sample.
        [
            sample(hour: 27, altitude: 20, azimuth: 100, elongation: 60),
            sample(hour: 28, altitude: 31, azimuth: 120, elongation: 60),
        ],
        // Darkness-overlap boundary around 0.45 of the window.
        [
            sample(hour: 18, altitude: 25, azimuth: 265, elongation: 40),
            sample(hour: 19, altitude: 20, azimuth: 275, elongation: 40),
            sample(hour: 20, altitude: 15, azimuth: 285, elongation: 40),
            sample(hour: 21, altitude: 5, azimuth: 295, elongation: 40),
        ],
        // Convenience boundaries: evening band, late-night band and neither.
        [sample(hour: 18, altitude: 30, azimuth: 265, elongation: 44)],
        [sample(hour: 24, altitude: 30, azimuth: 180, elongation: 44)],
        [sample(hour: 25, altitude: 30, azimuth: 180, elongation: 44)],
        [sample(hour: 26, altitude: 30, azimuth: 180, elongation: 44)],
        [sample(hour: 28, altitude: 30, azimuth: 120, elongation: 44)],
        // Venus evening twilight eligibility, on and off the two-hour bound.
        [
            sample(hour: 18, altitude: 22, azimuth: 260, elongation: 46),
            sample(hour: 19, altitude: 12, azimuth: 270, elongation: 46),
            sample(hour: 20, altitude: 7.9, azimuth: 280, elongation: 46),
        ],
        [
            sample(hour: 15, altitude: 22, azimuth: 250, elongation: 46),
            sample(hour: 16, altitude: 12, azimuth: 255, elongation: 46),
            sample(hour: 17, altitude: -2, azimuth: 260, elongation: 46),
        ],
        // Venus morning twilight.
        [
            sample(hour: 28, altitude: 9, azimuth: 90, elongation: 46),
            sample(hour: 29, altitude: 24, azimuth: 100, elongation: 46),
            sample(hour: 30, altitude: 33, azimuth: 110, elongation: 46),
        ],
        // Venus useful-duration saturation: exactly 45 minutes of window.
        [
            sample(hourMinutes: 18 * 60, altitude: 30, azimuth: 265, elongation: 46),
            sample(hourMinutes: 18 * 60 + 30, altitude: 30, azimuth: 268, elongation: 46),
        ],
        // Venus elongation term boundaries: 15 (zero), 45 (saturated) and either side.
        [sample(hour: 18, altitude: 20, azimuth: 265, elongation: 15)],
        [sample(hour: 18, altitude: 20, azimuth: 265, elongation: 15.000_001)],
        [sample(hour: 18, altitude: 20, azimuth: 265, elongation: 45)],
        [sample(hour: 18, altitude: 20, azimuth: 265, elongation: 44.999_999)],
        [sample(hour: 18, altitude: 20, azimuth: 265, elongation: nil)],
        // Venus altitude term boundary: exactly 12 degrees above the threshold.
        [sample(hour: 18, altitude: 20, azimuth: 265, elongation: 46)],
        [sample(hour: 18, altitude: 20.000_001, azimuth: 265, elongation: 46)],
        // Compass boundaries.
        [sample(hour: 22, altitude: 30, azimuth: 11.25, elongation: 44)],
        [sample(hour: 22, altitude: 30, azimuth: 11.249_999, elongation: 44)],
        [sample(hour: 22, altitude: 30, azimuth: 348.75, elongation: 44)],
        [sample(hour: 22, altitude: 30, azimuth: 359.999, elongation: 44)],
        [sample(hour: 22, altitude: 30, azimuth: 0, elongation: 44)],
        [sample(hour: 22, altitude: 30, azimuth: 360, elongation: 44)],
        // No visible sample at all.
        [
            sample(hour: 20, altitude: -12, azimuth: 90, elongation: 20),
            sample(hour: 22, altitude: 2, azimuth: 100, elongation: 20),
            sample(hour: 26, altitude: 7.999, azimuth: 110, elongation: 20),
        ],
        // Empty observation.
        [],
        // A long, ordinary run spanning the whole night.
        (0..<13).map { index in
            sample(
                hourMinutes: 18 * 60 + index * 60,
                altitude: [2, 9, 18, 27, 36, 45, 54, 63, 58, 44, 31, 17, 6][index],
                azimuth: Double(index) * 27,
                elongation: 25 + Double(index)
            )
        },
    ]

    /// Hourly-rating overlap boundaries plus the no-overlap cloud-cover fallback.
    private static let weatherCases: [WeatherCase] = [
        WeatherCase(hourlyScore: 0.2, cloudCoverScore: 5, includeRatings: true, ratingsStartHour: 18),
        WeatherCase(hourlyScore: 0.6, cloudCoverScore: 30, includeRatings: true, ratingsStartHour: 18),
        WeatherCase(hourlyScore: 1.1, cloudCoverScore: 55, includeRatings: true, ratingsStartHour: 18),
        WeatherCase(hourlyScore: 1.8, cloudCoverScore: 90, includeRatings: true, ratingsStartHour: 18),
        WeatherCase(hourlyScore: 0.2, cloudCoverScore: 0, includeRatings: false, ratingsStartHour: 18),
        WeatherCase(hourlyScore: 0.2, cloudCoverScore: 55, includeRatings: false, ratingsStartHour: 18),
        WeatherCase(hourlyScore: 0.2, cloudCoverScore: 100, includeRatings: false, ratingsStartHour: 18),
        // Ratings that start well after the night so most windows see no overlap.
        WeatherCase(hourlyScore: 1.6, cloudCoverScore: 20, includeRatings: true, ratingsStartHour: 27),
    ]

    private static let targets: [ObservableTarget] = [
        ObservableTarget(id: "venus", name: "Venus", type: .planet, preferredEquipment: .nakedEye, difficulty: 0.1),
        ObservableTarget(id: "mars", name: "Mars", type: .planet, preferredEquipment: .nakedEye, difficulty: 0.2),
        ObservableTarget(id: "jupiter", name: "Jupiter", type: .planet, preferredEquipment: .smallTelescope, difficulty: 0.25),
        ObservableTarget(id: "saturn", name: "Saturn", type: .planet, preferredEquipment: .smallTelescope, difficulty: 0.35),
    ]

    private static let astronomyContexts: [TargetRecommendationContext] = [
        context(
            location: CachedLocation(name: "Cupertino", latitude: 37.323, longitude: -122.032, elevation: 72),
            astronomicalNightStart: date(year: 2026, month: 6, day: 30, hour: 3, minute: 26),
            astronomicalNightEnd: date(year: 2026, month: 6, day: 30, hour: 11, minute: 26)
        ),
        context(
            location: CachedLocation(name: "El Segundo", latitude: 33.8078, longitude: -118.3183, elevation: 0),
            astronomicalNightStart: date(year: 2026, month: 7, day: 18, hour: 4, minute: 43, second: 38),
            astronomicalNightEnd: date(year: 2026, month: 7, day: 18, hour: 11, minute: 16, second: 6)
        ),
        context(
            location: CachedLocation(name: "Longyearbyen", latitude: 78.22, longitude: 15.65, elevation: 0),
            astronomicalNightStart: date(year: 2027, month: 12, day: 21, hour: 0, minute: 0),
            astronomicalNightEnd: date(year: 2027, month: 12, day: 21, hour: 9, minute: 30)
        ),
        context(
            location: CachedLocation(name: "Quito", latitude: -0.18, longitude: -78.47, elevation: 0),
            astronomicalNightStart: date(year: 2049, month: 12, day: 29, hour: 1, minute: 5),
            astronomicalNightEnd: date(year: 2049, month: 12, day: 29, hour: 10, minute: 40)
        ),
        context(
            location: CachedLocation(name: "Antipode", latitude: -33.87, longitude: 151.21, elevation: 0),
            astronomicalNightStart: date(year: 2000, month: 1, day: 2, hour: 11, minute: 0),
            astronomicalNightEnd: date(year: 2000, month: 1, day: 2, hour: 18, minute: 40)
        ),
    ]

    private static func sample(
        hour: Int,
        altitude: Double,
        azimuth: Double,
        elongation: Double?
    ) -> PlanetPositionSample {
        sample(hourMinutes: hour * 60, altitude: altitude, azimuth: azimuth, elongation: elongation)
    }

    private static func sample(
        hourMinutes: Int,
        altitude: Double,
        azimuth: Double,
        elongation: Double?
    ) -> PlanetPositionSample {
        PlanetPositionSample(
            time: date(hour: 0).addingTimeInterval(Double(hourMinutes) * 60),
            altitude: altitude,
            azimuth: azimuth,
            solarElongation: elongation
        )
    }

    private static func context(
        location: CachedLocation = CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
        astronomicalNightStart: Date = date(hour: 20),
        astronomicalNightEnd: Date = date(hour: 29),
        hourlyScore: Double = 0.2,
        cloudCoverScore: Double = 5,
        includeRatings: Bool = true,
        ratingsStartHour: Int = 18
    ) -> TargetRecommendationContext {
        TargetRecommendationContext(
            location: location,
            astronomicalNightStart: astronomicalNightStart,
            astronomicalNightEnd: astronomicalNightEnd,
            nightQuality: NightQualityAssessment(
                rating: NightQualityAssessment.Rating.from(score: hourlyScore),
                summary: "Test",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: cloudCoverScore,
                    fogScoreAvg: 5,
                    moonIlluminationAvg: 20,
                    windSpeedAvg: 2
                ),
                bestWindow: NightQualityAssessment.TimeWindow(
                    start: astronomicalNightStart,
                    end: astronomicalNightEnd
                ),
                hourlyRatings: includeRatings ? (0..<12).map { offset in
                    NightQualityAssessment.HourlyRating(
                        time: date(hour: ratingsStartHour).addingTimeInterval(Double(offset) * 3600),
                        score: hourlyScore,
                        cloudCover: Int(cloudCoverScore),
                        fogScore: 5,
                        moonIllumination: 20,
                        moonAltitude: -5,
                        windSpeed: 2
                    )
                } : [],
                nightStart: astronomicalNightStart,
                nightEnd: astronomicalNightEnd
            ),
            moonInfo: MoonInfo(
                phase: 0.2,
                phaseName: "Test Moon",
                altitude: -5,
                illumination: 20,
                emoji: ""
            )
        )
    }

    private static func date(hour: Int) -> Date {
        date(year: 2026, month: 3, day: 1 + hour / 24, hour: hour % 24)
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

private struct StubPlanetAstronomyProvider: PlanetAstronomyProviding {
    let observation: PlanetObservationData

    func planetObservation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> PlanetObservationData? {
        observation
    }
}

/// Verbatim pre-migration production scoring. Do not "improve" it, do not route
/// it through the shared engine, and do not let it read the planet calibration
/// file: its only job is to be the old behavior.
private enum LegacyPlanetRecommendationOracle {
    struct Outcome {
        let score: Int
        let window: TargetVisibilityWindow
        let reasons: [TargetRecommendationReason]
        let summary: String
    }

    private static let minimumVisibleAltitude = 8.0
    private static let planetAltitudeNormalizationDegrees = 70.0
    private static let venusTwilightEligibilityWindow: TimeInterval = 2 * 3600
    private static let venusTwilightUsefulDuration: TimeInterval = 45 * 60
    private static let venusTwilightAltitudeWeight = 0.45
    private static let venusTwilightDurationWeight = 0.30
    private static let venusTwilightElongationWeight = 0.25

    static func recommendation(
        target: ObservableTarget,
        samples: [PlanetPositionSample],
        context: TargetRecommendationContext
    ) -> Outcome? {
        guard target.type == .planet else { return nil }

        let visibleSamples = samples.filter { $0.altitude >= minimumVisibleAltitude }
        guard !visibleSamples.isEmpty,
              let bestSample = bestSample(from: visibleSamples, context: context) else {
            return nil
        }

        let window = visibilityWindow(
            from: samples,
            visibleSamples: visibleSamples,
            bestSample: bestSample
        )
        let weatherQuality = weatherQuality(in: window, context: context)
        let darknessOverlap = overlapFraction(
            windowStart: window.start,
            windowEnd: window.end,
            darknessStart: context.astronomicalNightStart,
            darknessEnd: context.astronomicalNightEnd
        )
        let convenience = convenienceScore(for: bestSample.time, context: context)
        let visibilityQuality = visibilityQuality(
            for: target,
            bestSample: bestSample,
            window: window,
            darknessOverlap: darknessOverlap,
            context: context
        )
        return Outcome(
            score: score(
                altitude: bestSample.altitude,
                weatherQuality: weatherQuality,
                visibilityQuality: visibilityQuality,
                convenience: convenience
            ),
            window: window,
            reasons: reasons(
                bestSample: bestSample,
                weatherQuality: weatherQuality,
                darknessOverlap: darknessOverlap,
                convenience: convenience
            ),
            summary: summary(bestSample: bestSample, window: window, context: context)
        )
    }

    private static func bestSample(
        from samples: [PlanetPositionSample],
        context: TargetRecommendationContext
    ) -> PlanetPositionSample? {
        samples.max { lhs, rhs in
            weightedScore(for: lhs, context: context) < weightedScore(for: rhs, context: context)
        }
    }

    private static func weightedScore(
        for sample: PlanetPositionSample,
        context: TargetRecommendationContext
    ) -> Double {
        let altitude = min(max(sample.altitude / planetAltitudeNormalizationDegrees, 0), 1)
        let darkness = sample.time >= context.astronomicalNightStart
            && sample.time <= context.astronomicalNightEnd ? 1.0 : 0.55
        let convenience = convenienceScore(for: sample.time, context: context)
        return altitude * 0.70 + darkness * 0.15 + convenience * 0.15
    }

    private static func visibilityWindow(
        from samples: [PlanetPositionSample],
        visibleSamples: [PlanetPositionSample],
        bestSample: PlanetPositionSample
    ) -> TargetVisibilityWindow {
        let firstVisible = visibleSamples.first
        let lastVisible = visibleSamples.last
        let firstVisibleIndex = firstVisible.flatMap { sample in
            samples.firstIndex(where: { $0.time == sample.time })
        }
        let lastVisibleIndex = lastVisible.flatMap { sample in
            samples.lastIndex(where: { $0.time == sample.time })
        }

        let start: Date
        if let firstVisible, let firstVisibleIndex, firstVisibleIndex > samples.startIndex {
            start = thresholdCrossing(between: samples[firstVisibleIndex - 1], and: firstVisible)
        } else {
            start = firstVisible?.time ?? bestSample.time
        }

        let end: Date
        if let lastVisible, let lastVisibleIndex, lastVisibleIndex < samples.index(before: samples.endIndex) {
            end = thresholdCrossing(between: lastVisible, and: samples[lastVisibleIndex + 1])
        } else {
            end = lastVisible?.time.addingTimeInterval(15 * 60)
                ?? bestSample.time.addingTimeInterval(15 * 60)
        }

        return TargetVisibilityWindow(
            start: start,
            end: end,
            bestTime: bestSample.time,
            maxAltitude: bestSample.altitude,
            direction: compassDirection(for: bestSample.azimuth).uppercased(),
            azimuth: bestSample.azimuth
        )
    }

    private static func thresholdCrossing(
        between first: PlanetPositionSample,
        and second: PlanetPositionSample
    ) -> Date {
        let altitudeChange = second.altitude - first.altitude
        guard abs(altitudeChange) > 0.0001 else { return first.time }
        let fraction = min(
            max((minimumVisibleAltitude - first.altitude) / altitudeChange, 0),
            1
        )
        return first.time.addingTimeInterval(second.time.timeIntervalSince(first.time) * fraction)
    }

    private static func score(
        altitude: Double,
        weatherQuality: Double,
        visibilityQuality: Double,
        convenience: Double
    ) -> Int {
        let altitudeQuality = min(max(altitude / planetAltitudeNormalizationDegrees, 0), 1)
        let lowAltitudePenalty = altitude < 15 ? 18.0 : 0
        let rawScore = altitudeQuality * 45
            + weatherQuality * 30
            + visibilityQuality * 12
            + convenience * 13
            - lowAltitudePenalty
        return Int(round(min(max(rawScore, 0), 100)))
    }

    private static func visibilityQuality(
        for target: ObservableTarget,
        bestSample: PlanetPositionSample,
        window: TargetVisibilityWindow,
        darknessOverlap: Double,
        context: TargetRecommendationContext
    ) -> Double {
        guard target.id.lowercased() == "venus" else {
            return darknessOverlap
        }

        return max(
            darknessOverlap,
            venusTwilightSuitability(
                bestSample: bestSample,
                window: window,
                context: context
            )
        )
    }

    private static func venusTwilightSuitability(
        bestSample: PlanetPositionSample,
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> Double {
        let isEveningTwilight = bestSample.time < context.astronomicalNightStart
            && window.end > context.astronomicalNightStart.addingTimeInterval(-venusTwilightEligibilityWindow)
        let isMorningTwilight = bestSample.time > context.astronomicalNightEnd
            && window.start < context.astronomicalNightEnd.addingTimeInterval(venusTwilightEligibilityWindow)
        guard isEveningTwilight || isMorningTwilight else { return 0 }

        let altitudeQuality = min(max((bestSample.altitude - minimumVisibleAltitude) / 12, 0), 1)
        let durationQuality = min(max(window.duration / venusTwilightUsefulDuration, 0), 1)
        let elongationQuality = min(max(((bestSample.solarElongation ?? 0) - 15) / 30, 0), 1)

        return altitudeQuality * venusTwilightAltitudeWeight
            + durationQuality * venusTwilightDurationWeight
            + elongationQuality * venusTwilightElongationWeight
    }

    private static func reasons(
        bestSample: PlanetPositionSample,
        weatherQuality: Double,
        darknessOverlap: Double,
        convenience: Double
    ) -> [TargetRecommendationReason] {
        var reasons: [TargetRecommendationReason] = []

        if bestSample.altitude >= 45 {
            reasons.append(.highAltitude)
        } else if bestSample.altitude < 20 {
            reasons.append(.lowAltitude)
        }

        if darknessOverlap >= 0.45 {
            reasons.append(.astronomicalDarkness)
        }

        if convenience >= 0.72 {
            reasons.append(.convenientPlanetWindow)
        } else if convenience <= 0.35 {
            reasons.append(.lateOrEarlyPlanetWindow)
        }

        if weatherQuality >= 0.7 {
            reasons.append(.goodNightQuality)
        } else if weatherQuality < 0.45 {
            reasons.append(.poorWeather)
        }

        reasons.append(.planetMoonlightResistant)
        return reasons
    }

    private static func summary(
        bestSample: PlanetPositionSample,
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> String {
        let direction = compassDirection(for: bestSample.azimuth).uppercased()
        let altitude = Int(round(bestSample.altitude))

        if context.hasPoorTargetRecommendationConditions(in: window) {
            if bestSample.time < context.astronomicalNightStart {
                return "Well placed after sunset, but clouds may block the view."
            }

            if bestSample.time > context.astronomicalNightEnd.addingTimeInterval(-2 * 3600) {
                return "Well placed before dawn, but clouds may block the view."
            }

            return "Well placed tonight, but clouds may block the view."
        }

        if bestSample.time < context.astronomicalNightStart {
            if bestSample.altitude < 20 {
                return "Low in the \(direction) shortly after sunset; horizon obstructions may matter."
            }
            return "Look \(direction), about \(altitude)° high shortly after sunset."
        }

        if bestSample.time > context.astronomicalNightEnd.addingTimeInterval(-2 * 3600) {
            if bestSample.altitude < 20 {
                return "Visible before dawn, but low altitude limits the view."
            }
            if bestSample.altitude < 35 {
                return "Best before dawn; only moderately high."
            }
            return "Visible before dawn in the \(direction), about \(altitude)° high."
        }

        return "Highest around \(timeFormatter.string(from: bestSample.time)), facing \(direction)."
    }

    private static func convenienceScore(
        for time: Date,
        context: TargetRecommendationContext
    ) -> Double {
        let eveningStart = context.astronomicalNightStart.addingTimeInterval(-2 * 3600)
        let eveningEnd = context.astronomicalNightStart.addingTimeInterval(4 * 3600)
        if time >= eveningStart && time <= eveningEnd {
            return 1
        }

        let lateNightStart = context.astronomicalNightEnd.addingTimeInterval(-3 * 3600)
        if time >= lateNightStart {
            return 0.35
        }

        return 0.65
    }

    private static func weatherQuality(
        in window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> Double {
        let overlappingRatings = context.nightQuality.hourlyRatings.filter { rating in
            let ratingEnd = rating.time.addingTimeInterval(3600)
            return ratingEnd > window.start && rating.time < window.end
        }

        guard !overlappingRatings.isEmpty else {
            return 1 - min(max(context.nightQuality.details.cloudCoverScore / 100, 0), 1)
        }

        let averageScore = overlappingRatings.map(\.score).reduce(0, +) / Double(overlappingRatings.count)
        return 1 - min(max(averageScore / 2, 0), 1)
    }

    private static func overlapFraction(
        windowStart: Date,
        windowEnd: Date,
        darknessStart: Date,
        darknessEnd: Date
    ) -> Double {
        guard windowEnd > windowStart else { return 0 }

        let overlapStart = max(windowStart, darknessStart)
        let overlapEnd = min(windowEnd, darknessEnd)
        guard overlapEnd > overlapStart else { return 0 }

        return overlapEnd.timeIntervalSince(overlapStart) / windowEnd.timeIntervalSince(windowStart)
    }

    private static func compassDirection(for azimuth: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        ]
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % directions.count
        return directions[index]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Verbatim pre-migration production low-precision astronomy.
private enum LegacyPlanetOrbitalElements {
    enum Planet: String {
        case earth
        case venus
        case mars
        case jupiter
        case saturn
    }

    struct Elements {
        let longitudeOfAscendingNode: Double
        let inclination: Double
        let argumentOfPerihelion: Double
        let semiMajorAxis: Double
        let eccentricity: Double
        let meanAnomaly: Double
    }

    static func observation(
        targetID: String,
        context: TargetRecommendationContext,
        sampleInterval: TimeInterval
    ) -> PlanetObservationData? {
        guard let planet = Planet(rawValue: targetID.lowercased()) else { return nil }

        let start = context.astronomicalNightStart.addingTimeInterval(-2 * 3600)
        let end = context.astronomicalNightEnd.addingTimeInterval(60 * 60)
        guard end > start else { return nil }

        var samples: [PlanetPositionSample] = []
        var time = start
        while time <= end {
            samples.append(position(
                for: planet,
                at: time,
                latitude: context.location.latitude,
                longitude: context.location.longitude
            ))
            time = time.addingTimeInterval(sampleInterval)
        }
        return PlanetObservationData(targetID: targetID, samples: samples)
    }

    private static func position(
        for planet: Planet,
        at date: Date,
        latitude: Double,
        longitude: Double
    ) -> PlanetPositionSample {
        let jd = julianDate(from: date)
        let d = jd - 2_451_543.5
        let sunGeocentric = heliocentricCoordinates(elements(for: .earth, schlyterDayNumber: d))
        let planetCoordinates = heliocentricCoordinates(elements(for: planet, schlyterDayNumber: d))

        let x = planetCoordinates.x + sunGeocentric.x
        let y = planetCoordinates.y + sunGeocentric.y
        let z = planetCoordinates.z + sunGeocentric.z
        let obliquity = radians(23.4393 - 3.563e-7 * d)

        let equatorialX = x
        let equatorialY = y * cos(obliquity) - z * sin(obliquity)
        let equatorialZ = y * sin(obliquity) + z * cos(obliquity)
        let rightAscension = atan2(equatorialY, equatorialX)
        let declination = atan2(equatorialZ, sqrt(equatorialX * equatorialX + equatorialY * equatorialY))

        let localSiderealTime = radians(normalizedDegrees(
            280.460_618_37 + 360.985_647_366_29 * (jd - 2_451_545.0) + longitude
        ))
        let hourAngle = normalizedRadians(localSiderealTime - rightAscension)
        let latitudeRadians = radians(latitude)

        let altitude = asin(
            sin(declination) * sin(latitudeRadians)
            + cos(declination) * cos(latitudeRadians) * cos(hourAngle)
        )
        let azimuth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitudeRadians) - tan(declination) * cos(latitudeRadians)
        )

        return PlanetPositionSample(
            time: date,
            altitude: degrees(altitude),
            azimuth: normalizedDegrees(degrees(azimuth) + 180),
            solarElongation: angularSeparation(first: (x, y, z), second: sunGeocentric)
        )
    }

    private static func angularSeparation(
        first: (x: Double, y: Double, z: Double),
        second: (x: Double, y: Double, z: Double)
    ) -> Double {
        let dotProduct = first.x * second.x + first.y * second.y + first.z * second.z
        let firstMagnitude = sqrt(first.x * first.x + first.y * first.y + first.z * first.z)
        let secondMagnitude = sqrt(second.x * second.x + second.y * second.y + second.z * second.z)
        guard firstMagnitude > 0, secondMagnitude > 0 else { return 0 }

        let cosine = min(max(dotProduct / (firstMagnitude * secondMagnitude), -1), 1)
        return degrees(acos(cosine))
    }

    private static func elements(for planet: Planet, schlyterDayNumber d: Double) -> Elements {
        switch planet {
        case .earth:
            return Elements(
                longitudeOfAscendingNode: 0,
                inclination: 0,
                argumentOfPerihelion: 282.9404 + 4.70935e-5 * d,
                semiMajorAxis: 1,
                eccentricity: 0.016709 - 1.151e-9 * d,
                meanAnomaly: 356.0470 + 0.9856002585 * d
            )
        case .venus:
            return Elements(
                longitudeOfAscendingNode: 76.6799 + 2.46590e-5 * d,
                inclination: 3.3946 + 2.75e-8 * d,
                argumentOfPerihelion: 54.8910 + 1.38374e-5 * d,
                semiMajorAxis: 0.723330,
                eccentricity: 0.006773 - 1.302e-9 * d,
                meanAnomaly: 48.0052 + 1.6021302244 * d
            )
        case .mars:
            return Elements(
                longitudeOfAscendingNode: 49.5574 + 2.11081e-5 * d,
                inclination: 1.8497 - 1.78e-8 * d,
                argumentOfPerihelion: 286.5016 + 2.92961e-5 * d,
                semiMajorAxis: 1.523688,
                eccentricity: 0.093405 + 2.516e-9 * d,
                meanAnomaly: 18.6021 + 0.5240207766 * d
            )
        case .jupiter:
            return Elements(
                longitudeOfAscendingNode: 100.4542 + 2.76854e-5 * d,
                inclination: 1.3030 - 1.557e-7 * d,
                argumentOfPerihelion: 273.8777 + 1.64505e-5 * d,
                semiMajorAxis: 5.20256,
                eccentricity: 0.048498 + 4.469e-9 * d,
                meanAnomaly: 19.8950 + 0.0830853001 * d
            )
        case .saturn:
            return Elements(
                longitudeOfAscendingNode: 113.6634 + 2.38980e-5 * d,
                inclination: 2.4886 - 1.081e-7 * d,
                argumentOfPerihelion: 339.3939 + 2.97661e-5 * d,
                semiMajorAxis: 9.55475,
                eccentricity: 0.055546 - 9.499e-9 * d,
                meanAnomaly: 316.9670 + 0.0334442282 * d
            )
        }
    }

    private static func heliocentricCoordinates(_ elements: Elements) -> (x: Double, y: Double, z: Double) {
        let meanAnomalyRadians = radians(normalizedDegrees(elements.meanAnomaly))
        let eccentricity = elements.eccentricity
        let eccentricAnomaly = meanAnomalyRadians
            + eccentricity * sin(meanAnomalyRadians) * (1 + eccentricity * cos(meanAnomalyRadians))

        let xv = elements.semiMajorAxis * (cos(eccentricAnomaly) - eccentricity)
        let yv = elements.semiMajorAxis * sqrt(1 - eccentricity * eccentricity) * sin(eccentricAnomaly)
        let trueAnomaly = atan2(yv, xv)
        let radius = sqrt(xv * xv + yv * yv)

        let node = radians(elements.longitudeOfAscendingNode)
        let inclinationRadians = radians(elements.inclination)
        let argument = trueAnomaly + radians(elements.argumentOfPerihelion)

        let x = radius * (cos(node) * cos(argument) - sin(node) * sin(argument) * cos(inclinationRadians))
        let y = radius * (sin(node) * cos(argument) + cos(node) * sin(argument) * cos(inclinationRadians))
        let z = radius * sin(argument) * sin(inclinationRadians)

        return (x, y, z)
    }

    private static func julianDate(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    private static func normalizedRadians(_ radians: Double) -> Double {
        let twoPi = 2 * Double.pi
        return (radians.truncatingRemainder(dividingBy: twoPi) + twoPi)
            .truncatingRemainder(dividingBy: twoPi)
    }
}
