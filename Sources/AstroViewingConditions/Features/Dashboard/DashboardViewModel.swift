import SwiftUI

@MainActor
@Observable
public class DashboardViewModel {
    // Services
    private let weatherService = WeatherService()
    private let astronomyService = AstronomyService()
    private var issService: ISSService?
    
    // State
    public var viewingConditions: ViewingConditions?
    public var isLoading = false
    public var error: (any Error)?
    public var selectedDay: DaySelection = .today
    public var lastSuccessfulFetch: Date?
    
    private let apiKey: String
    
    public var hasISSConfigured: Bool {
        !apiKey.isEmpty
    }
    
    public enum DaySelection: Int, CaseIterable, Sendable {
        case today = 0
        case tomorrow = 1
        case dayAfter = 2
        
        public var title: String {
            switch self {
            case .today:
                return "Today"
            case .tomorrow:
                return "Tomorrow"
            case .dayAfter:
                return DateFormatters.shortDateFormatter.string(from: Date().addingTimeInterval(2 * 24 * 60 * 60))
            }
        }
    }
    
    public var isDataStale: Bool {
        guard let lastFetch = lastSuccessfulFetch else { return true }
        return Date().timeIntervalSince(lastFetch) > 1800 // 30 minutes
    }
    
    public var currentHourlyForecasts: [HourlyForecast] {
        guard let conditions = viewingConditions else { return [] }
        
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfSelectedDay = calendar.date(byAdding: .day, value: selectedDay.rawValue, to: startOfToday)!
        let endOfSelectedDay = calendar.date(byAdding: .day, value: 1, to: startOfSelectedDay)!
        
        return conditions.hourlyForecasts.filter { forecast in
            forecast.time >= startOfSelectedDay && forecast.time < endOfSelectedDay
        }
    }
    
    public var currentHourForecast: HourlyForecast? {
        let now = Date()
        let calendar = Calendar.current
        
        // Find the forecast for the current hour
        return currentHourlyForecasts.first { forecast in
            let forecastHour = calendar.component(.hour, from: forecast.time)
            let currentHour = calendar.component(.hour, from: now)
            let isSameDay = calendar.isDate(forecast.time, inSameDayAs: now)
            return isSameDay && forecastHour == currentHour
        } ?? currentHourlyForecasts.first
    }
    
    public var currentSunEvents: SunEvents? {
        guard let conditions = viewingConditions else { return nil }
        let index = selectedDay.rawValue
        guard index < conditions.dailySunEvents.count else { return nil }
        return conditions.dailySunEvents[index]
    }
    
    public var currentMoonInfo: MoonInfo? {
        guard let conditions = viewingConditions else { return nil }
        let index = selectedDay.rawValue
        guard index < conditions.dailyMoonInfo.count else { return nil }
        return conditions.dailyMoonInfo[index]
    }
    
    public var currentISSPasses: [ISSPass] {
        viewingConditions?.issPasses ?? []
    }
    
    public var fogScore: FogScore? {
        viewingConditions?.fogScore
    }
    
    public init(apiKey: String = "") {
        self.apiKey = apiKey
        if !apiKey.isEmpty {
            self.issService = ISSService(apiKey: apiKey)
        }
    }
    
    public func loadConditions(for location: SavedLocation) async {
        isLoading = true
        error = nil
        
        do {
            // Fetch weather data
            let forecasts = try await weatherService.fetchForecast(
                latitude: location.latitude,
                longitude: location.longitude,
                days: 3
            )
            
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            
            var dailySunEvents: [SunEvents] = []
            var dailyMoonInfo: [MoonInfo] = []
            
            for dayOffset in 0..<3 {
                let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday)!
                let sunEvents = await astronomyService.calculateSunEvents(
                    for: location,
                    on: date
                )
                let moonInfo = await astronomyService.calculateMoonInfo(
                    for: location,
                    on: date
                )
                dailySunEvents.append(sunEvents)
                dailyMoonInfo.append(moonInfo)
            }
            
            // Fetch ISS passes (only if API key is configured)
            let issPasses: [ISSPass]
            if let service = issService {
                issPasses = try await service.fetchPasses(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
            } else {
                issPasses = []
            }
            
            let fogScore = FogCalculator.calculateCurrent(from: forecasts)
            
            viewingConditions = ViewingConditions(
                fetchedAt: Date(),
                location: location,
                hourlyForecasts: forecasts,
                dailySunEvents: dailySunEvents,
                dailyMoonInfo: dailyMoonInfo,
                issPasses: issPasses,
                fogScore: fogScore
            )
            
            lastSuccessfulFetch = Date()
            
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    public func refresh(for location: SavedLocation) async {
        await loadConditions(for: location)
    }
}
