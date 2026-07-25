import Foundation
import SharedCode
import SwiftUI
import XCTest

final class WidgetTonightPresentationTests: XCTestCase {
    func testWidgetPresentationHelperOnlyFormatsTrendAndTime() {
        XCTAssertEqual(WidgetTonightPresentation.trendLabel(for: .improving), "Improving")
        XCTAssertEqual(WidgetTonightPresentation.trendSymbol(for: .degrading), "↘")

        let formatted = WidgetTonightPresentation.bestWindowText(
            .init(start: date(hour: 23, minute: 10), end: date(dayOffset: 1, hour: 3, minute: 30)),
            timeZone: TimeZone(secondsFromGMT: 0)
        )
        XCTAssertEqual(formatted?.replacingOccurrences(of: "\u{202F}", with: " "), "11:10 PM–3:30 AM")
    }

    func testSmallConditionSummaryUsesHalfNightLabelsWhenTheyDiffer() {
        XCTAssertEqual(
            WidgetTonightPresentation.smallConditionSummary(
                earlyQuality: "Fair",
                lateQuality: "Poor",
                trend: .stable
            ),
            .init(label: "Fair → Poor", symbol: nil)
        )
    }

    func testSmallConditionSummaryUsesCanonicalTrendWhenHalfNightLabelsMatch() {
        XCTAssertEqual(
            WidgetTonightPresentation.smallConditionSummary(
                earlyQuality: "Good",
                lateQuality: "Good",
                trend: .improving
            ),
            .init(label: "Improving", symbol: "↗")
        )
        XCTAssertEqual(
            WidgetTonightPresentation.smallConditionSummary(
                earlyQuality: "Good",
                lateQuality: "Good",
                trend: .stable
            ),
            .init(label: "Steady", symbol: "→")
        )
        XCTAssertEqual(
            WidgetTonightPresentation.smallConditionSummary(
                earlyQuality: "Good",
                lateQuality: "Good",
                trend: .degrading
            ),
            .init(label: "Degrading", symbol: "↘")
        )
    }

    func testIdentityIconUsesTheDecorativeSparklesSymbol() {
        XCTAssertEqual(WidgetTonightPresentation.identitySymbol, "sparkles")
        XCTAssertTrue(WidgetTonightPresentation.identitySymbolIsDecorative)
    }

    func testCompactBestWindowTextRemovesOnlyZeroMinutesAndRetainsAMPM() {
        let timeZone = TimeZone(secondsFromGMT: 0)

        XCTAssertEqual(
            readableCompactRange(WidgetTonightPresentation.compactBestWindowText(
                .init(start: date(hour: 22), end: date(dayOffset: 1, hour: 0)),
                timeZone: timeZone
            )),
            "10 PM–12 AM"
        )
        XCTAssertEqual(
            readableCompactRange(WidgetTonightPresentation.compactBestWindowText(
                .init(start: date(hour: 22, minute: 30), end: date(dayOffset: 1, hour: 0)),
                timeZone: timeZone
            )),
            "10:30 PM–12 AM"
        )
    }

    func testCompactTimeRangeJoinsTheSeparatorToBothEndpoints() {
        let range = WidgetTonightPresentation.compactBestWindowText(
            .init(start: date(hour: 23), end: date(dayOffset: 1, hour: 1, minute: 30)),
            timeZone: TimeZone(secondsFromGMT: 0)
        )

        XCTAssertEqual(readableCompactRange(range), "11 PM–1:30 AM")
        XCTAssertTrue(range?.contains("\u{2060}–\u{2060}") == true)
        XCTAssertFalse(range?.contains("\n–\n") == true)
    }

    func testWidgetContentDensityUsesExplicitThresholds() {
        XCTAssertEqual(WidgetContentDensity.resolve(for: .xSmall), .regular)
        XCTAssertEqual(WidgetContentDensity.resolve(for: .xLarge), .regular)
        XCTAssertEqual(WidgetContentDensity.resolve(for: .xxLarge), .compact)
        XCTAssertEqual(WidgetContentDensity.resolve(for: .xxxLarge), .compact)
        XCTAssertEqual(WidgetContentDensity.resolve(for: .accessibility1), .compact)
        XCTAssertEqual(WidgetContentDensity.resolve(for: .accessibility2), .compact)
        XCTAssertEqual(WidgetContentDensity.resolve(for: .accessibility3), .minimal)
        XCTAssertEqual(WidgetContentDensity.resolve(for: .accessibility5), .minimal)
    }

    func testSmallMinimalLayoutMayOmitTheConditionSummary() {
        XCTAssertFalse(WidgetTonightPresentation.smallLayoutShowsConditionSummary(for: .minimal))
        XCTAssertTrue(WidgetTonightPresentation.smallLayoutShowsConditionSummary(for: .regular))
        XCTAssertTrue(WidgetTonightPresentation.smallLayoutShowsConditionSummary(for: .compact))
    }

