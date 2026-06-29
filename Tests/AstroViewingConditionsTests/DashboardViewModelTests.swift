import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

@MainActor
final class DashboardViewModelTests: XCTestCase {

    func testCurrentISSPassesFollowSelectedLocationDay() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 28, hour: 12
        ))!
        let startOfFirstDay = calendar.startOfDay(for: firstDay)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfFirstDay)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: startOfFirstDay)!
        let fourthDay = calendar.date(byAdding: .day, value: 3, to: startOfFirstDay)!
        let sunEvents = [startOfFirstDay, tomorrow, dayAfter, fourthDay].map {
            Self.makeSunEvents(for: $0, calendar: calendar)
        }
        let tonightBeforeMidnight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: startOfFirstDay
        )!
        let tonightAfterMidnight = calendar.date(
            bySettingHour: 2, minute: 28, second: 0, of: tomorrow
        )!
        let tomorrowNight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: tomorrow
        )!
        let dayAfterNight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: dayAfter
        )!
        let conditions = ViewingConditions(
            fetchedAt: firstDay,
            location: CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
            hourlyForecasts: [Self.makeForecast(at: firstDay)],
            dailySunEvents: sunEvents,
            dailyMoonInfo: [],
            issPasses: [
                ISSPass(riseTime: tonightBeforeMidnight, duration: 300, maxElevation: 30),
                ISSPass(riseTime: tonightAfterMidnight, duration: 300, maxElevation: 35),
                ISSPass(riseTime: tomorrowNight, duration: 300, maxElevation: 40),
                ISSPass(riseTime: dayAfterNight, duration: 300, maxElevation: 50)
            ],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
        let viewModel = DashboardViewModel(now: { firstDay })
        viewModel.viewingConditions = conditions

        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [30, 35])
        viewModel.selectedDay = .tomorrow
        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [40])
        viewModel.selectedDay = .dayAfter
        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [50])
    }

    private static func makeForecast(at date: Date) -> HourlyForecast {
        HourlyForecast(
            time: date,
            cloudCover: 0,
            humidity: 0,
            windSpeed: 0,
            windDirection: 0,
            temperature: 0
        )
    }

    private static func makeSunEvents(for date: Date, calendar: Calendar) -> SunEvents {
        let sunrise = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date)!
        let sunset = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: date)!
        return SunEvents(
            sunrise: sunrise,
            sunset: sunset,
            civilTwilightBegin: sunrise.addingTimeInterval(-1_800),
            civilTwilightEnd: sunset.addingTimeInterval(1_800),
            nauticalTwilightBegin: sunrise.addingTimeInterval(-3_600),
            nauticalTwilightEnd: sunset.addingTimeInterval(3_600),
            astronomicalTwilightBegin: sunrise.addingTimeInterval(-5_400),
            astronomicalTwilightEnd: sunset.addingTimeInterval(5_400)
        )
    }
    
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
        
        let viewModel = DashboardViewModel(now: { fetchDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: fetchDate))!
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not fetch date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts")
        
        // Forecasts are based on fetch date, not current date
        let fetchDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: fetchDate))!
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, fetchDay2Date,
                "Tab 2 forecasts should be for the day after tomorrow based on fetch date")
        }
    }
    
    func testAt1AMStaleCacheTabsRemainAnchoredToCurrentDate() {
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
        
        let viewModel = DashboardViewModel(now: { currentDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        // Tab labels use current date, not fetch date
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: currentDate))!
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not fetch date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts for two days after the current date")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: currentDate))!,
                "Tab 2 forecasts should be based on the current date, not a stale cache date")
        }
        
        viewModel.selectedDay = .today
        let todayForecasts = viewModel.currentHourlyForecasts
        XCTAssertFalse(todayForecasts.isEmpty, "Tab 0 (Today) should use the actual current day")
        
        if let firstTodayForecast = todayForecasts.first {
            let forecastDate = calendar.startOfDay(for: firstTodayForecast.time)
            XCTAssertEqual(forecastDate, calendar.startOfDay(for: currentDate),
                "Tab 0 forecasts should not remain pinned to a stale cache's first day")
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
        
        let viewModel = DashboardViewModel(now: { refreshDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = refreshDate
        
        // Tab labels use current date, not refresh date
        let refreshStartOfDay0 = calendar.startOfDay(for: refreshDate)
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: refreshDate))!
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not refresh date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts after refresh")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, calendar.date(byAdding: .day, value: 2, to: refreshStartOfDay0)!,
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
