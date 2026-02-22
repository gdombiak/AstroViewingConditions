import SwiftUI

private enum StorageKeys {
    static let cachedConditions = "cachedViewingConditions"
    static let cachedLocationLat = "cachedLocationLatitude"
    static let cachedLocationLon = "cachedLocationLongitude"
}

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
    
    private var apiKey: String
    private let userDefaults = UserDefaults.standard
    
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
            switch selection {
            case .today:
                return "Today"
            case .tomorrow:
                return "Tomorrow"
            case .dayAfter:
                return DateFormatters.shortDateFormatter.string(from: referenceDate.addingTimeInterval(2 * 24 * 60 * 60))
            }
        }
    }
    
    public func titleForSelectedDay(_ selection: DaySelection) -> String {
        guard let conditions = viewingConditions else {
            return selection.title
        }
        let referenceDate = conditions.fetchedAt
        return DaySelection.title(for: selection, referenceDate: referenceDate)
    }
    
    public var isDataStale: Bool {
        guard let lastFetch = lastSuccessfulFetch else { return true }
        return Date().timeIntervalSince(lastFetch) > Self.staleThresholdSeconds
    }
    
    public var shouldFetchFreshConditions: Bool {
        isDataStale || viewingConditions == nil
    }
    
    public var currentHourlyForecasts: [HourlyForecast] {
        guard let conditions = viewingConditions else { return [] }
        
        let calendar = Calendar.current
        let fetchDate = conditions.fetchedAt
        let startOfToday = calendar.startOfDay(for: fetchDate)
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
            // Fetch weather data
            let forecasts = try await weatherService.fetchForecast(
                latitude: latitude,
                longitude: longitude,
                days: 3
            )
            
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            
            var dailySunEvents: [SunEvents] = []
            var dailyMoonInfo: [MoonInfo] = []
            
            for dayOffset in 0..<3 {
                let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday)!
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
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(conditions)
            userDefaults.set(data, forKey: StorageKeys.cachedConditions)
            userDefaults.set(conditions.location.latitude, forKey: StorageKeys.cachedLocationLat)
            userDefaults.set(conditions.location.longitude, forKey: StorageKeys.cachedLocationLon)
        } catch {
            print("Failed to cache conditions: \(error)")
        }
    }
    
    public func loadFromCache() -> Bool {
        guard let data = userDefaults.data(forKey: StorageKeys.cachedConditions) else {
            return false
        }
        
        do {
            let decoder = JSONDecoder()
            let conditions = try decoder.decode(ViewingConditions.self, from: data)
            
            self.viewingConditions = conditions
            self.lastSuccessfulFetch = conditions.fetchedAt
            
            return true
        } catch {
            return false
        }
    }
    
    public func loadConditionsIfNeeded(for location: SavedLocation) async {
        let loadedFromCache = loadFromCache()
        
        // Check if cached location matches the requested location
        let cachedLocationMatches = viewingConditions?.location.name == location.name
        
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
