import AstroEngine
@testable import SharedCode
import XCTest

/// Migration equivalence for the lunar recommendation slice.
///
/// `LegacyMoonRecommendationOracle` is a verbatim copy of the pre-migration
/// private math in `DefaultMoonTargetRecommendationProvider` (useful-window
/// selection, visibility window, scoring, phase quality, reasons, visible
/// fraction, weather quality, sixteen-point compass). It exists only to prove
/// that `AstroEngine.MoonRecommendation` reproduces the old production behavior
/// exactly across a broad sweep of observations and contexts.
final class MoonRecommendationMigrationTests: XCTestCase {
    func testEngineMatchesLegacyImplementationAcrossBroadInputs() {
        let phases: [Double] = [0, 0.02, 0.04, 0.12, 0.25, 0.33, 0.5, 0.62, 0.75, 0.9, 0.96, 1]
        let illuminations = [0, 8, 9, 30, 45, 46, 60, 89, 90, 100]
        let altitudeProfiles: [[Double]] = [
            [18, 35, 48, 30, 12, 4, -2, -9],
            [-18, -12, -8, -4, -1, 0, 3, 9],
            [-20, -15, -11, -6, -3, -2, -1, -0.5],
            [0, 0, 0, 0, 0, 0, 0, 0],
            [40, 40, 12, 6, 3, 1, 0.5, 0.25],
            [5, -1, 7, -2, 9, -3, 11, -4],
        ]
        let bestWindows: [(start: Int, end: Int)?] = [
            nil, (21, 25), (20, 29), (22, 23), (26, 40), (24, 24),
        ]
        let hourlyScores: [Double] = [0, 0.2, 0.9, 1.6, 2]
        let cloudCovers: [Double] = [0, 55, 80, 100]

        var comparisons = 0
        var produced = 0
        for (profileIndex, altitudes) in altitudeProfiles.enumerated() {
            for bestWindow in bestWindows {
                for hourlyScore in hourlyScores {
                    // Rotate the remaining axes so the sweep stays bounded while
                    // every phase, illumination and cloud value is exercised.
                    let phase = phases[comparisons % phases.count]
                    let illumination = illuminations[comparisons % illuminations.count]
                    let cloudCover = cloudCovers[comparisons % cloudCovers.count]
                    let hasRatings = comparisons % 3 != 0
                    let observation = Self.observation(
                        phase: phase,
                        illumination: illumination,
                        altitudes: altitudes,
                        azimuthOffset: Double(profileIndex) * 37,
                        alwaysDown: altitudes.allSatisfy { $0 <= 0 },
                        set: comparisons % 4 == 0 ? nil : Self.date(hour: 22 + comparisons % 6)
                    )
                    let context = Self.context(
                        bestWindow: bestWindow.map {
                            .init(start: Self.date(hour: $0.start), end: Self.date(hour: $0.end))
                        },
                        hourlyScore: hourlyScore,
                        cloudCoverScore: cloudCover,
                        includeRatings: hasRatings
                    )
                    comparisons += 1

                    let provider = DefaultMoonTargetRecommendationProvider(
                        moonAstronomyProvider: StubMoonAstronomyProvider(observation: observation)
                    )
                    let actual = provider.recommendation(for: Self.moonTarget, context: context)
                    let legacy = LegacyMoonRecommendationOracle.recommendation(
                        observation: observation, context: context
                    )

                    guard let actual, let legacy else {
                        XCTAssertEqual(
                            actual == nil, legacy == nil,
                            "nil disagreement for phase \(phase) illumination \(illumination)"
                        )
                        continue
                    }
                    produced += 1
                    XCTAssertEqual(actual.score, legacy.score)
                    XCTAssertEqual(actual.reasons, legacy.reasons)
                    XCTAssertEqual(actual.visibilityWindow.start, legacy.window.start)
                    XCTAssertEqual(actual.visibilityWindow.end, legacy.window.end)
                    XCTAssertEqual(actual.visibilityWindow.bestTime, legacy.window.bestTime)
                    XCTAssertEqual(actual.visibilityWindow.maxAltitude, legacy.window.maxAltitude)
                    XCTAssertEqual(actual.visibilityWindow.azimuth, legacy.window.azimuth)
                    XCTAssertEqual(actual.visibilityWindow.direction, legacy.window.direction)
                    XCTAssertEqual(actual.visibilityWindow.id, legacy.window.id)
                    XCTAssertEqual(actual.id, "moon-\(legacy.window.id)")
                }
            }
        }
        XCTAssertEqual(comparisons, 6 * 6 * 5)
        XCTAssertGreaterThan(produced, 60)
        print("[moon migration] compared \(comparisons) provider invocations, \(produced) with a recommendation")
    }