    func testMediumCompactAndMinimalLayoutsKeepFirstAndLastResolvedFactors() {
        let factors = [
            NightQualityDisplayFactor(kind: .clouds, label: "Clouds", value: "78%", tone: .limiting),
            NightQualityDisplayFactor(kind: .seeing, label: "Seeing", value: "Excellent", tone: .favorable),
            NightQualityDisplayFactor(kind: .transparency, label: "Transparency", value: "Poor", tone: .limiting)
        ]

        XCTAssertEqual(
            WidgetTonightPresentation.mediumLayoutFactors(factors, density: .compact).map(\.kind),
            [.clouds, .transparency]
        )
        XCTAssertEqual(
            WidgetTonightPresentation.mediumLayoutFactors(factors, density: .minimal).map(\.kind),
            [.clouds, .transparency]
        )
        XCTAssertEqual(
            WidgetTonightPresentation.mediumLayoutFactors(factors, density: .regular),
            factors
        )
    }

    func testMediumCondensedLayoutsSafelyKeepAvailableOptionalFactors() {
        let clouds = NightQualityDisplayFactor(kind: .clouds, label: "Clouds", value: "78%", tone: .limiting)
        let seeing = NightQualityDisplayFactor(kind: .seeing, label: "Seeing", value: "Excellent", tone: .favorable)

        XCTAssertEqual(
            WidgetTonightPresentation.mediumLayoutFactors([clouds], density: .minimal),
            [clouds]
        )
        XCTAssertEqual(
            WidgetTonightPresentation.mediumLayoutFactors([clouds, seeing], density: .compact),
            [clouds, seeing]
        )
        XCTAssertTrue(WidgetTonightPresentation.mediumLayoutFactors([], density: .minimal).isEmpty)
        XCTAssertTrue(WidgetTonightPresentation.mediumLayoutFactors([clouds], density: .minimal, includesFactors: false).isEmpty)
    }

    func testMediumCondensedFactorSummaryKeepsFactorsAndValuesTogether() {
        let clouds = NightQualityDisplayFactor(kind: .clouds, label: "Clouds", value: "67%", tone: .limiting)
        let seeing = NightQualityDisplayFactor(kind: .seeing, label: "Seeing", value: "Excellent", tone: .favorable)
        let transparency = NightQualityDisplayFactor(kind: .transparency, label: "Transparency", value: "Poor", tone: .limiting)

        XCTAssertEqual(
            WidgetTonightPresentation.mediumCondensedFactorSummary([clouds, seeing, transparency], density: .minimal),
            "Clouds 67%  •  Transparency Poor"
        )
        XCTAssertEqual(
            WidgetTonightPresentation.mediumCondensedFactorSummary([clouds], density: .minimal),
            "Clouds 67%"
        )
        XCTAssertNil(WidgetTonightPresentation.mediumCondensedFactorSummary([], density: .minimal))
    }

    func testMediumCondensedLayoutsOmitLocation() {
        XCTAssertTrue(WidgetTonightPresentation.mediumLayoutShowsLocation(for: .regular))
        XCTAssertFalse(WidgetTonightPresentation.mediumLayoutShowsLocation(for: .compact))
        XCTAssertFalse(WidgetTonightPresentation.mediumLayoutShowsLocation(for: .minimal))
    }

