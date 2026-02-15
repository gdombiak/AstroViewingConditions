import SwiftUI

@MainActor
@Observable
public class DashboardViewModel {
    // Services
    private let weatherService = WeatherService()
    private let astronomyService = AstronomyService()
    private let issService = ISSService()
    
    // State
    public var viewingConditions: ViewingConditions?
    public var isLoading = false
    public var error: (any Error)?
    public var selectedDay: DaySelection = .today
    public var lastSuccessfulFetch: Date?
    
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
    
    public var currentSunEvents: SunEvents? {
        viewingConditions?.sunEvents
    }
    
    public var currentMoonInfo: MoonInfo? {
        viewingConditions?.moonInfo
    }
    
    public var currentISSPasses: [ISSPass] {
        viewingConditions?.issPasses ?? []
    }
    
    public var fogScore: FogScore? {
        viewingConditions?.fogScore
    }
    
    public init() {}
    
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
            
            // Calculate astronomical data
            let sunEvents = await astronomyService.calculateSunEvents(
                for: location,
                on: Date()
            )
            let moonInfo = await astronomyService.calculateMoonInfo(
                for: location,
                on: Date()
            )
            
            // Fetch ISS passes
            let issPasses = try await issService.fetchPasses(
                latitude: location.latitude,
                longitude: location.longitude,
                number: 10
            )
            
            let fogScore = FogCalculator.calculateCurrent(from: forecasts)
            
            viewingConditions = ViewingConditions(
                fetchedAt: Date(),
                location: location,
                hourlyForecasts: forecasts,
                sunEvents: sunEvents,
                moonInfo: moonInfo,
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
