import SharedCode
import CoreLocation
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
protocol DashboardCurrentLocationProviding: AnyObject, Sendable {
    var authorizationStatus: CLAuthorizationStatus { get }
    var isAuthorized: Bool { get }

    func requestAuthorization()
    func resolveCurrentLocation() async throws -> CachedLocation
}

enum DashboardCurrentLocationResolutionResult: Equatable {
    case unchanged
    case resolvedSelectionUpdated
}

/// App-scoped, in-memory GPS state. ContentView owns this for the lifetime of
/// the running app, so it survives Field Mode's dashboard recreation but not a
/// new process launch.
@MainActor
@Observable
final class DashboardLocationSession {
    private final class ResolutionOperation {
        let generation: Int
        let task: Task<CachedLocation, Error>

        init(generation: Int, provider: any DashboardCurrentLocationProviding) {
            self.generation = generation
            task = Task { @MainActor in
                try await provider.resolveCurrentLocation()
            }
        }
    }

    var currentLocation: CachedLocation?
    private var resolutionOperation: ResolutionOperation?
    private var resolutionGeneration = 0

    func resolveCurrentLocation(
        using provider: any DashboardCurrentLocationProviding
    ) async throws -> CachedLocation? {
        if let currentLocation {
            return currentLocation
        }

        let requestGeneration = resolutionGeneration
        let operation: ResolutionOperation
        if let resolutionOperation,
           resolutionOperation.generation == requestGeneration {
            operation = resolutionOperation
        } else {
            operation = ResolutionOperation(generation: requestGeneration, provider: provider)
            resolutionOperation = operation
        }

        do {
            let resolved = try await operation.task.value
            if resolutionOperation === operation {
                resolutionOperation = nil
            }
            guard operation.generation == resolutionGeneration else { return nil }
            currentLocation = resolved
            return resolved
        } catch {
            if resolutionOperation === operation {
                resolutionOperation = nil
            }
            guard operation.generation == resolutionGeneration else { return nil }
            throw error
        }
    }

    func invalidateCurrentLocation() {
        resolutionGeneration += 1
        currentLocation = nil
    }
}

/// Owns the dashboard's explicit location selection and is the only route to
/// device-location resolution. Keeping this state separate from the view's
/// lifecycle makes repeated SwiftUI tasks harmless.
@MainActor
@Observable
final class DashboardLocationLoader {
    var selectedLocation: SelectedLocation
    var currentLocation: CachedLocation? { locationSession.currentLocation }

    private let provider: any DashboardCurrentLocationProviding
    private let saveSelection: (SelectedLocation) -> Void
    private let hadPersistedSelection: Bool
    private let locationSession: DashboardLocationSession
    private var selectionGeneration = 0
    private var internallyResolvedSelection: SelectedLocation?

    init(
        persistedSelection: SelectedLocation?,
        provider: any DashboardCurrentLocationProviding,
        saveSelection: @escaping (SelectedLocation) -> Void,
        locationSession: DashboardLocationSession = DashboardLocationSession()
    ) {
        let selection = persistedSelection ?? Self.currentLocationSelection
        self.selectedLocation = selection
        self.provider = provider
        self.saveSelection = saveSelection
        self.hadPersistedSelection = persistedSelection != nil
        self.locationSession = locationSession
    }

    func restoreSelection(using savedLocations: [CachedLocation]) {
        let restored = Self.validatedSelection(selectedLocation, savedLocations: savedLocations)
        if restored != selectedLocation || !hadPersistedSelection {
            applySelection(restored)
            saveSelection(restored)
        }
    }

    func repairSelectionIfNeeded(using savedLocations: [CachedLocation]) {
        let repaired = Self.validatedSelection(selectedLocation, savedLocations: savedLocations)
        guard repaired != selectedLocation else { return }
        applySelection(repaired)
        saveSelection(repaired)
    }

    /// Records an intentional user selection. Returning from a fixed location
    /// to Current Location discards any runtime GPS result so it is resolved
    /// afresh; rehydration uses the initializer instead and keeps its cache.
    func select(_ selection: SelectedLocation) {
        guard !(selectedLocation.source == .currentGPS && selection.source == .currentGPS) else {
            return
        }
        guard selection != selectedLocation else { return }

        applySelection(selection)
    }

