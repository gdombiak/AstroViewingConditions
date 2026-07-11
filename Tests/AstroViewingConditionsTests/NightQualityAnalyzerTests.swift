import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class NightQualityAnalyzerTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    private func createDate(hour: Int, dayOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 1 + dayOffset
        components.hour = hour
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components) ?? Date()
    }
    
    private func createSunEvents(for dayOffset: Int) -> SunEvents {
        SunEvents(
            sunrise: createDate(hour: 6, dayOffset: dayOffset),
            sunset: createDate(hour: 18, dayOffset: dayOffset),
            civilTwilightBegin: createDate(hour: 5, dayOffset: dayOffset),
            civilTwilightEnd: createDate(hour: 19, dayOffset: dayOffset),
            nauticalTwilightBegin: createDate(hour: 4, dayOffset: dayOffset),
            nauticalTwilightEnd: createDate(hour: 20, dayOffset: dayOffset),
            astronomicalTwilightBegin: createDate(hour: 5, dayOffset: dayOffset),
            astronomicalTwilightEnd: createDate(hour: 20, dayOffset: dayOffset)
        )
    }
    
    private func createForecasts(hours: [(hour: Int, cloudCover: Int, humidity: Int, windSpeed: Double)], dayOffset: Int = 0) -> [HourlyForecast] {
        hours.map { hourData in
            HourlyForecast(
                time: createDate(hour: hourData.hour, dayOffset: dayOffset),
                cloudCover: hourData.cloudCover,
                humidity: hourData.humidity,
                windSpeed: hourData.windSpeed,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 5.0,
                visibility: 20000,
                lowCloudCover: nil
            )
        }
    }
    
    private func analyze(forecasts: [HourlyForecast], moonIllumination: Int, dayOffset: Int = 0) -> NightQualityAssessment {
        let sunEventsToday = createSunEvents(for: dayOffset)
        let sunEventsTomorrow = createSunEvents(for: dayOffset + 1)
        let moonInfo = MoonInfo(
            phase: Double(moonIllumination) / 100.0,
            phaseName: moonIllumination < 25 ? "New Moon" : (moonIllumination > 75 ? "Full Moon" : "Half Moon"),
            altitude: 45.0,
            illumination: moonIllumination,
            emoji: moonIllumination < 25 ? "🌑" : (moonIllumination > 75 ? "🌕" : "🌓")
        )
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        
        return NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: 40.7128,  // New York City coordinates for testing
            longitude: -74.0060,
            for: createDate(hour: 12, dayOffset: dayOffset),
            calendar: calendar
        )
    }
    
    // MARK: - Clear Sky Tests
    
    func testExcellentConditionsWithClearSkyAndNewMoon() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 40, windSpeed: 2.0),
            (hour: 21, cloudCover: 0, humidity: 45, windSpeed: 2.5),
            (hour: 22, cloudCover: 0, humidity: 50, windSpeed: 1.5),
            (hour: 23, cloudCover: 0, humidity: 55, windSpeed: 1.0),
            (hour: 0, cloudCover: 0, humidity: 40, windSpeed: 1.5),
            (hour: 1, cloudCover: 0, humidity: 45, windSpeed: 1.0),
            (hour: 2, cloudCover: 0, humidity: 50, windSpeed: 1.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 5)
        
        XCTAssertFalse(result.hourlyRatings.isEmpty)
        XCTAssertEqual(result.rating, .excellent)
        XCTAssertEqual(result.details.cloudCoverScore, 0)
        XCTAssertLessThan(result.details.moonIlluminationAvg, 100)
        XCTAssertGreaterThanOrEqual(result.details.moonIlluminationAvg, 0)
    }
    
    // MARK: - Cloud Cover Tests
    
    func test100CloudsShouldBePoor() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 100, humidity: 40, windSpeed: 2.0),
            (hour: 21, cloudCover: 100, humidity: 45, windSpeed: 2.5),
            (hour: 22, cloudCover: 100, humidity: 50, windSpeed: 1.5),
            (hour: 23, cloudCover: 100, humidity: 55, windSpeed: 1.0),
            (hour: 0, cloudCover: 100, humidity: 40, windSpeed: 1.5),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 5)
        
        XCTAssertFalse(result.hourlyRatings.isEmpty)
        XCTAssertEqual(result.rating, .poor)
    }

    func testMiamiLikeOvercastForecastsRemainPoorAndCloudAware() {
        let overcastForecasts = (20...23).enumerated().map { index, hour in
            HourlyForecast(
                time: createDate(hour: hour),
                cloudCover: 100,
                humidity: 80,
                windSpeed: Double(index + 2),
                windDirection: 180,
                temperature: 25,
                dewPoint: 21,
                visibility: 18_000,
                lowCloudCover: 0,
                midCloudCover: 0,
                highCloudCover: 100,
                windSpeed200hPa: 50
            )
        }
        let clearForecasts = overcastForecasts.map { forecast in
            HourlyForecast(
                time: forecast.time,
                cloudCover: 0,
                humidity: forecast.humidity,
                windSpeed: forecast.windSpeed,
                windDirection: forecast.windDirection,
                temperature: forecast.temperature,
                dewPoint: forecast.dewPoint,
                visibility: forecast.visibility,
                lowCloudCover: 0,
                midCloudCover: 0,
                highCloudCover: 0,
                windSpeed200hPa: forecast.windSpeed200hPa
            )
        }

        let result = analyze(forecasts: overcastForecasts, moonIllumination: 5)
        let clearResult = analyze(forecasts: clearForecasts, moonIllumination: 5)

        XCTAssertEqual(result.details.cloudCoverScore, 100, accuracy: 0.1)
        XCTAssertEqual(result.details.transparencyScoreAvg ?? -1, 2, accuracy: 0.0001)
        XCTAssertFalse(result.summary.contains("Expect clear skies"))
        XCTAssertFalse(result.summary.contains("Perfect conditions"))
        XCTAssertTrue(result.summary.localizedCaseInsensitiveContains("cloud"))
        XCTAssertGreaterThan(
            result.hourlyRatings.map(\.score).reduce(0, +),
            clearResult.hourlyRatings.map(\.score).reduce(0, +)
        )
        XCTAssertGreaterThan(result.rating.rawValue, clearResult.rating.rawValue)
    }

    func testHighCloudCoverStableSummaryIncludesPoorSeeingWarning() {
        let forecasts = (20...23).map { hour in
            HourlyForecast(
                time: createDate(hour: hour),
                cloudCover: 100,
                humidity: 80,
                windSpeed: 2,
                windDirection: 180,
                temperature: 25,
                dewPoint: 21,
                visibility: 18_000,
                lowCloudCover: 0,
                midCloudCover: 0,
                highCloudCover: 100,
                windSpeed200hPa: 250
            )
        }

        let result = analyze(forecasts: forecasts, moonIllumination: 5)

        XCTAssertEqual(result.trend, .stable)
        XCTAssertEqual(result.summary, "Clouds are likely to block the view. Poor seeing may limit fine detail.")
    }
    
    func testPartialCloudsShouldBeFairOrPoor() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 50, humidity: 40, windSpeed: 2.0),
            (hour: 21, cloudCover: 50, humidity: 45, windSpeed: 2.5),
            (hour: 22, cloudCover: 50, humidity: 50, windSpeed: 1.5),
            (hour: 23, cloudCover: 50, humidity: 55, windSpeed: 1.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 5)
        
        XCTAssertFalse(result.hourlyRatings.isEmpty)
        XCTAssertTrue(result.rating == .fair || result.rating == .poor)
    }
    
    // MARK: - Moon Tests
    
    func testFullMoonShouldReduceRating() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 40, windSpeed: 2.0),
            (hour: 21, cloudCover: 0, humidity: 45, windSpeed: 2.5),
            (hour: 22, cloudCover: 0, humidity: 50, windSpeed: 1.5),
            (hour: 23, cloudCover: 0, humidity: 55, windSpeed: 1.0),
        ])
        
        let resultNewMoon = analyze(forecasts: forecasts, moonIllumination: 5)
        let resultFullMoon = analyze(forecasts: forecasts, moonIllumination: 100)
        
        XCTAssertFalse(resultNewMoon.hourlyRatings.isEmpty)
        XCTAssertFalse(resultFullMoon.hourlyRatings.isEmpty)
        // With hourly moon altitude, full moon should have equal or worse rating than new moon
        // (equal when moon is below horizon, worse when above)
        XCTAssertGreaterThanOrEqual(resultFullMoon.rating.rawValue, resultNewMoon.rating.rawValue)
    }
    
    // MARK: - Wind Tests
    
    func testHighWindShouldReduceRating() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 40, windSpeed: 15.0),
            (hour: 21, cloudCover: 0, humidity: 45, windSpeed: 18.0),
            (hour: 22, cloudCover: 0, humidity: 50, windSpeed: 20.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 5)
        
        XCTAssertFalse(result.hourlyRatings.isEmpty)
        XCTAssertEqual(result.details.windSpeedAvg, 17.6, accuracy: 0.1)
    }
    
    func testCalmWindShouldBeExcellent() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 40, windSpeed: 1.0),
            (hour: 21, cloudCover: 0, humidity: 45, windSpeed: 1.5),
            (hour: 22, cloudCover: 0, humidity: 50, windSpeed: 2.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 5)
        
        XCTAssertFalse(result.hourlyRatings.isEmpty)
        XCTAssertEqual(result.rating, .excellent)
    }
    
    // MARK: - Fog Tests
    
    func testHighFogShouldReduceRating() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 98, windSpeed: 2.0),
            (hour: 21, cloudCover: 0, humidity: 98, windSpeed: 2.5),
            (hour: 22, cloudCover: 0, humidity: 98, windSpeed: 1.5),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 5)
        
        XCTAssertFalse(result.hourlyRatings.isEmpty)
        XCTAssertGreaterThan(result.details.fogScoreAvg, 0)
    }
    
    // MARK: - No Data Tests
    
    func testNoNighttimeData() {
        let forecasts = createForecasts(hours: [
            (hour: 8, cloudCover: 0, humidity: 40, windSpeed: 2.0),
            (hour: 9, cloudCover: 5, humidity: 45, windSpeed: 2.5),
            (hour: 10, cloudCover: 0, humidity: 50, windSpeed: 1.5),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 5)
        
        XCTAssertTrue(result.hourlyRatings.isEmpty)
        XCTAssertEqual(result.rating, .poor)
    }
    
    // MARK: - Details Verification
    
    func testDetailsAreCalculatedCorrectly() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 10, humidity: 40, windSpeed: 5.0),
            (hour: 21, cloudCover: 20, humidity: 45, windSpeed: 6.0),
            (hour: 22, cloudCover: 30, humidity: 50, windSpeed: 7.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 25)
        
        XCTAssertEqual(result.details.cloudCoverScore, 20, accuracy: 1)
        XCTAssertGreaterThanOrEqual(result.details.moonIlluminationAvg, 0)
        XCTAssertLessThanOrEqual(result.details.moonIlluminationAvg, 100)
        XCTAssertEqual(result.details.windSpeedAvg, 6, accuracy: 0.1)
    }
    
    // MARK: - Hourly Ratings
    
    func testHourlyRatingsHaveCorrectData() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 50, humidity: 40, windSpeed: 5.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertEqual(result.hourlyRatings.count, 1)
        XCTAssertEqual(result.hourlyRatings.first?.cloudCover, 50)
    }

    func testLegacyForecastDataPreservesExistingFormula() {
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 40, windSpeed: 4.0)
        ])

        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        let rating = try! XCTUnwrap(result.hourlyRatings.first)
        let moonScore = rating.moonAltitude <= 0 ? 0 : (rating.moonIllumination <= 10 ? 0 : rating.moonIllumination <= 25 ? 0.5 : rating.moonIllumination <= 50 ? 1 : 2) * (0.5 + 0.5 * min(max(rating.moonAltitude / 90, 0), 1))
        let expectedScore = Double(rating.fogScore) / 50 * 0.20 + moonScore * 0.15 + 0.5 * 0.10

        XCTAssertEqual(rating.score, expectedScore, accuracy: 0.0001)
        XCTAssertNil(rating.seeingScore)
        XCTAssertNil(rating.transparencyScore)
        XCTAssertNil(result.details.seeingScoreAvg)
        XCTAssertNil(result.details.transparencyScoreAvg)
    }

    func testCompleteDataPopulatesScoresAndChangesOverallScore() {
        let legacy = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 40, windSpeed: 2),
            (hour: 21, cloudCover: 0, humidity: 40, windSpeed: 2)
        ])
        let enriched = legacy.enumerated().map { index, forecast in
            HourlyForecast(
                time: forecast.time,
                cloudCover: forecast.cloudCover,
                humidity: forecast.humidity,
                windSpeed: forecast.windSpeed,
                windDirection: forecast.windDirection,
                temperature: index == 0 ? 10 : 16,
                dewPoint: forecast.dewPoint,
                visibility: 1_000,
                lowCloudCover: 100,
                midCloudCover: 100,
                highCloudCover: 100,
                windSpeed200hPa: 250
            )
        }

        let legacyResult = analyze(forecasts: legacy, moonIllumination: 10)
        let enrichedResult = analyze(forecasts: enriched, moonIllumination: 10)

        XCTAssertNotNil(enrichedResult.details.seeingScoreAvg)
        XCTAssertNotNil(enrichedResult.details.transparencyScoreAvg)
        XCTAssertGreaterThan(enrichedResult.hourlyRatings[0].score, legacyResult.hourlyRatings[0].score)
    }

    func testTransparencyOnlyFallback() {
        let forecasts = [HourlyForecast(
            time: createDate(hour: 20), cloudCover: 100, humidity: 40, windSpeed: 2, windDirection: 180,
            temperature: 10, dewPoint: 5, visibility: 20_000, lowCloudCover: 100, midCloudCover: 100, highCloudCover: 100
        )]

        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        XCTAssertNil(result.hourlyRatings[0].seeingScore)
        XCTAssertEqual(result.hourlyRatings[0].transparencyScore, 2)
    }

    func testMissingHighCloudDoesNotEnableTransparency() {
        let partialLayerForecast = HourlyForecast(
            time: createDate(hour: 20), cloudCover: 100, humidity: 40, windSpeed: 2, windDirection: 180,
            temperature: 10, dewPoint: 5, visibility: 20_000, lowCloudCover: 100, midCloudCover: 100,
            highCloudCover: nil, windSpeed200hPa: nil
        )
        let legacyForecast = HourlyForecast(
            time: partialLayerForecast.time, cloudCover: 100, humidity: 40, windSpeed: 2, windDirection: 180,
            temperature: 10, dewPoint: 5, visibility: 20_000, lowCloudCover: 100,
            midCloudCover: nil, highCloudCover: nil, windSpeed200hPa: nil
        )

        let result = analyze(forecasts: [partialLayerForecast], moonIllumination: 10)
        let legacyResult = analyze(forecasts: [legacyForecast], moonIllumination: 10)

        XCTAssertNil(result.hourlyRatings[0].transparencyScore)
        XCTAssertNil(result.details.transparencyScoreAvg)
        XCTAssertEqual(result.hourlyRatings[0].score, legacyResult.hourlyRatings[0].score, accuracy: 0.0001)
    }

    func testMissingMidCloudUsesSeeingOnlyFallback() {
        let partialLayerForecast = HourlyForecast(
            time: createDate(hour: 20), cloudCover: 100, humidity: 40, windSpeed: 2, windDirection: 180,
            temperature: 10, dewPoint: 5, visibility: 20_000, lowCloudCover: 100, midCloudCover: nil,
            highCloudCover: 100, windSpeed200hPa: 250
        )
        let seeingOnlyForecast = HourlyForecast(
            time: partialLayerForecast.time, cloudCover: 100, humidity: 40, windSpeed: 2, windDirection: 180,
            temperature: 10, dewPoint: 5, visibility: 20_000, lowCloudCover: 100,
            midCloudCover: nil, highCloudCover: nil, windSpeed200hPa: 250
        )

        let result = analyze(forecasts: [partialLayerForecast], moonIllumination: 10)
        let seeingOnlyResult = analyze(forecasts: [seeingOnlyForecast], moonIllumination: 10)

        XCTAssertNil(result.hourlyRatings[0].transparencyScore)
        XCTAssertNil(result.details.transparencyScoreAvg)
        XCTAssertNotNil(result.hourlyRatings[0].seeingScore)
        XCTAssertEqual(result.hourlyRatings[0].score, seeingOnlyResult.hourlyRatings[0].score, accuracy: 0.0001)
    }

    func testSeeingOnlyFallback() {
        let forecasts = [HourlyForecast(
            time: createDate(hour: 20), cloudCover: 100, humidity: 40, windSpeed: 2, windDirection: 180,
            temperature: 10, dewPoint: 5, visibility: 20_000, lowCloudCover: nil, windSpeed200hPa: 250
        )]

        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        XCTAssertEqual(result.hourlyRatings[0].seeingScore, 2)
        XCTAssertNil(result.hourlyRatings[0].transparencyScore)
    }

    func testDetailsAverageOnlyAvailableSeeingSamples() {
        let forecasts = [
            HourlyForecast(time: createDate(hour: 20), cloudCover: 0, humidity: 40, windSpeed: 2, windDirection: 180, temperature: 10, windSpeed200hPa: 50),
            HourlyForecast(time: createDate(hour: 21), cloudCover: 0, humidity: 40, windSpeed: 2, windDirection: 180, temperature: 12, windSpeed200hPa: nil)
        ]

        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        XCTAssertEqual(result.hourlyRatings[0].seeingScore, 0)
        XCTAssertEqual(result.hourlyRatings[1].seeingScore, 0.5)
        XCTAssertEqual(result.details.seeingScoreAvg, 0.25)
        XCTAssertNil(result.details.transparencyScoreAvg)
    }

    func testGoodNightWithPoorSeeingAppendsSummaryWarning() {
        let forecasts = (20...23).map { hour in
            HourlyForecast(
                time: createDate(hour: hour), cloudCover: 0, humidity: 40, windSpeed: 2,
                windDirection: 180, temperature: 10, dewPoint: 5, visibility: 20_000,
                windSpeed200hPa: 250
            )
        }

        let result = analyze(forecasts: forecasts, moonIllumination: 5)

        XCTAssertEqual(result.rating, .good)
        XCTAssertEqual(result.summary, "Good night for observing. Expect clear skies. Poor seeing may limit fine detail.")
    }

    func testGoodNightWithoutPoorSeeingPreservesSummary() {
        let fairSeeingForecasts = (20...23).map { hour in
            HourlyForecast(
                time: createDate(hour: hour), cloudCover: 0, humidity: 40, windSpeed: 7,
                windDirection: 180, temperature: 10, dewPoint: 5, visibility: 20_000,
                windSpeed200hPa: 150
            )
        }
        let missingSeeingForecasts = (20...23).map { hour in
            HourlyForecast(
                time: createDate(hour: hour), cloudCover: 20, humidity: 40, windSpeed: 4,
                windDirection: 180, temperature: 10, dewPoint: 5, visibility: 20_000
            )
        }

        let fairSeeingResult = analyze(forecasts: fairSeeingForecasts, moonIllumination: 5)
        let missingSeeingResult = analyze(forecasts: missingSeeingForecasts, moonIllumination: 5)

        XCTAssertEqual(fairSeeingResult.summary, "Good night for observing. Expect clear skies.")
        XCTAssertEqual(missingSeeingResult.summary, "Good night for observing. Expect clear skies.")
    }

    func testAnalyzeConditionsUsesLocationDayWhenUTCDateHasAdvanced() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        func localDate(dayOffset: Int, hour: Int) -> Date {
            var components = DateComponents()
            components.timeZone = calendar.timeZone
            components.year = 2026
            components.month = 5
            components.day = 30 + dayOffset
            components.hour = hour
            return calendar.date(from: components)!
        }

        func localSunEvents(dayOffset: Int) -> SunEvents {
            SunEvents(
                sunrise: localDate(dayOffset: dayOffset, hour: 6),
                sunset: localDate(dayOffset: dayOffset, hour: 19),
                civilTwilightBegin: localDate(dayOffset: dayOffset, hour: 5),
                civilTwilightEnd: localDate(dayOffset: dayOffset, hour: 20),
                nauticalTwilightBegin: localDate(dayOffset: dayOffset, hour: 5),
                nauticalTwilightEnd: localDate(dayOffset: dayOffset, hour: 20),
                astronomicalTwilightBegin: localDate(dayOffset: dayOffset + 1, hour: 4),
                astronomicalTwilightEnd: localDate(dayOffset: dayOffset, hour: 21)
            )
        }

        let forecasts = [
            HourlyForecast(time: localDate(dayOffset: 0, hour: 21), cloudCover: 20, humidity: 50, windSpeed: 2, windDirection: 180, temperature: 12, dewPoint: 3, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: localDate(dayOffset: 0, hour: 22), cloudCover: 20, humidity: 50, windSpeed: 2, windDirection: 180, temperature: 12, dewPoint: 3, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: localDate(dayOffset: 1, hour: 21), cloudCover: 80, humidity: 50, windSpeed: 2, windDirection: 180, temperature: 12, dewPoint: 3, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: localDate(dayOffset: 1, hour: 22), cloudCover: 80, humidity: 50, windSpeed: 2, windDirection: 180, temperature: 12, dewPoint: 3, visibility: 20000, lowCloudCover: nil)
        ]
        let conditions = ViewingConditions(
            fetchedAt: localDate(dayOffset: 0, hour: 20),
            location: CachedLocation(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437),
            hourlyForecasts: forecasts,
            dailySunEvents: [localSunEvents(dayOffset: 0), localSunEvents(dayOffset: 1)],
            dailyMoonInfo: [
                MoonInfo(phase: 0.1, phaseName: "Waxing Crescent", altitude: 10, illumination: 10, emoji: "🌒"),
                MoonInfo(phase: 0.9, phaseName: "Waxing Gibbous", altitude: 45, illumination: 90, emoji: "🌔")
            ],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let referenceDate = ISO8601DateFormatter().date(from: "2026-05-31T03:30:00Z")!

        let result = NightQualityAnalyzer.analyzeConditions(conditions, referenceDate: referenceDate)

        XCTAssertEqual(result?.nightStart, localSunEvents(dayOffset: 0).astronomicalTwilightEnd)
        XCTAssertEqual(result?.details.cloudCoverScore, 20)
    }
    
    // MARK: - Bimodal Night Tests
    
    private func createBimodalForecasts(cloudPattern: [(hour: Int, cloudCover: Int, humidity: Int, windSpeed: Double)], dayOffset: Int = 0) -> [HourlyForecast] {
        cloudPattern.map {
            HourlyForecast(
                time: createDate(hour: $0.hour, dayOffset: dayOffset),
                cloudCover: $0.cloudCover,
                humidity: $0.humidity,
                windSpeed: $0.windSpeed,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 5.0,
                visibility: 20000,
                lowCloudCover: nil
            )
        }
    }
    
    func testDegradingNight_ClearThenCloudy() {
        // First half clear, second half overcast → trend should be degrading
        let forecasts: [HourlyForecast] = [
            HourlyForecast(time: createDate(hour: 20, dayOffset: 0), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 21, dayOffset: 0), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 22, dayOffset: 0), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 23, dayOffset: 0), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 0, dayOffset: 1), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 1, dayOffset: 1), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 2, dayOffset: 1), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 3, dayOffset: 1), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
        ]
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertEqual(result.trend, .degrading)
        XCTAssertNotNil(result.firstHalfScore)
        XCTAssertNotNil(result.secondHalfScore)
        XCTAssertLessThan(result.firstHalfScore!, result.secondHalfScore!)
        XCTAssertTrue(result.summary.contains("degrade") || result.summary.contains("degrading"), "Summary should mention degrading conditions: \(result.summary)")
    }
    
    func testImprovingNight_CloudyThenClear() {
        // First half overcast, second half clear → trend should be improving
        let forecasts: [HourlyForecast] = [
            HourlyForecast(time: createDate(hour: 20, dayOffset: 0), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 21, dayOffset: 0), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 22, dayOffset: 0), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 23, dayOffset: 0), cloudCover: 100, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 0, dayOffset: 1), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 1, dayOffset: 1), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 2, dayOffset: 1), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 3, dayOffset: 1), cloudCover: 0, humidity: 60, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
        ]
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertEqual(result.trend, .improving)
        XCTAssertNotNil(result.firstHalfScore)
        XCTAssertNotNil(result.secondHalfScore)
        XCTAssertGreaterThan(result.firstHalfScore!, result.secondHalfScore!)
        XCTAssertTrue(result.summary.contains("improve") || result.summary.contains("improving"), "Summary should mention improving conditions: \(result.summary)")
    }
    
    func testStableNight_AllClear() {
        // All clear → trend should be stable
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 21, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 22, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 23, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 0, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 1, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 2, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 3, cloudCover: 0, humidity: 50, windSpeed: 2.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertEqual(result.trend, .stable)
    }
    
    func testStableNight_AllCloudy() {
        // All cloudy → trend should be stable
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 100, humidity: 70, windSpeed: 2.0),
            (hour: 21, cloudCover: 100, humidity: 70, windSpeed: 2.0),
            (hour: 22, cloudCover: 100, humidity: 70, windSpeed: 2.0),
            (hour: 23, cloudCover: 100, humidity: 70, windSpeed: 2.0),
            (hour: 0, cloudCover: 100, humidity: 70, windSpeed: 2.0),
            (hour: 1, cloudCover: 100, humidity: 70, windSpeed: 2.0),
            (hour: 2, cloudCover: 100, humidity: 70, windSpeed: 2.0),
            (hour: 3, cloudCover: 100, humidity: 70, windSpeed: 2.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertEqual(result.trend, .stable)
    }
    
    func testBimodalNight_FirstHalfBetterThanSecond() {
        // Clear first, cloudy second → first half score should be lower (better) than second
        let forecasts: [HourlyForecast] = [
            HourlyForecast(time: createDate(hour: 20, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 21, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 22, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 23, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 0, dayOffset: 1), cloudCover: 80, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 1, dayOffset: 1), cloudCover: 80, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 2, dayOffset: 1), cloudCover: 80, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 3, dayOffset: 1), cloudCover: 80, humidity: 70, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
        ]
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertNotNil(result.firstHalfScore)
        XCTAssertNotNil(result.secondHalfScore)
        XCTAssertLessThan(result.firstHalfScore!, result.secondHalfScore!, "First half should be better (lower score) than second half")
    }
    
    func testTrendThreshold_SimilarHalvesShouldBeStable() {
        // Identical conditions in both halves → should be stable
        let forecasts: [HourlyForecast] = [
            HourlyForecast(time: createDate(hour: 20, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 21, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 22, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 23, dayOffset: 0), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 0, dayOffset: 1), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 1, dayOffset: 1), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 2, dayOffset: 1), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
            HourlyForecast(time: createDate(hour: 3, dayOffset: 1), cloudCover: 0, humidity: 50, windSpeed: 2.0, windDirection: 180, temperature: 15.0, dewPoint: 5.0, visibility: 20000, lowCloudCover: nil),
        ]
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertEqual(result.trend, .stable, "Identical conditions between halves should result in stable trend")
    }
    
    func testFewHoursShouldDefaultToStable() {
        // Fewer than 4 hours → should default to stable with nil scores
        let forecasts = createForecasts(hours: [
            (hour: 20, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 21, cloudCover: 0, humidity: 50, windSpeed: 2.0),
            (hour: 22, cloudCover: 0, humidity: 50, windSpeed: 2.0),
        ])
        
        let result = analyze(forecasts: forecasts, moonIllumination: 10)
        
        XCTAssertEqual(result.trend, .stable)
    }
}