    func testSharedWidgetPayloadModelHasNoWidgetPresentationDependencies() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelURL = repositoryRoot.appendingPathComponent("Sources/SharedCode/Core/Models/WidgetNightSummary.swift")
        let source = try String(contentsOf: modelURL, encoding: .utf8)

        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("WidgetContentDensity"))
        XCTAssertFalse(source.contains("WidgetTonightPresentation"))
    }

    func testMoonPenaltyMatchesPrePhaseOneBehavior() {
        XCTAssertEqual(NightQualityAnalysisRules.moonPenalty(illumination: 100, altitude: -1), 0)
        XCTAssertEqual(NightQualityAnalysisRules.moonPenalty(illumination: 10, altitude: 90), 0)
        XCTAssertEqual(NightQualityAnalysisRules.moonPenalty(illumination: 25, altitude: 90), 0.5)
        XCTAssertEqual(NightQualityAnalysisRules.moonPenalty(illumination: 50, altitude: 90), 1)
        XCTAssertEqual(NightQualityAnalysisRules.moonPenalty(illumination: 100, altitude: 45), 1.5)
        XCTAssertEqual(NightQualityAnalysisRules.moonPenalty(illumination: 100, altitude: 90), 2)
    }

    func testWindPenaltyMatchesPrePhaseOneThresholdBoundaries() {
        XCTAssertEqual(NightQualityAnalysisRules.windPenalty(3), 0)
        XCTAssertEqual(NightQualityAnalysisRules.windPenalty(3.0001), 0.5)
        XCTAssertEqual(NightQualityAnalysisRules.windPenalty(6), 0.5)
        XCTAssertEqual(NightQualityAnalysisRules.windPenalty(6.0001), 1)
        XCTAssertEqual(NightQualityAnalysisRules.windPenalty(10), 1)
        XCTAssertEqual(NightQualityAnalysisRules.windPenalty(10.0001), 2)
    }

    func testResolvedFactorsPreserveCloudSeeingTransparencyOrder() {
        let presentation = NightQualityPresentation(assessment: assessment())
        let summary = summary(factors: presentation.factors)

        XCTAssertEqual(summary.factors.map(\.kind), [.clouds, .seeing, .transparency])
        XCTAssertEqual(Array(summary.factors.prefix(2)).map(\.kind), [.clouds, .seeing])
    }

    func testDisplayFactorKindHasNoMoonOrWindCases() {
        let presentation = NightQualityPresentation(
            assessment: assessment(hourlyRatings: [rating(moonIllumination: 100, moonAltitude: 90, windSpeed: 25)])
        )

        XCTAssertEqual(NightQualityDisplayFactor.Kind.allCases, [.clouds, .seeing, .transparency])
        XCTAssertEqual(presentation.factors.map(\.kind), [.clouds, .seeing, .transparency])
    }

    func testSingleHourMoonOrWindPenaltyDoesNotChangeAnalyzerHeadline() {
        let assessment = assessment(
            hourlyRatings: [rating(moonIllumination: 100, moonAltitude: 90, windSpeed: 25)],
            summary: "Good overall conditions, but some clouds may affect the view."
        )

        XCTAssertEqual(NightQualityPresentation(assessment: assessment).primaryMessage, assessment.summary)
    }

    func testHeavyCloudTimingMatchesExistingEarlyLateAndIntermittentResults() {
        let clearBefore = rating(time: date(hour: 20), score: 0.2, cloudCover: 10)
        let heavyOne = rating(time: date(hour: 21), score: 1.2, cloudCover: 90)
        let heavyTwo = rating(time: date(hour: 22), score: 1.2, cloudCover: 90)
        let clearAfter = rating(time: date(hour: 23), score: 0.2, cloudCover: 10)

        XCTAssertEqual(NightQualityAnalysisRules.cloudTiming(in: [clearBefore, heavyOne, heavyTwo]), .lateHeavy)
        XCTAssertEqual(NightQualityAnalysisRules.cloudTiming(in: [heavyOne, heavyTwo, clearAfter]), .earlyHeavy)
        XCTAssertEqual(NightQualityAnalysisRules.cloudTiming(in: [clearBefore, heavyOne, heavyTwo, clearAfter]), .intermittentHeavy)
    }

    func testAnalyzerSummaryRetainsExistingHeavyCloudText() {
        let result = NightQualityAnalyzer.analyzeNight(
            forecasts: (20...23).map { hour in
                HourlyForecast(
                    time: date(hour: hour), cloudCover: 100, humidity: 40, windSpeed: 2,
                    windDirection: 180, temperature: 15, dewPoint: 5, visibility: 20_000
                )
            },
            sunEventsToday: sunEvents(for: date(hour: 12)),
            sunEventsTomorrow: sunEvents(for: date(dayOffset: 1, hour: 12)),
            moonInfo: .init(phase: 0.2, phaseName: "Waxing", altitude: 0, illumination: 20, emoji: "🌒"),
            latitude: 45.5,
            longitude: -122.7,
            for: date(hour: 12),
            calendar: utcCalendar
        )

        XCTAssertEqual(result.summary, "Poor conditions for stargazing. Heavy clouds are likely to block the view.")
    }

    func testMissingOptionalFactorsAreHandledWithoutFabricatedValues() {
        let presentation = NightQualityPresentation(assessment: assessment(seeingScore: nil, transparencyScore: nil))
        XCTAssertEqual(presentation.factors.map(\.kind), [.clouds])
    }

    func testRenamedDisplayFactorPreservesCodableBehavior() throws {
        let factor = NightQualityDisplayFactor(kind: .seeing, label: "Seeing", value: "Good", tone: .favorable)
        let decoded = try JSONDecoder().decode(NightQualityDisplayFactor.self, from: JSONEncoder().encode(factor))
        XCTAssertEqual(decoded, factor)
    }

    func testOlderPhaseOneSummaryDecodesAsTruthfulReducedPresentation() throws {
        let data = """
        { "generatedAt": 743385600, "locationName": "Home", "latitude": 45.5,
          "longitude": -122.7, "score": 73, "verdict": "Good", "cloudCover": 0,
          "moonIllumination": 0, "windSpeed": 0, "dominantCondition": "Clear skies" }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WidgetNightSummary.self, from: data)
        XCTAssertEqual(decoded.primaryMessage, "Open Astro Conditions to update")
        XCTAssertTrue(decoded.factors.isEmpty)
    }

    func testLegacyFullViewingConditionsCacheStillConverts() throws {
        let decoded = WidgetNightSummary.decodeCachedPayload(try JSONEncoder().encode(legacyConditions()))
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.locationName, "Home")
    }

    func testLocalDayFreshnessRejectsCacheAcrossMidnight() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let generatedAt = calendar.date(from: .init(year: 2026, month: 7, day: 25, hour: 23, minute: 45))!
        let referenceDate = calendar.date(from: .init(year: 2026, month: 7, day: 26, hour: 0, minute: 15))!
        XCTAssertFalse(summary(generatedAt: generatedAt).isFreshForLocalDay(within: 3600, relativeTo: referenceDate))
    }

    private func assessment(
        hourlyRatings: [NightQualityAssessment.HourlyRating]? = nil,
        summary: String = "Shared assessment",
        seeingScore: Double? = 0.4,
        transparencyScore: Double? = 0.4
    ) -> NightQualityAssessment {
        let ratings = hourlyRatings ?? [rating()]
        return NightQualityAssessment(
            rating: .good, summary: summary,
            details: .init(cloudCoverScore: 28, fogScoreAvg: 0, moonIlluminationAvg: 20, windSpeedAvg: 2, seeingScoreAvg: seeingScore, transparencyScoreAvg: transparencyScore),
            bestWindow: .init(start: date(hour: 20), end: date(hour: 23)), hourlyRatings: ratings,
            nightStart: date(hour: 20), nightEnd: date(hour: 23), trend: .stable,
            firstHalfScore: 0.7, secondHalfScore: 0.3
        )
    }

    private func rating(time: Date? = nil, score: Double = 0.3, cloudCover: Int = 28, moonIllumination: Int = 20, moonAltitude: Double = -5, windSpeed: Double = 2) -> NightQualityAssessment.HourlyRating {
        .init(time: time ?? date(hour: 20), score: score, cloudCover: cloudCover, fogScore: 0, moonIllumination: moonIllumination, moonAltitude: moonAltitude, windSpeed: windSpeed, seeingScore: 0.4, transparencyScore: 0.4)
    }

    private func summary(generatedAt: Date = Date(timeIntervalSince1970: 0), factors: [NightQualityDisplayFactor] = []) -> WidgetNightSummary {
        WidgetNightSummary(
            generatedAt: generatedAt, locationName: "Home", latitude: 45.5, longitude: -122.7,
            timeZoneIdentifier: "America/Los_Angeles", score: 73, verdict: "Good", earlyQuality: "Fair",
            lateQuality: "Good", trend: .improving, bestWindow: nil, primaryMessage: "Shared assessment",
            factors: factors, hasAstronomicalNight: true
        )
    }

    private func legacyConditions() -> ViewingConditions {
        let today = utcCalendar.startOfDay(for: Date())
        let tomorrow = utcCalendar.date(byAdding: .day, value: 1, to: today)!
        return ViewingConditions(
            fetchedAt: Date(), location: .init(name: "Home", latitude: 45.5, longitude: -122.7),
            hourlyForecasts: [20, 21, 22].map { hour in HourlyForecast(time: utcCalendar.date(byAdding: .hour, value: hour, to: today)!, cloudCover: 20, humidity: 40, windSpeed: 2, windDirection: 180, temperature: 14, dewPoint: 5, visibility: 20_000, lowCloudCover: 5, midCloudCover: 5, highCloudCover: 5) },
            dailySunEvents: [sunEvents(for: today), sunEvents(for: tomorrow)],
            dailyMoonInfo: [.init(phase: 0.2, phaseName: "Waxing", altitude: 20, illumination: 20, emoji: "🌒")],
            issPasses: [], fogScore: .init(score: 0, factors: []), timeZoneIdentifier: "UTC"
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func sunEvents(for day: Date) -> SunEvents {
        func time(_ hour: Int) -> Date { utcCalendar.date(byAdding: .hour, value: hour, to: utcCalendar.startOfDay(for: day))! }
        return SunEvents(sunrise: time(6), sunset: time(20), civilTwilightBegin: time(5), civilTwilightEnd: time(21), nauticalTwilightBegin: time(4), nauticalTwilightEnd: time(22), astronomicalTwilightBegin: time(3), astronomicalTwilightEnd: time(20))
    }

    private func date(dayOffset: Int = 0, hour: Int, minute: Int = 0) -> Date {
        utcCalendar.date(from: .init(year: 2026, month: 7, day: 25 + dayOffset, hour: hour, minute: minute))!
    }

    private func readableCompactRange(_ range: String?) -> String? {
        range?
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2060}", with: "")
    }
}
