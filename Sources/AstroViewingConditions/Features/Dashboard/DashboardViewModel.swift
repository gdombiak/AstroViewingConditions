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
        TargetScoreCategory.resolve(score) == category
    }

    private var category: TargetScoreCategory {
        switch self {
        case .excellent: .excellent
        case .good: .good
        case .fair: .fair
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
/// the running app, but it does not survive a new process launch.
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
    private let conditionsRepository: SharedConditionsRepository
    private let targetRecommendationService: any TargetRecommendationProviding
    private let observingQualityEnvironment: any ObservingQualityEnvironment
    private let now: @Sendable () -> Date
    
    // State
    public var viewingConditions: ViewingConditions?
    public var isLoading = false
    public var error: (any Error)?
    public private(set) var issError: ISSError?
    public var selectedDay: DaySelection = .today
    /// Mirror of process light-pollution readiness (set by composition root, not views).
    public private(set) var lightPollutionReadiness: LightPollutionReadiness = .loading
    /// Bumped when readiness/provider changes so @Observable clients refresh.
    private var observingQualityRevision: UInt = 0
    
    private var apiKey: String
    public private(set) var locationTimeZone: TimeZone?
    private var conditionsLoadOperations: [ConditionsLoadKey: ConditionsLoadOperation] = [:]
    
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
        guard let viewingConditions else { return true }
        return !SharedConditionsRepository.isFreshForCurrentLocalDay(
            viewingConditions,
            referenceDate: now()
        )
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

    var currentBestTargetsPresentation: BestTargetsListPresentation {
        guard let conditions = viewingConditions,
              let resolution = TargetRecommendationContextBuilder.resolve(
                conditions: conditions,
                dayOffset: selectedDay.rawValue,
                referenceDate: now(),
                timeZone: displayTimeZone
              ) else {
            return BestTargetsListPresentation(recommendations: [])
        }

        let recommendations = targetRecommendationService.recommendations(
            for: resolution.context,
            limit: 100
        )
        Self.logUITargetRecommendations(
            recommendations,
            selectedDay: selectedDay,
            context: resolution.context,
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
        conditionsProvider: ConditionsProvider = ConditionsProvider(),
        conditionsRepository: SharedConditionsRepository? = nil,
        targetRecommendationService: any TargetRecommendationProviding = DefaultTargetRecommendationService(),
        observingQualityEnvironment: (any ObservingQualityEnvironment)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.apiKey = apiKey
        self.conditionsRepository = conditionsRepository
            ?? SharedConditionsRepository(provider: conditionsProvider, now: now)
        self.targetRecommendationService = targetRecommendationService
        // Safe default: exact night-score fallback. Never an unbootstrapped `.loading` session.
        // ContentView injects the process-owned ObservingQualitySession that it bootstraps.
        let environment = observingQualityEnvironment ?? UnavailableObservingQualityEnvironment.shared
        self.observingQualityEnvironment = environment
        self.lightPollutionReadiness = environment.lightPollutionReadiness
        self.now = now
    }

    /// Called by the process composition root after light-pollution bootstrap completes
    /// (or when test installs a provider). Feature views must not call LPATLAS1 loaders.
    public func syncLightPollutionReadinessFromEnvironment() {
        lightPollutionReadiness = observingQualityEnvironment.lightPollutionReadiness
        observingQualityRevision &+= 1
    }

    /// Night-conditions assessment (weather/Moon/darkness details). Unchanged by light pollution.
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

    /// True when night conditions exist but the headline must wait for LP readiness.
    /// Avoids flashing night-only score as if it were finalized observing quality.
    public var isObservingQualityHeadlinePending: Bool {
        _ = observingQualityRevision
        return currentNightQuality != nil && lightPollutionReadiness == .loading
    }

    /// Observing quality for the dashboard headline once light-pollution readiness is resolved.
    ///
    /// - Returns `nil` while `lightPollutionReadiness == .loading` (do not show interim score).
    /// - When `.ready` or `.unavailable`, always returns an assessment if night quality exists
    ///   (unavailable → exact night-conditions score, `lightPollution == nil`).
    public var currentObservingQuality: ObservingQualityAssessment? {
        _ = observingQualityRevision
        guard lightPollutionReadiness != .loading else { return nil }
        guard let nightQuality = currentNightQuality,
              let conditions = viewingConditions else {
            return nil
        }
        return observingQualityEnvironment.assess(
            nightConditionsScore: nightQuality.calculatedScore,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude
        )
    }

    /// Headline presentation derived only from observing-quality score (not night rating bands).
    public var currentObservingQualityHeadline: ObservingQualityHeadlinePresentation? {
        guard let assessment = currentObservingQuality else { return nil }
        return ObservingQualityHeadlinePresentation(assessment: assessment)
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
    private func loadConditions(for location: CachedLocation, forceRefresh: Bool = false) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let result = try await conditionsRepository.conditions(
                for: location,
                apiKey: apiKey,
                referenceDate: now(),
                forceRefresh: forceRefresh
            )
            let newConditions = result.conditions
            issError = result.issError
            if let identifier = newConditions.timeZoneIdentifier {
                locationTimeZone = TimeZone(identifier: identifier)
            } else {
                locationTimeZone = LocationTimeZoneResolver.approximate(longitude: newConditions.location.longitude)
            }
            viewingConditions = newConditions
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
        guard await loadConditions(for: location, forceRefresh: true) else {
            return false
        }

        await publishCompanionConditions()
        return true
    }

    private func publishCompanionConditions() async {
        guard let conditions = viewingConditions else { return }
        let companionConditions = conditions.limitedToTonightCache()
        if let widgetSummary = WidgetNightSummary.make(from: companionConditions) {
            await AppGroupStorage.saveWidgetNightSummaryAsync(widgetSummary)
        }
        await publishTonightTargets(from: conditions)
        await publishThreeNightOutlook(from: conditions)
        WatchConnectivityService.shared.sendConditionsToWatch(companionConditions)
        
        WidgetReloadService.shared.scheduleReload()
    }

    private func publishThreeNightOutlook(from conditions: ViewingConditions) async {
        let referenceDate = now()
        let existing = await AppGroupStorage.loadWidgetThreeNightOutlookSummaryAsync()
        switch ThreeNightOutlookWidgetPayloadBuilder.publicationDecision(
            conditions: conditions, existingSummary: existing,
            referenceDate: referenceDate, timeZone: displayTimeZone
        ) {
        case let .publish(summary):
            if ThreeNightOutlookPersistencePolicy.shouldSave(
                decision: .publish(summary),
                existing: existing,
                targetLocation: conditions.location,
                referenceDate: referenceDate
            ) {
                await AppGroupStorage.saveWidgetThreeNightOutlookSummaryAsync(summary)
            }
        case let .unavailable(summary):
            if ThreeNightOutlookPersistencePolicy.shouldSave(
                decision: .unavailable(summary),
                existing: existing,
                targetLocation: conditions.location,
                referenceDate: referenceDate
            ) {
                await AppGroupStorage.saveWidgetThreeNightOutlookSummaryAsync(summary)
            }
        case .preserveExisting:
            break
        }
    }

    private func publishTonightTargets(from conditions: ViewingConditions) async {
        let referenceDate = now()
        let existingSummary = await AppGroupStorage.loadWidgetTonightTargetsSummaryAsync()
        let decision = TonightTargetsWidgetContextResolver.publicationDecision(
            conditions: conditions,
            existingSummary: existingSummary,
            referenceDate: referenceDate,
            timeZone: displayTimeZone
        )

        let resolution: TargetRecommendationContextResolution
        switch decision {
        case let .publish(resolvedContext):
            resolution = resolvedContext
        case .preserveExisting:
            return
        case .unavailable:
            let unavailable = TonightTargetsWidgetPayloadBuilder.makeUnavailableSummary(
                generatedAt: conditions.fetchedAt,
                location: conditions.location,
                timeZone: displayTimeZone
                    ?? LocationTimeZoneResolver.approximate(
                        longitude: conditions.location.longitude
                    ),
                referenceDate: referenceDate
            )
            if TonightTargetsPersistencePolicy.shouldSave(
                candidate: unavailable,
                existing: existingSummary,
                targetLocation: conditions.location,
                referenceDate: referenceDate
            ) {
                await AppGroupStorage.saveWidgetTonightTargetsSummaryAsync(unavailable)
            }
            return
        }

        let recommendations = targetRecommendationService.recommendations(
            for: resolution.context,
            limit: 100
        )
        let summary = TonightTargetsWidgetPayloadBuilder.makeSummary(
            conditions: conditions,
            resolution: resolution,
            recommendations: recommendations
        )
        if TonightTargetsPersistencePolicy.shouldSave(
            candidate: summary,
            existing: existingSummary,
            targetLocation: conditions.location,
            referenceDate: referenceDate
        ) {
            await AppGroupStorage.saveWidgetTonightTargetsSummaryAsync(summary)
        }
    }

    private func publishUnavailableTonightTargets(for location: CachedLocation) async {
        let referenceDate = now()
        let timeZone = displayTimeZone
            ?? LocationTimeZoneResolver.approximate(longitude: location.longitude)
        let summary = TonightTargetsWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: referenceDate,
            location: location,
            timeZone: timeZone,
            referenceDate: referenceDate
        )
        let existing = await AppGroupStorage.loadWidgetTonightTargetsSummaryAsync()
        if TonightTargetsPersistencePolicy.shouldSave(
            candidate: summary,
            existing: existing,
            targetLocation: location,
            referenceDate: referenceDate
        ) {
            await AppGroupStorage.saveWidgetTonightTargetsSummaryAsync(summary)
        }
    }

    private func publishUnavailableThreeNightOutlook(for location: CachedLocation) async {
        let referenceDate = now()
        let timeZone = displayTimeZone
            ?? LocationTimeZoneResolver.approximate(longitude: location.longitude)
        let summary = ThreeNightOutlookWidgetPayloadBuilder.makeUnavailableSummary(
            generatedAt: referenceDate, location: location,
            timeZone: timeZone, referenceDate: referenceDate
        )
        let existing = await AppGroupStorage.loadWidgetThreeNightOutlookSummaryAsync()
        if ThreeNightOutlookPersistencePolicy.shouldSaveUnavailable(
            existing: existing,
            targetLocation: location,
            referenceDate: referenceDate
        ) {
            await AppGroupStorage.saveWidgetThreeNightOutlookSummaryAsync(summary)
        }
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

        if !currentConditionsMatch(location) {
            viewingConditions = nil
            issError = nil
        }

        if await loadConditions(for: location) {
            await publishCompanionConditions()
            return
        }

        if let conditions = viewingConditions,
           conditionsMatch(conditions, location: location) {
            await publishTonightTargets(from: conditions)
            await publishThreeNightOutlook(from: conditions)
        } else {
            await publishUnavailableTonightTargets(for: location)
            await publishUnavailableThreeNightOutlook(for: location)
        }
        WidgetReloadService.shared.scheduleReload()
    }

    private func currentConditionsMatch(_ location: CachedLocation) -> Bool {
        guard let viewingConditions else { return false }
        return conditionsMatch(viewingConditions, location: location)
    }

    private func conditionsMatch(_ conditions: ViewingConditions, location: CachedLocation) -> Bool {
        SharedConditionsRepository.locationMatches(conditions.location, location)
    }
}
