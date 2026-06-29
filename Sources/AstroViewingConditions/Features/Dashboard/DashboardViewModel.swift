import SharedCode
import SwiftUI
import WidgetKit

@MainActor
@Observable
public class DashboardViewModel {
    // Services
    private let conditionsProvider: ConditionsProvider
    private let cacheService: CacheService
    private let now: () -> Date
    
    // State
    public var viewingConditions: ViewingConditions?
    public var isLoading = false
    public var error: (any Error)?
    public private(set) var issError: ISSError?
    public var selectedDay: DaySelection = .today
    public var lastSuccessfulFetch: Date?
    
    private var apiKey: String
    public private(set) var locationTimeZone: TimeZone?
    
    private static let staleThresholdSeconds: TimeInterval = 60 * 60 // 1 hour
    
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
        
        public static func title(for selection: DaySelection, referenceDate: Date, calendar: Calendar) -> String {
            let startOfDay = calendar.startOfDay(for: referenceDate)
            switch selection {
            case .today:
                return "Today"
            case .tomorrow:
                return "Tomorrow"
            case .dayAfter:
                let dayAfter = calendar.date(byAdding: .day, value: 2, to: startOfDay)
                    ?? startOfDay.addingTimeInterval(2 * 24 * 60 * 60)
                return DateFormatters.formatShortDate(dayAfter, in: calendar.timeZone)
            }
        }
    }
    
    public func titleForSelectedDay(_ selection: DaySelection) -> String {
        return DaySelection.title(for: selection, referenceDate: now(), calendar: locationCalendar)
    }
    
    public var isDataStale: Bool {
        guard let lastFetch = lastSuccessfulFetch else { return true }
        let timeStale = Date().timeIntervalSince(lastFetch) > Self.staleThresholdSeconds
        let dayRolledOver = !locationCalendar.isDate(lastFetch, inSameDayAs: Date())
        return timeStale || dayRolledOver
    }
    
    public var shouldFetchFreshConditions: Bool {
        isDataStale || viewingConditions == nil
    }
    
    public var currentHourlyForecasts: [HourlyForecast] {
        guard let conditions = viewingConditions else { return [] }
        
        let calendar = locationCalendar
        let startOfToday = calendar.startOfDay(for: now())
        guard let startOfSelectedDay = calendar.date(byAdding: .day, value: selectedDay.rawValue, to: startOfToday),
              let endOfSelectedDay = calendar.date(byAdding: .day, value: 1, to: startOfSelectedDay) else {
            return []
        }
        
        return conditions.hourlyForecasts.filter { forecast in
            forecast.time >= startOfSelectedDay && forecast.time < endOfSelectedDay
        }
    }
    
    public var currentHourForecast: HourlyForecast? {
        let now = now()
        let calendar = locationCalendar
        
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
        let index = conditionsDayIndex
        guard index >= 0, index < conditions.dailySunEvents.count else { return nil }
        return conditions.dailySunEvents[index]
    }
    
    public var nextSunEvents: SunEvents? {
        guard let conditions = viewingConditions else { return nil }
        let index = conditionsDayIndex + 1
        guard index >= 0, index < conditions.dailySunEvents.count else { return nil }
        return conditions.dailySunEvents[index]
    }
    
    public var currentMoonInfo: MoonInfo? {
        guard let conditions = viewingConditions else { return nil }
        let index = conditionsDayIndex
        guard index >= 0, index < conditions.dailyMoonInfo.count else { return nil }
        return conditions.dailyMoonInfo[index]
    }
    
    public var currentISSPasses: [ISSPass] {
        guard let conditions = viewingConditions,
              let sunset = currentSunEvents?.sunset,
              let followingSunrise = nextSunEvents?.sunrise else { return [] }

        return conditions.issPasses.filter {
            $0.riseTime >= sunset && $0.riseTime < followingSunrise
        }
    }

    public var issCardTitle: String {
        switch selectedDay {
        case .today:
            return "ISS Passes Tonight"
        case .tomorrow:
            return "ISS Passes Tomorrow Night"
        case .dayAfter:
            return "ISS Passes \(titleForSelectedDay(.dayAfter)) Night"
        }
    }

    public var issEmptyMessage: String {
        switch selectedDay {
        case .today:
            return "No visible ISS passes tonight"
        case .tomorrow:
            return "No visible ISS passes tomorrow night"
        case .dayAfter:
            return "No visible ISS passes on \(titleForSelectedDay(.dayAfter)) night"
        }
    }
    
    public var fogScore: FogScore? {
        viewingConditions?.fogScore
    }
    
    public var locationCalendar: Calendar {
        if let timeZone = displayTimeZone {
            return LocationTimeZoneResolver.calendar(for: timeZone)
        }
        return LocationTimeZoneResolver.calendar(for: TimeZone(secondsFromGMT: 0) ?? TimeZone.current)
    }
    
    public var displayTimeZone: TimeZone? {
        if let locationTimeZone {
            return locationTimeZone
        }
        if let identifier = viewingConditions?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        if let longitude = viewingConditions?.location.longitude {
            return LocationTimeZoneResolver.approximate(longitude: longitude)
        }
        return nil
    }
    
    public var currentNightQuality: NightQualityAssessment? {
        guard let conditions = viewingConditions,
              let sunEventsToday = currentSunEvents,
              let moonInfo = currentMoonInfo else {
            return nil
        }
        
        let calendar = locationCalendar
        let tomorrowIndex = conditionsDayIndex + 1
        let sunEventsTomorrow = tomorrowIndex >= 0 && tomorrowIndex < conditions.dailySunEvents.count
            ? conditions.dailySunEvents[tomorrowIndex]
            : nil
        guard let targetDate = calendar.date(byAdding: .day, value: selectedDay.rawValue, to: calendar.startOfDay(for: now())) else {
            return nil
        }
        
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
        guard let conditions = viewingConditions else { return [] }
        
        let calendar = locationCalendar
        let startOfToday = calendar.startOfDay(for: now())
        guard let startOfSelectedDay = calendar.date(byAdding: .day, value: selectedDay.rawValue, to: startOfToday),
              let endOfFollowingDay = calendar.date(byAdding: .day, value: 3, to: startOfSelectedDay) else {
            return []
        }
        
        return conditions.hourlyForecasts.filter { forecast in
            forecast.time >= startOfSelectedDay && forecast.time < endOfFollowingDay
        }
    }
    
    public init(
        apiKey: String = "",
        cacheService: CacheService = CacheService(),
        conditionsProvider: ConditionsProvider = ConditionsProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.apiKey = apiKey
        self.cacheService = cacheService
        self.conditionsProvider = conditionsProvider
        self.now = now
    }

    private var conditionsDayIndex: Int {
        guard let firstForecastTime = viewingConditions?.hourlyForecasts.first?.time else {
            return selectedDay.rawValue
        }
        let calendar = locationCalendar
        let firstDay = calendar.startOfDay(for: firstForecastTime)
        let today = calendar.startOfDay(for: now())
        let elapsedDays = calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0
        return elapsedDays + selectedDay.rawValue
    }
    
    public func updateAPIKey(_ newKey: String) {
        guard newKey != apiKey else { return }
        self.apiKey = newKey
    }
    
    @discardableResult
    private func loadConditions(for location: SavedLocation) async -> Bool {
        isLoading = true
        error = nil
        
        do {
            let result = try await conditionsProvider.fetchConditionsWithDiagnostics(
                for: CachedLocation(from: location),
                days: 4,
                apiKey: apiKey
            )
            let newConditions = result.conditions
            issError = result.issError
            if let identifier = newConditions.timeZoneIdentifier {
                locationTimeZone = TimeZone(identifier: identifier)
            } else {
                locationTimeZone = LocationTimeZoneResolver.approximate(longitude: newConditions.location.longitude)
            }
            viewingConditions = newConditions
            lastSuccessfulFetch = newConditions.fetchedAt
            isLoading = false
            return true
            
        } catch {
            self.error = error
            isLoading = false
            return false
        }
    }
    
    @discardableResult
    public func refresh(for location: SavedLocation) async -> Bool {
        guard await loadConditions(for: location) else {
            return false
        }

        await saveToCache()
        await publishCompanionConditions()
        return true
    }
    
    private func saveToCache() async {
        guard let conditions = viewingConditions else { return }
        await cacheService.saveAsync(conditions)
    }

    private func publishCompanionConditions() async {
        guard let conditions = viewingConditions else { return }
        let companionConditions = conditions.limitedToTonightCache()
        await AppGroupStorage.saveWidgetConditionsAsync(companionConditions)
        WatchConnectivityService.shared.sendConditionsToWatch(companionConditions)
        
        WidgetReloadService.shared.scheduleReload()
    }
    
    private func loadFromCache(matching location: CachedLocation) async -> Bool {
        guard let conditions = await cacheService.loadAsync(),
              conditionsMatch(conditions, location: location) else {
            return false
        }

        self.viewingConditions = conditions
        self.lastSuccessfulFetch = conditions.fetchedAt
        self.issError = nil

        return true
    }
    
    private func resolveTimeZone(for location: CachedLocation) async {
        locationTimeZone = await LocationTimeZoneResolver.resolve(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }
    
    public func loadConditionsIfNeeded(for location: SavedLocation) async {
        let cachedLocation = CachedLocation(from: location)
        await resolveTimeZone(for: cachedLocation)

        let loadedFromCache = await loadFromCache(matching: cachedLocation)
        if !loadedFromCache, !currentConditionsMatch(cachedLocation) {
            viewingConditions = nil
            lastSuccessfulFetch = nil
        }

        if shouldFetchFreshConditions {
            await refresh(for: location)
        }
    }

    private func currentConditionsMatch(_ location: CachedLocation) -> Bool {
        guard let viewingConditions else { return false }
        return conditionsMatch(viewingConditions, location: location)
    }

    private func conditionsMatch(_ conditions: ViewingConditions, location: CachedLocation) -> Bool {
        let tolerance = 0.0001
        let cachedLat = conditions.location.latitude
        let cachedLon = conditions.location.longitude

        guard cachedLat != 0, cachedLon != 0 else { return false }

        return abs(cachedLat - location.latitude) < tolerance &&
               abs(cachedLon - location.longitude) < tolerance
    }
}