    /// Cartesian axes prevent the rotated sweep from hiding interactions between
    /// phase branches, illumination caps, poor weather and alwaysDown.
    func testIndependentPhaseIlluminationWeatherBoundaryMatrix() {
        let phases: [Double] = [0, (0.04).nextDown, 0.04, (0.04).nextUp,
            (0.17).nextDown, 0.17, (0.17).nextUp, 0.25,
            (0.33).nextDown, 0.33, (0.33).nextUp, 0.5,
            (0.67).nextDown, 0.67, (0.67).nextUp, 0.75,
            (0.83).nextDown, 0.83, (0.83).nextUp,
            (0.96).nextDown, 0.96, (0.96).nextUp, 1]
        let illuminations = [0, 8, 9, 39, 40, 44, 45, 46, 89, 90, 100]
        var comparisons = 0
        for phase in phases {
            for illumination in illuminations {
                for cloud in [0.0, (55.0).nextDown, 55.0, 100.0] {
                    for alwaysDown in [false, true] {
                        let observation = Self.observation(
                            phase: phase, illumination: illumination,
                            altitudes: [0, 10, 10, -1], azimuthOffset: 0,
                            alwaysDown: alwaysDown, set: Self.date(hour: 22))
                        assertMatchesLegacy(observation, Self.context(
                            bestWindow: nil, hourlyScore: 0, cloudCoverScore: cloud,
                            includeRatings: false))
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 2024)
        print("[moon migration] independent boundary matrix: \(comparisons) recommendations")
    }

    func testVisibilityDirectionAndSetBoundariesAgainstLegacy() {
        var comparisons = 0
        for altitudes in [[0.0, 0, 0, 0], [-1, 1, -1, -1], [-1, 1, -1, -1, -1],
                          [10, 10, -1], [1], [0, 0, 0, 10]] {
            for set in [Self.date(hour: 20), Self.date(hour: 20).addingTimeInterval(1),
                        Self.date(hour: 27).addingTimeInterval(-1), Self.date(hour: 27)] {
                for azimuth in [(11.25).nextDown, 11.25, (11.25).nextUp, 348.75, -90, 720] {
                    assertMatchesLegacy(Self.observation(
                        phase: 0.5, illumination: 40, altitudes: altitudes,
                        azimuthOffset: azimuth, alwaysDown: true, set: set),
                        Self.context(bestWindow: nil, hourlyScore: 0.2,
                                     cloudCoverScore: 0, includeRatings: true))
                    comparisons += 1
                }
            }
        }
        // The fourth sample is the highest and has nil azimuth in the stub.
        assertMatchesLegacy(Self.observation(phase: 0.5, illumination: 60,
            altitudes: [1, 2, 3, 10], azimuthOffset: 0, alwaysDown: false, set: nil),
            Self.context(bestWindow: .init(start: Self.date(hour: 22), end: Self.date(hour: 23)),
                         hourlyScore: 1.1, cloudCoverScore: 100, includeRatings: true))
        XCTAssertEqual(comparisons, 144)
    }

    func testRatingOverlapAndUsefulWindowBoundariesAgainstLegacy() {
        let observation = Self.observation(phase: 0.5, illumination: 60,
            altitudes: [0, 10, 10, -1], azimuthOffset: 0, alwaysDown: false, set: nil)
        // Visibility is 21:30...22:30: each exact-touching rating is excluded.
        var comparisons = 0
        for offset in [-1.0, 0, 1] {
            for hour in [20, 22] {
                for score in [-1.0, 0, (1.1).nextDown, 1.1, (1.1).nextUp, 2, 3] {
                    let rating = NightQualityAssessment.HourlyRating(
                        time: Self.date(hour: hour).addingTimeInterval(1800 + offset),
                        score: score, cloudCover: 0, fogScore: 0,
                        moonIllumination: 60, moonAltitude: 10, windSpeed: 0)
                    assertMatchesLegacy(observation, Self.context(
                        bestWindow: nil, hourlyScore: 0, cloudCoverScore: 100,
                        includeRatings: false, ratingRows: [rating]))
                    comparisons += 1
                }
            }
        }
        for window in [(21, 21), (22, 21), (19, 30), (22, 22)] {
            assertMatchesLegacy(observation, Self.context(
                bestWindow: .init(start: Self.date(hour: window.0), end: Self.date(hour: window.1)),
                hourlyScore: 0, cloudCoverScore: 0, includeRatings: false))
            comparisons += 1
        }
        XCTAssertEqual(comparisons, 46)
    }

    private func assertMatchesLegacy(_ observation: MoonObservationData,
                                     _ context: TargetRecommendationContext,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let actual = DefaultMoonTargetRecommendationProvider(
            moonAstronomyProvider: StubMoonAstronomyProvider(observation: observation))
            .recommendation(for: Self.moonTarget, context: context)
        let expected = LegacyMoonRecommendationOracle.recommendation(observation: observation, context: context)
        XCTAssertEqual(actual == nil, expected == nil, file: file, line: line)
        guard let actual, let expected else { return }
        XCTAssertEqual(actual.score, expected.score, file: file, line: line)
        XCTAssertEqual(actual.reasons, expected.reasons, file: file, line: line)
        XCTAssertEqual(actual.visibilityWindow.start, expected.window.start, file: file, line: line)
        XCTAssertEqual(actual.visibilityWindow.end, expected.window.end, file: file, line: line)
        XCTAssertEqual(actual.visibilityWindow.bestTime, expected.window.bestTime, file: file, line: line)
        XCTAssertEqual(actual.visibilityWindow.maxAltitude, expected.window.maxAltitude, file: file, line: line)
        XCTAssertEqual(actual.visibilityWindow.azimuth, expected.window.azimuth, file: file, line: line)
        XCTAssertEqual(actual.visibilityWindow.direction, expected.window.direction, file: file, line: line)
        XCTAssertEqual(actual.visibilityWindow.id, expected.window.id, file: file, line: line)
        XCTAssertEqual(actual.id, "moon-\(expected.window.id)", file: file, line: line)
    }

    func testLiveProviderStillProducesTheProductionShape() throws {
        let provider = DefaultMoonTargetRecommendationProvider()
        let context = Self.context(
            bestWindow: .init(start: Self.date(hour: 21), end: Self.date(hour: 25)),
            hourlyScore: 0.2,
            cloudCoverScore: 5,
            includeRatings: true
        )
        let observation = SunCalcMoonAstronomyProvider().moonObservation(for: context)
        let recommendation = provider.recommendation(for: Self.moonTarget, context: context)
        let legacy = LegacyMoonRecommendationOracle.recommendation(
            observation: observation, context: context
        )
        XCTAssertEqual(recommendation?.score, legacy?.score)
        XCTAssertEqual(recommendation?.reasons, legacy?.reasons)
        XCTAssertEqual(recommendation?.visibilityWindow.bestTime, legacy?.window.bestTime)
    }

    /// The validation summary counted samples visible *inside the useful window*
    /// before the migration; a best conditions window narrower than the night
    /// must still exclude the samples outside it.
    func testValidationSummarySamplesStayClippedToTheUsefulWindow() {
        let observation = Self.observation(
            phase: 0.25, illumination: 50,
            altitudes: [18, 35, 48, 30, 22, 11, 6, 2],
            azimuthOffset: 0, alwaysDown: false, set: nil
        )
        let night = Self.context(bestWindow: nil, hourlyScore: 0.2,
                                 cloudCoverScore: 5, includeRatings: true)
        XCTAssertEqual(
            DefaultMoonTargetRecommendationProvider
                .usefulVisibleSamples(observation: observation, context: night).count,
            observation.positionSamples.count
        )

        let narrow = Self.context(
            bestWindow: .init(start: Self.date(hour: 21).addingTimeInterval(1800),
                              end: Self.date(hour: 21).addingTimeInterval(3 * 1800)),
            hourlyScore: 0.2, cloudCoverScore: 5, includeRatings: true
        )
        let clipped = DefaultMoonTargetRecommendationProvider
            .usefulVisibleSamples(observation: observation, context: narrow)
        XCTAssertEqual(clipped.map(\.altitude), [35, 48, 30])
    }

    func testNonMoonTargetsStillProduceNoRecommendation() {
        let provider = DefaultMoonTargetRecommendationProvider(
            moonAstronomyProvider: StubMoonAstronomyProvider(
                observation: Self.observation(
                    phase: 0.25, illumination: 50, altitudes: [18, 35, 48, 30],
                    azimuthOffset: 0, alwaysDown: false, set: nil
                )
            )
        )
        let planet = ObservableTarget(id: "jupiter", name: "Jupiter", type: .planet,
                                      preferredEquipment: .telescope, difficulty: 0.2)
        XCTAssertNil(provider.recommendation(
            for: planet,
            context: Self.context(bestWindow: nil, hourlyScore: 0.2,
                                  cloudCoverScore: 5, includeRatings: true)
        ))
    }

    // MARK: - Helpers

    static let moonTarget = ObservableTarget(
        id: "moon", name: "Moon", type: .moon, preferredEquipment: .nakedEye, difficulty: 0.1
    )

    static func observation(
        phase: Double,
        illumination: Int,
        altitudes: [Double],
        azimuthOffset: Double,
        alwaysDown: Bool,
        set: Date?
    ) -> MoonObservationData {
        MoonObservationData(
            phase: phase,
            phaseName: "",
            illumination: illumination,
            rise: date(hour: 19),
            set: set,
            alwaysUp: false,
            alwaysDown: alwaysDown,
            positionSamples: altitudes.enumerated().map { index, altitude in
                MoonPositionSample(
                    time: date(hour: 21).addingTimeInterval(Double(index) * 1800),
                    altitude: altitude,
                    azimuth: index == 3 ? nil : (azimuthOffset + Double(index) * 23).truncatingRemainder(dividingBy: 360)
                )
            }
        )
    }

    static func context(
        bestWindow: NightQualityAssessment.TimeWindow?,
        hourlyScore: Double,
        cloudCoverScore: Double,
        includeRatings: Bool,
        ratingRows: [NightQualityAssessment.HourlyRating]? = nil
    ) -> TargetRecommendationContext {
        TargetRecommendationContext(
            location: CachedLocation(name: "Sweep", latitude: 34, longitude: -118, elevation: 0),
            astronomicalNightStart: date(hour: 20),
            astronomicalNightEnd: date(hour: 29),
            nightQuality: NightQualityAssessment(
                rating: NightQualityAssessment.Rating.from(score: hourlyScore),
                summary: "Sweep",
                details: NightQualityAssessment.Details(
                    cloudCoverScore: cloudCoverScore, fogScoreAvg: 5,
                    moonIlluminationAvg: 50, windSpeedAvg: 2
                ),
                bestWindow: bestWindow,
                hourlyRatings: ratingRows ?? (includeRatings ? (20..<29).map { hour in
                    NightQualityAssessment.HourlyRating(
                        time: date(hour: hour),
                        score: hourlyScore + Double(hour % 3) * 0.1,
                        cloudCover: Int(cloudCoverScore), fogScore: 5,
                        moonIllumination: 50, moonAltitude: 35, windSpeed: 2
                    )
                } : []),
                nightStart: date(hour: 20),
                nightEnd: date(hour: 29)
            ),
            moonInfo: MoonInfo(phase: 0.25, phaseName: "First Quarter", altitude: 35,
                               illumination: 50, emoji: "")
        )
    }

    static func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1 + hour / 24
        components.hour = hour % 24
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

private struct StubMoonAstronomyProvider: MoonAstronomyProviding {
    let observation: MoonObservationData

    func moonObservation(for context: TargetRecommendationContext) -> MoonObservationData {
        observation
    }
}

/// Verbatim pre-migration production math. Do not "improve" it and do not route
/// it through the shared engine: its only job is to be the old behavior.
private enum LegacyMoonRecommendationOracle {
    struct Outcome {
        let score: Int
        let window: TargetVisibilityWindow
        let reasons: [TargetRecommendationReason]
    }

    static func recommendation(
        observation: MoonObservationData,
        context: TargetRecommendationContext
    ) -> Outcome? {
        let usefulWindow = context.nightQuality.bestWindow.map {
            NightQualityAssessment.TimeWindow(start: $0.start, end: $0.end)
        } ?? NightQualityAssessment.TimeWindow(
            start: context.astronomicalNightStart,
            end: context.astronomicalNightEnd
        )
        let usefulSamples = observation.positionSamples.filter {
            $0.time >= usefulWindow.start && $0.time <= usefulWindow.end
        }
        let visibleSamples = usefulSamples.filter { $0.altitude > 0 }
        guard !visibleSamples.isEmpty else { return nil }

        let bestSample = visibleSamples.max { $0.altitude < $1.altitude }

        let visibleWindow = visibilityWindow(
            usefulWindow: usefulWindow,
            visibleSamples: visibleSamples,
            bestSample: bestSample
        )
        let score = score(
            observation: observation,
            visibleFraction: visibleFraction(samples: usefulSamples),
            weatherQuality: weatherQuality(in: visibleWindow, context: context)
        )
        let reasons = reasons(
            observation: observation,
            usefulWindow: usefulWindow,
            visibleSamples: visibleSamples,
            visibleFraction: visibleFraction(samples: usefulSamples),
            weatherQuality: weatherQuality(in: visibleWindow, context: context)
        )
        return Outcome(score: score, window: visibleWindow, reasons: reasons)
    }

    private static func visibilityWindow(
        usefulWindow: NightQualityAssessment.TimeWindow,
        visibleSamples: [MoonPositionSample],
        bestSample: MoonPositionSample?
    ) -> TargetVisibilityWindow {
        let bestTime = bestSample?.time ?? usefulWindow.start.addingTimeInterval(usefulWindow.duration / 2)
        let start = visibleSamples.first?.time ?? usefulWindow.start
        let end = visibleSamples.last?.time.addingTimeInterval(30 * 60) ?? usefulWindow.end

        return TargetVisibilityWindow(
            start: max(start, usefulWindow.start),
            end: min(max(end, start.addingTimeInterval(30 * 60)), usefulWindow.end),
            bestTime: bestTime,
            maxAltitude: bestSample?.altitude,
            direction: bestSample?.azimuth.map(Self.compassDirection),
            azimuth: bestSample?.azimuth
        )
    }

    private static func score(
        observation: MoonObservationData,
        visibleFraction: Double,
        weatherQuality: Double
    ) -> Int {
        let phaseQuality = phaseQuality(observation: observation)
        let rawScore = phaseQuality * 45 + visibleFraction * 30 + weatherQuality * 25
        let cappedScore = observation.illumination <= 8 ? min(rawScore, 35) : rawScore
        return Int(round(min(max(cappedScore, 0), 100)))
    }

    private static func phaseQuality(observation: MoonObservationData) -> Double {
        let phase = observation.phase
        let illumination = observation.illumination

        if illumination <= 8 || phase <= 0.04 || phase >= 0.96 {
            return 0.12
        }

        let quarterDistance = min(abs(phase - 0.25), abs(phase - 0.75))
        if quarterDistance <= 0.08 {
            return 1.0
        }

        if illumination <= 45 {
            return 0.82
        }

        if illumination >= 90 {
            return 0.70
        }

        return 0.68
    }

    private static func reasons(
        observation: MoonObservationData,
        usefulWindow: NightQualityAssessment.TimeWindow,
        visibleSamples: [MoonPositionSample],
        visibleFraction: Double,
        weatherQuality: Double
    ) -> [TargetRecommendationReason] {
        var reasons: [TargetRecommendationReason] = []
        let phase = observation.phase

        if visibleSamples.isEmpty || visibleFraction < 0.25 || observation.alwaysDown {
            reasons.append(.moonBelowUsefulWindow)
        }

        if observation.illumination <= 8 || phase <= 0.04 || phase >= 0.96 {
            reasons.append(.newMoonDarkSky)
        } else if min(abs(phase - 0.25), abs(phase - 0.75)) <= 0.08 {
            reasons.append(.excellentMoonCraterDetail)
        } else if observation.illumination >= 90 {
            reasons.append(.brightFullMoonDeepSkyImpact)
        } else if visibleFraction >= 0.25 {
            reasons.append(.moonVisibleUsefulWindow)
        }

        if let set = observation.set,
           set > usefulWindow.start,
           set < usefulWindow.end.addingTimeInterval(-2 * 3600),
           observation.illumination >= 40 {
            reasons.append(.moonSetsEarlyDarkSkyLater)
        }

        if weatherQuality < 0.45 {
            reasons.append(.poorWeather)
        }

        return reasons.isEmpty ? [.moonVisibleUsefulWindow] : reasons
    }

    private static func visibleFraction(samples: [MoonPositionSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let visibleCount = samples.filter { $0.altitude > 0 }.count
        return Double(visibleCount) / Double(samples.count)
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
}