    func resolveCurrentLocationIfNeeded() async throws -> DashboardCurrentLocationResolutionResult {
        guard selectedLocation.source == .currentGPS, currentLocation == nil else { return .unchanged }

        guard provider.isAuthorized else {
            provider.requestAuthorization()
            return .unchanged
        }

        let requestGeneration = selectionGeneration

        do {
            guard let resolved = try await locationSession.resolveCurrentLocation(using: provider) else {
                if requestGeneration == selectionGeneration,
                   selectedLocation.source == .currentGPS,
                   currentLocation == nil {
                    return try await resolveCurrentLocationIfNeeded()
                }
                return .unchanged
            }

            guard requestGeneration == selectionGeneration,
                  selectedLocation.source == .currentGPS else {
                if selectedLocation.source == .currentGPS, currentLocation == nil {
                    return try await resolveCurrentLocationIfNeeded()
                }
                return .unchanged
            }

            let selection = SelectedLocation(
                source: .currentGPS,
                name: resolved.name,
                latitude: resolved.latitude,
                longitude: resolved.longitude
            )
            selectedLocation = selection
            internallyResolvedSelection = selection
            saveSelection(selection)
            return .resolvedSelectionUpdated
        } catch {
            guard requestGeneration == selectionGeneration,
                  selectedLocation.source == .currentGPS else {
                return .unchanged
            }
            throw error
        }
    }

    func consumeInternallyResolvedSelectionUpdate(matching selection: SelectedLocation) -> Bool {
        guard internallyResolvedSelection == selection else { return false }
        internallyResolvedSelection = nil
        return true
    }

    var authorizationStatus: CLAuthorizationStatus {
        provider.authorizationStatus
    }

    var isAuthorized: Bool {
        provider.isAuthorized
    }

    func requestAuthorization() {
        guard selectedLocation.source == .currentGPS else { return }
        provider.requestAuthorization()
    }

    var activeLocation: CachedLocation? {
        switch selectedLocation.source {
        case .currentGPS:
            return currentLocation
        case .saved:
            return CachedLocation(
                id: selectedLocation.id,
                name: selectedLocation.name,
                latitude: selectedLocation.latitude,
                longitude: selectedLocation.longitude
            )
        }
    }

    private static var currentLocationSelection: SelectedLocation {
        SelectedLocation(
            source: .currentGPS,
            name: "My Current Location",
            latitude: 0,
            longitude: 0
        )
    }

    private static func validatedSelection(
        _ selection: SelectedLocation,
        savedLocations: [CachedLocation]
    ) -> SelectedLocation {
        guard selection.source == .saved else { return selection }
        guard let id = selection.id,
              let savedLocation = savedLocations.first(where: { $0.id == id }) else {
            return currentLocationSelection
        }

        return SelectedLocation(
            source: .saved,
            id: savedLocation.id,
            name: savedLocation.name,
            latitude: savedLocation.latitude,
            longitude: savedLocation.longitude
        )
    }

    private func applySelection(_ selection: SelectedLocation) {
        let isFixedToCurrentLocation = selectedLocation.source == .saved
            && selection.source == .currentGPS
        selectionGeneration += 1
        internallyResolvedSelection = nil
        selectedLocation = isFixedToCurrentLocation ? Self.currentLocationSelection : selection
        if isFixedToCurrentLocation {
            locationSession.invalidateCurrentLocation()
        }
    }
}

@MainActor
@Observable
public class DashboardViewModel {
    private struct ConditionsLoadKey: Hashable {
        let id: UUID?
        let latitude: Double
        let longitude: Double
        let elevation: Double?

        init(location: CachedLocation) {
            id = location.id
            latitude = location.latitude
            longitude = location.longitude
            elevation = location.elevation
        }
    }

    private final class ConditionsLoadOperation {
        var task: Task<Void, Never>!
    }

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
    private var conditionsLoadOperations: [ConditionsLoadKey: ConditionsLoadOperation] = [:]
    
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
    private func loadConditions(for location: CachedLocation) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let result = try await conditionsProvider.fetchConditionsWithDiagnostics(
                for: location,
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
        await refresh(for: CachedLocation(from: location))
    }

    @discardableResult
    public func refresh(for location: CachedLocation) async -> Bool {
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
        await loadConditionsIfNeeded(for: CachedLocation(from: location))
    }

    public func loadConditionsIfNeeded(for location: CachedLocation) async {
        let key = ConditionsLoadKey(location: location)
        if let operation = conditionsLoadOperations[key] {
            await operation.task.value
            return
        }

        let operation = ConditionsLoadOperation()
        conditionsLoadOperations[key] = operation
        operation.task = Task { @MainActor [weak self] in
            await self?.loadConditionsIfNeededUncoalesced(for: location)
        }
        await operation.task.value
        if conditionsLoadOperations[key] === operation {
            conditionsLoadOperations[key] = nil
        }
    }

    private func loadConditionsIfNeededUncoalesced(for location: CachedLocation) async {
        await resolveTimeZone(for: location)

        let loadedFromCache = await loadFromCache(matching: location)
        if !loadedFromCache, !currentConditionsMatch(location) {
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
