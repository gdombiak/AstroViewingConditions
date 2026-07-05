import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

@MainActor
final class DashboardViewModelTests: XCTestCase {

    func testTimeoutStopsInitialLoadingAndShowsError() async {
        let viewModel = makeTimeoutViewModel()
        let location = SavedLocation(name: "Test", latitude: 45, longitude: -122)

        let succeeded = await viewModel.refresh(for: location)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.viewingConditions)
        XCTAssertEqual(viewModel.error?.localizedDescription, "Weather request timed out. Please try again.")
    }

    func testRefreshTimeoutKeepsExistingConditionsAndShowsSavedDataWarning() async {
        let viewModel = makeTimeoutViewModel()
        let location = SavedLocation(name: "Test", latitude: 45, longitude: -122)
        let existing = ViewingConditions(
            fetchedAt: Date(),
            location: CachedLocation(from: location),
            hourlyForecasts: [],
            dailySunEvents: [],
            dailyMoonInfo: [],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: [])
        )
        viewModel.viewingConditions = existing

        let succeeded = await viewModel.refresh(for: location)

        XCTAssertFalse(succeeded)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.viewingConditions?.fetchedAt, existing.fetchedAt)
        XCTAssertEqual(viewModel.error?.localizedDescription, "Refresh timed out. Showing saved data.")
    }

    private func makeTimeoutViewModel() -> DashboardViewModel {
        let weather = WeatherService(forecastTimeout: 0.01) { _ in
            await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
            throw CancellationError()
        }
        return DashboardViewModel(conditionsProvider: ConditionsProvider(weatherService: weather))
    }

    func testTargetSheetWidthOnlyExpandsForRegularSizeClass() {
        XCTAssertEqual(TargetSheetLayout.preferredWidth(for: .regular), 720)
        XCTAssertNil(TargetSheetLayout.preferredWidth(for: .compact))
        XCTAssertNil(TargetSheetLayout.preferredWidth(for: nil))
    }

    func testBestTargetsPoorConditionsNoteThreshold() {
        XCTAssertTrue(TonightsBestTargetsCard.showsPoorConditionsNote(for: 29))
        XCTAssertFalse(TonightsBestTargetsCard.showsPoorConditionsNote(for: 30))
        XCTAssertFalse(TonightsBestTargetsCard.showsPoorConditionsNote(for: nil))
    }

    func testBestTargetsDashboardCapsAtFiveAndShowsViewAllForAdditionalTargets() {
        let recommendations = [90, 85, 80, 75, 70, 65].enumerated().map { index, score in
            Self.makeRecommendation(id: "target-\(index)", name: "Target \(index)", score: score)
        }
        let presentation = BestTargetsListPresentation(recommendations: recommendations)

        XCTAssertEqual(presentation.dashboardRecommendations.count, 5)
        XCTAssertTrue(presentation.hasAdditionalTargets)
        XCTAssertTrue(TonightsBestTargetsCard.showsViewAll(hasAdditionalTargets: true))
        XCTAssertFalse(TonightsBestTargetsCard.showsViewAll(hasAdditionalTargets: false))
    }

    func testBestTargetsFullListGroupsScoreBandsAndHidesScoresBelow45() {
        let recommendations = [90, 80, 79, 65, 64, 45, 44].enumerated().map { index, score in
            Self.makeRecommendation(id: "target-\(index)", name: "Target \(index)", score: score)
        }
        let sections = BestTargetsListPresentation(recommendations: recommendations).sections(for: .all)

        XCTAssertEqual(sections.map(\.band), [.excellent, .good, .fair])
        XCTAssertEqual(sections.map { $0.recommendations.map(\.score) }, [
            [90, 80],
            [79, 65],
            [64, 45]
        ])
        XCTAssertFalse(sections.flatMap(\.recommendations).contains { $0.score < 45 })
    }

    func testCurrentTargetRecommendationsUseInjectedServiceOutput() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 29, hour: 12
        ))!
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let sunEvents = [
            Self.makeSunEvents(for: startOfDay, calendar: calendar),
            Self.makeSunEvents(for: tomorrow, calendar: calendar)
        ]
        let forecasts = (20...28).map { hour -> HourlyForecast in
            let date = calendar.date(
                bySettingHour: hour % 24,
                minute: 0,
                second: 0,
                of: hour >= 24 ? tomorrow : startOfDay
            )!
            return Self.makeForecast(at: date)
        }
        let expectedRecommendations = [
            Self.makeRecommendation(id: "saturn", name: "Saturn", score: 65),
            Self.makeRecommendation(id: "venus", name: "Venus", score: 62),
            Self.makeRecommendation(id: "jupiter", name: "Jupiter", score: 53),
            Self.makeRecommendation(id: "mars", name: "Mars", score: 45)
        ]
        let targetRecommendationService = FixedDashboardTargetRecommendationService(
            recommendations: expectedRecommendations
        )
        let viewModel = DashboardViewModel(
            targetRecommendationService: targetRecommendationService,
            now: { referenceDate }
        )
        viewModel.viewingConditions = ViewingConditions(
            fetchedAt: referenceDate,
            location: CachedLocation(name: "Cupertino", latitude: 37.323, longitude: -122.0322, elevation: 72),
            hourlyForecasts: forecasts,
            dailySunEvents: sunEvents,
            dailyMoonInfo: [
                MoonInfo(phase: 0.98, phaseName: "Full Moon", altitude: 20, illumination: 98, emoji: ""),
                MoonInfo(phase: 0.99, phaseName: "Full Moon", altitude: 18, illumination: 99, emoji: "")
            ],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )

        let recommendations = viewModel.currentTargetRecommendations

        XCTAssertEqual(recommendations.map(\.target.name), ["Saturn", "Venus", "Jupiter", "Mars"])
        XCTAssertEqual(recommendations.map(\.score), [65, 62, 53, 45])
        XCTAssertEqual(targetRecommendationService.requestedLimits, [100])
    }

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

    private static func makeRecommendation(
        id: String,
        name: String,
        score: Int
    ) -> TargetRecommendation {
        let start = Date(timeIntervalSince1970: 1_782_790_000)
        let end = start.addingTimeInterval(3_600)
        return TargetRecommendation(
            target: ObservableTarget(
                id: id,
                name: name,
                type: .planet,
                preferredEquipment: .nakedEye,
                difficulty: 0.2
            ),
            score: score,
            visibilityWindow: TargetVisibilityWindow(
                start: start,
                end: end,
                bestTime: start.addingTimeInterval(1_800),
                maxAltitude: 35,
                direction: "SE"
            ),
            reasons: [.convenientPlanetWindow],
            summary: "\(name) summary"
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

private final class FixedDashboardTargetRecommendationService: TargetRecommendationProviding, @unchecked Sendable {
    let recommendations: [TargetRecommendation]
    private(set) var requestedLimits: [Int] = []

    init(recommendations: [TargetRecommendation]) {
        self.recommendations = recommendations
    }

    func recommendations(
        for context: TargetRecommendationContext,
        limit: Int
    ) -> [TargetRecommendation] {
        requestedLimits.append(limit)
        return Array(recommendations.prefix(limit))
    }
}
