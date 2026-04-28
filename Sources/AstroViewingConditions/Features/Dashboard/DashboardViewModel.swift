import SharedCode
import SwiftUI
import WidgetKit

@MainActor
@Observable
public class DashboardViewModel {
    // Services
    private let weatherService = WeatherService()
    private let astronomyService = AstronomyService()
    private var issService: ISSService?
    private let cacheService: CacheService
    
    // State
    public var viewingConditions: ViewingConditions?
    public var isLoading = false
    public var error: (any Error)?
    public var selectedDay: DaySelection = .today
    public var lastSuccessfulFetch: Date?
    
    private var apiKey: String
    private var locationTimeZone: TimeZone?
    
    private static let staleThresholdSeconds: TimeInterval = 6 * 60 * 60 // 6 hours
    
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
                return "Day After"
            }
        }
        
        public static func title(for selection: DaySelection, referenceDate: Date) -> String {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: referenceDate)
            switch selection {
            case .today:
                return "Today"
            case .tomorrow:
                return "Tomorrow"
            case .dayAfter:
                let dayAfter = calendar.date(byAdding: .day, value: 2, to: startOfDay)!
                return DateFormatters.shortDateFormatter.string(from: dayAfter)
            }
        }
    }
    
    public func titleForSelectedDay(_ selection: DaySelection) -> String {
        return DaySelection.title(for: selection, referenceDate: Date())
    }
    
    public var isDataStale: Bool {
        guard let lastFetch = lastSuccessfulFetch else { return true }
        let timeStale = Date().timeIntervalSince(lastFetch) > Self.staleThresholdSeconds
        let dayRolledOver = !Calendar.current.isDate(lastFetch, inSameDayAs: Date())
        return timeStale || dayRolledOver
    }
    
    public var shouldFetchFreshConditions: Bool {
        isDataStale || viewingConditions == nil
    }
    
    public var currentHourlyForecasts: [HourlyForecast] {
        guard let conditions = viewingConditions,
              !conditions.hourlyForecasts.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let firstForecastTime = conditions.hourlyForecasts.first!.time
        let startOfFirstDay = calendar.startOfDay(for: firstForecastTime)
        let startOfSelectedDay = calendar.date(byAdding: .day, value: selectedDay.rawValue, to: startOfFirstDay)!
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
    
    private var locationCalendar: Calendar {
        if let tz = locationTimeZone {
            return LocationTimeZoneResolver.calendar(for: tz)
        }
        return Calendar.current
    }
    
    public var currentNightQuality: NightQualityAssessment? {
        guard let conditions = viewingConditions,
              let sunEventsToday = currentSunEvents,
              let moonInfo = currentMoonInfo else {
            return nil
        }
        
        let calendar = locationCalendar
        let tomorrowIndex = selectedDay.rawValue + 1
        let sunEventsTomorrow = tomorrowIndex < conditions.dailySunEvents.count ? conditions.dailySunEvents[tomorrowIndex] : nil
        let targetDate = calendar.date(byAdding: .day, value: selectedDay.rawValue, to: calendar.startOfDay(for: Date()))!
        
        let nightForecasts = nightTimeForecasts
        
        return NightQualityAnalyzer.analyzeNight(
            forecasts: nightForecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            for: targetDate,
            calendar: calendar
        )
    }
    
    private var nightTimeForecasts: [HourlyForecast] {
        guard let conditions = viewingConditions,
              !conditions.hourlyForecasts.isEmpty else { return [] }
        
        let calendar = locationCalendar
        let firstForecastTime = conditions.hourlyForecasts.first!.time
        let startOfFirstDay = calendar.startOfDay(for: firstForecastTime)
        let startOfSelectedDay = calendar.date(byAdding: .day, value: selectedDay.rawValue, to: startOfFirstDay)!
        let endOfFollowingDay = calendar.date(byAdding: .day, value: 3, to: startOfSelectedDay)!
        
        return conditions.hourlyForecasts.filter { forecast in
            forecast.time >= startOfSelectedDay && forecast.time < endOfFollowingDay
        }
    }
    
    public init(apiKey: String = "", cacheService: CacheService = CacheService()) {
        self.apiKey = apiKey
        self.cacheService = cacheService
        if !apiKey.isEmpty {
            self.issService = ISSService(apiKey: apiKey)
        }
    }
    
    public func updateAPIKey(_ newKey: String) {
        guard newKey != apiKey else { return }
        self.apiKey = newKey
        if !newKey.isEmpty {
            self.issService = ISSService(apiKey: newKey)
        } else {
            self.issService = nil
        }
    }
    
    public func loadConditions(for location: SavedLocation) async {
        isLoading = true
        error = nil
        
        let latitude = location.latitude
        let longitude = location.longitude
        let locationName = location.name
        let locationElevation = location.elevation
        
        do {
            // Resolve timezone for the location being viewed
            let tz = await LocationTimeZoneResolver.resolve(latitude: latitude, longitude: longitude)
            locationTimeZone = tz
            let calendar = LocationTimeZoneResolver.calendar(for: tz)
            
            // Fetch weather data
            let forecasts = try await weatherService.fetchForecast(
                latitude: latitude,
                longitude: longitude,
                days: 4
            )
            
            let startOfToday = calendar.startOfDay(for: Date())
            
            var dailySunEvents: [SunEvents] = []
            var dailyMoonInfo: [MoonInfo] = []
            
            for dayOffset in 0..<4 {
                let date = calendar.date(byAdding: Calendar.Component.day, value: dayOffset, to: startOfToday)!
                let sunEvents = await astronomyService.calculateSunEvents(
                    latitude: latitude,
                    longitude: longitude,
                    on: date
                )
                let moonInfo = await astronomyService.calculateMoonInfo(
                    latitude: latitude,
                    longitude: longitude,
                    on: date
                )
                dailySunEvents.append(sunEvents)
                dailyMoonInfo.append(moonInfo)
            }
            
            // Fetch ISS passes (only if API key is configured)
            let issPasses: [ISSPass]
            if let service = issService {
                issPasses = try await service.fetchPasses(
                    latitude: latitude,
                    longitude: longitude
                )
            } else {
                issPasses = []
            }
            
            let fogScore = FogCalculator.calculateCurrent(from: forecasts)
            
            let cachedLocation = CachedLocation(
                name: locationName,
                latitude: latitude,
                longitude: longitude,
                elevation: locationElevation
            )
            
            let newConditions = ViewingConditions(
                fetchedAt: Date(),
                location: cachedLocation,
                hourlyForecasts: forecasts,
                dailySunEvents: dailySunEvents,
                dailyMoonInfo: dailyMoonInfo,
                issPasses: issPasses,
                fogScore: fogScore
            )
            viewingConditions = newConditions
            lastSuccessfulFetch = Date()
            
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    public func refresh(for location: SavedLocation) async {
        await loadConditions(for: location)
    }
    
    public func saveToCache() {
        guard let conditions = viewingConditions else { return }
        cacheService.save(conditions)
        AppGroupStorage.saveWidgetConditions(conditions)
        WatchConnectivityService.shared.sendConditionsToWatch(conditions)
        
        WidgetReloadService.shared.scheduleReload()
    }
    
    public func loadFromCache() -> Bool {
        guard let conditions = cacheService.load() else {
            return false
        }
        
        self.viewingConditions = conditions
        self.lastSuccessfulFetch = conditions.fetchedAt
        
        return true
    }
    
    public func loadConditionsIfNeeded(for location: SavedLocation) async {
        if let widgetConditions = AppGroupStorage.loadWidgetConditions(),
           widgetConditions.fetchedAt.timeIntervalSinceNow > -3600,
           widgetConditions.location.latitude == location.latitude,
           widgetConditions.location.longitude == location.longitude {
            self.viewingConditions = widgetConditions
            self.lastSuccessfulFetch = widgetConditions.fetchedAt
            return
        }

        let loadedFromCache = loadFromCache()
        let cachedLocation = CachedLocation(from: location)
        let cachedLocationMatches = cacheService.cachedLocationMatches(cachedLocation)

        if shouldFetchFreshConditions || !cachedLocationMatches {
            await loadConditions(for: location)
            saveToCache()
        } else if !loadedFromCache {
            viewingConditions = nil
            await loadConditions(for: location)
            saveToCache()
        }
    }
}
