import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

final class NightQualityAnalyzerHostTests: XCTestCase {
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
}
