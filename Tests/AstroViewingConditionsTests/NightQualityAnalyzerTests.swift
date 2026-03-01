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
        
        return NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            for: createDate(hour: 12, dayOffset: dayOffset)
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
        XCTAssertEqual(result.details.moonIlluminationAvg, 5)
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
        XCTAssertTrue(resultFullMoon.rating.rawValue > resultNewMoon.rating.rawValue)
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
        XCTAssertEqual(result.details.moonIlluminationAvg, 25)
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
}
