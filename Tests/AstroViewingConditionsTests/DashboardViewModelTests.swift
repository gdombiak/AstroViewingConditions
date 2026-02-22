import XCTest
import Foundation
@testable import AstroViewingConditions

@MainActor
final class DashboardViewModelTests: XCTestCase {
    
    func testScenario1_at11PM_tabLabelsMatchData() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var monday11PM = DateComponents()
        monday11PM.year = 2026
        monday11PM.month = 2
        monday11PM.day = 22
        monday11PM.hour = 23
        monday11PM.minute = 0
        let fetchDate = calendar.date(from: monday11PM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: fetchDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: fetchDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: fetchDate,
                    sunset: fetchDate.addingTimeInterval(43200),
                    civilTwilightBegin: fetchDate.addingTimeInterval(-1800),
                    civilTwilightEnd: fetchDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: fetchDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: fetchDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: fetchDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: fetchDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel()
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        let expectedDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: fetchDate))!
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        let expectedDay2Formatted = DateFormatters.shortDateFormatter.string(from: expectedDay2Date)
        
        XCTAssertEqual(actualDay2Title, expectedDay2Formatted, 
            "Tab 2 label should be based on fetch date, not current date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, expectedDay2Date,
                "Tab 2 forecasts should be for the day after tomorrow (based on fetch date)")
        }
    }
    
    func testScenario1_at1AM_noRefresh_tabLabelsAndDataShouldMatchFetchDate() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var monday11PM = DateComponents()
        monday11PM.year = 2026
        monday11PM.month = 2
        monday11PM.day = 22
        monday11PM.hour = 23
        monday11PM.minute = 0
        let fetchDate = calendar.date(from: monday11PM)!
        
        var tuesday1AM = DateComponents()
        tuesday1AM.year = 2026
        tuesday1AM.month = 2
        tuesday1AM.day = 23
        tuesday1AM.hour = 1
        tuesday1AM.minute = 0
        let currentDate = calendar.date(from: tuesday1AM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: fetchDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: fetchDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: fetchDate,
                    sunset: fetchDate.addingTimeInterval(43200),
                    civilTwilightBegin: fetchDate.addingTimeInterval(-1800),
                    civilTwilightEnd: fetchDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: fetchDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: fetchDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: fetchDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: fetchDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel()
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        let fetchStartOfDay0 = calendar.startOfDay(for: fetchDate)
        let expectedDay2Date = calendar.date(byAdding: .day, value: 2, to: fetchStartOfDay0)!
        let expectedDay2Formatted = DateFormatters.shortDateFormatter.string(from: expectedDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, expectedDay2Formatted, 
            "Tab 2 label should be based on fetch date (Mon Feb 22), not current date (Tue Feb 23)")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts from the fetch date")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, expectedDay2Date,
                "Tab 2 forecasts should be for day after tomorrow based on fetch date, not current date")
        }
        
        viewModel.selectedDay = .today
        let todayForecasts = viewModel.currentHourlyForecasts
        XCTAssertFalse(todayForecasts.isEmpty, "Tab 0 (Today) should have forecasts from fetch date")
        
        if let firstTodayForecast = todayForecasts.first {
            let forecastDate = calendar.startOfDay(for: firstTodayForecast.time)
            XCTAssertEqual(forecastDate, fetchStartOfDay0,
                "Tab 0 forecasts should be for the fetch date, not current date")
        }
    }
    
    func testScenario1_afterRefresh_labelsAndDataShouldMatchNewFetchDate() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var tuesday1AM = DateComponents()
        tuesday1AM.year = 2026
        tuesday1AM.month = 2
        tuesday1AM.day = 23
        tuesday1AM.hour = 1
        tuesday1AM.minute = 0
        let refreshDate = calendar.date(from: tuesday1AM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: refreshDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: refreshDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: refreshDate,
                    sunset: refreshDate.addingTimeInterval(43200),
                    civilTwilightBegin: refreshDate.addingTimeInterval(-1800),
                    civilTwilightEnd: refreshDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: refreshDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: refreshDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: refreshDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: refreshDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel()
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = refreshDate
        
        let refreshStartOfDay0 = calendar.startOfDay(for: refreshDate)
        let expectedDay2Date = calendar.date(byAdding: .day, value: 2, to: refreshStartOfDay0)!
        let expectedDay2Formatted = DateFormatters.shortDateFormatter.string(from: expectedDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, expectedDay2Formatted, 
            "Tab 2 label should be based on refresh date (Tue Feb 23)")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts after refresh")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, expectedDay2Date,
                "Tab 2 forecasts should be for day after tomorrow based on refresh date")
        }
        
        viewModel.selectedDay = .today
        let todayForecasts = viewModel.currentHourlyForecasts
        XCTAssertFalse(todayForecasts.isEmpty, "Tab 0 should have forecasts after refresh")
        
        if let firstTodayForecast = todayForecasts.first {
            let forecastDate = calendar.startOfDay(for: firstTodayForecast.time)
            XCTAssertEqual(forecastDate, refreshStartOfDay0,
                "Tab 0 forecasts should be for refresh date")
        }
    }
}
