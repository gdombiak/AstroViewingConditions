import SharedCode
import SwiftUI
import WidgetKit

enum BestTargetsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case moonAndPlanets = "Moon & Planets"
    case deepSky = "Deep Sky"
    case doubleStars = "Double Stars"

    var id: Self { self }
}

enum BestTargetsScoreBand: String, CaseIterable, Identifiable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair / Marginal"

    var id: Self { self }

    func contains(score: Int) -> Bool {
        switch self {
        case .excellent: return score >= 80
        case .good: return (65...79).contains(score)
        case .fair: return (45...64).contains(score)
        }
    }
}

struct BestTargetsSection: Identifiable {
    let band: BestTargetsScoreBand
    let recommendations: [TargetRecommendation]

    var id: BestTargetsScoreBand { band }
}

struct BestTargetsListPresentation {
    static let dashboardLimit = 5
    static let minimumVisibleScore = 45

    let recommendations: [TargetRecommendation]

    var dashboardRecommendations: [TargetRecommendation] {
        Array(recommendations.prefix(Self.dashboardLimit))
    }

    var hasAdditionalTargets: Bool {
        visibleRecommendations.count > Self.dashboardLimit
    }

    func sections(for filter: BestTargetsFilter) -> [BestTargetsSection] {
        let filtered = visibleRecommendations.filter { recommendation in
            switch filter {
            case .all:
                return true
            case .moonAndPlanets:
                return recommendation.target.type == .moon || recommendation.target.type == .planet
            case .deepSky:
                return recommendation.target.type == .deepSky
                    && recommendation.target.deepSkyObjectType != .doubleStar
            case .doubleStars:
                return recommendation.target.deepSkyObjectType == .doubleStar
            }
        }

        return BestTargetsScoreBand.allCases.compactMap { band in
            let recommendations = filtered.filter { band.contains(score: $0.score) }
            return recommendations.isEmpty ? nil : BestTargetsSection(
                band: band,
                recommendations: recommendations
            )
        }
    }

    private var visibleRecommendations: [TargetRecommendation] {
        recommendations.filter { $0.score >= Self.minimumVisibleScore }
    }
}

@MainActor
@Observable
public class DashboardViewModel {
    // Services
    private let conditionsProvider: ConditionsProvider
    private let cacheService: CacheService
    private let targetRecommendationService: any TargetRecommendationProviding
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
        "ISS Passes"
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

    var currentBestTargetsPresentation: BestTargetsListPresentation {
        guard let conditions = viewingConditions,
              let sunEventsToday = currentSunEvents,
              let nightQuality = currentNightQuality,
              let moonInfo = currentMoonInfo else {
            return BestTargetsListPresentation(recommendations: [])
        }

        let context = TargetRecommendationContext(
            location: conditions.location,
            astronomicalNightStart: sunEventsToday.astronomicalNightStart,
            astronomicalNightEnd: sunEventsToday.astronomicalNightEnd(using: nextSunEvents),
            nightQuality: nightQuality,
            moonInfo: moonInfo
        )

        let recommendations = targetRecommendationService.recommendations(for: context, limit: 100)
        Self.logUITargetRecommendations(
            recommendations,
            selectedDay: selectedDay,
            context: context,
            timeZone: displayTimeZone
        )
        return BestTargetsListPresentation(recommendations: recommendations)
    }

    public var currentTargetRecommendations: [TargetRecommendation] {
        currentBestTargetsPresentation.dashboardRecommendations
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
        targetRecommendationService: any TargetRecommendationProviding = DefaultTargetRecommendationService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.apiKey = apiKey
        self.cacheService = cacheService
        self.conditionsProvider = conditionsProvider
        self.targetRecommendationService = targetRecommendationService
        self.now = now
    }

    private static func logUITargetRecommendations(
        _ recommendations: [TargetRecommendation],
        selectedDay: DaySelection,
        context: TargetRecommendationContext,
        timeZone: TimeZone?
    ) {
#if DEBUG
        /*
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone ?? .current

        let rows = recommendations.enumerated().map { index, recommendation in
            let window = recommendation.visibilityWindow
            let windowText = "\(formatter.string(from: window.start)) - \(formatter.string(from: window.end))"
            return "\(index + 1). \(recommendation.target.name) [\(recommendation.target.type.rawValue)] score=\(recommendation.score) best=\(formatter.string(from: window.bestTime)) window=\(windowText) summary=\"\(recommendation.summary)\""
        }

        debugPrint(
            """
            [BestTargetsUIInput]
            selectedDay: \(selectedDay.title)
            selectedDate: \(formatter.string(from: context.nightQuality.nightStart))
            timezone: \((timeZone ?? .current).identifier)
            count: \(recommendations.count)
            order:
            \(rows.joined(separator: "\n"))
            """
        )
        */
#endif
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
        defer { isLoading = false }
        
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
            return true
            
        } catch {
            let weatherTimedOut: Bool
            if case .timeout? = error as? WeatherError { weatherTimedOut = true } else { weatherTimedOut = false }
            if viewingConditions != nil, error is TimeoutError || weatherTimedOut {
                self.error = TimeoutError("Refresh timed out. Showing saved data.")
            } else {
                self.error = error
            }
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
