import Foundation
import SwiftUI
import SharedCode
import WidgetKit

enum ConditionsError: Error, LocalizedError {
    case noLocationSelected
    case fetchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noLocationSelected: return "No location selected"
        case .fetchFailed(let msg): return msg
        }
    }
}

protocol WatchConditionsManagerDelegate: AnyObject {
    func conditionsManager(_ manager: WatchConditionsManager, didReceiveConditions conditions: ViewingConditions)
}

class WatchConditionsManager: ObservableObject, @unchecked Sendable, WatchConnectivityManagerDelegate {
    static let shared = WatchConditionsManager()
    private static let freshConditionsInterval: TimeInterval = 3600
    private static let locationMatchTolerance = 0.01
    
    weak var delegate: WatchConditionsManagerDelegate?
    
    private let connectivityManager = WatchConnectivityManager.shared
    private let locationManager = WatchLocationManager.shared
    
    @Published var conditions: ViewingConditions?
    @Published var nightQuality: NightQualityAssessment?
    @Published private(set) var locationTimeZone: TimeZone?
    @Published var isLoading = false
    @Published var error: Error?
    
    var locationCalendar: Calendar {
        if let timeZone = displayTimeZone {
            return LocationTimeZoneResolver.calendar(for: timeZone)
        }
        return LocationTimeZoneResolver.calendar(for: TimeZone(identifier: "UTC")!)
    }
    
    var displayTimeZone: TimeZone? {
        if let locationTimeZone {
            return locationTimeZone
        }
        if let identifier = conditions?.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        if let longitude = conditions?.location.longitude {
            return LocationTimeZoneResolver.approximate(longitude: longitude)
        }
        return nil
    }
    
    private init() {
        connectivityManager.addDelegate(self)
        loadCachedConditions()
    }

    var shouldRefresh: Bool {
        guard let conditions else { return true }
        guard let selectedLocation = locationManager.selectedLocation else { return true }
        return !Self.isFresh(conditions) || !Self.conditions(conditions, match: selectedLocation)
    }

    private func loadCachedConditions() {
        Task {
            guard let conditions = await AppGroupStorage.loadWatchNightConditionsAsync() else { return }
            let timeZone = await Self.resolveTimeZone(for: conditions)
            await MainActor.run {
                self.locationTimeZone = timeZone
                self.conditions = conditions
            }
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveConditions conditions: ViewingConditions) {
        Task {
            if !Self.isFresh(conditions) {
                return
            }

            let selectedLocation = await MainActor.run { locationManager.selectedLocation }
            if let selectedLocation,
               !Self.conditions(conditions, match: selectedLocation) {
                return
            }

            await AppGroupStorage.saveWatchNightConditionsAsync(conditions)
            let timeZone = await Self.resolveTimeZone(for: conditions)
            await MainActor.run {
                self.locationTimeZone = timeZone
                self.conditions = conditions
                self.error = nil
                self.isLoading = false
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem) {
    }
    
    func refresh() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            let conditions = try await fetchConditions()
            let timeZone = await Self.resolveTimeZone(for: conditions)
            await MainActor.run {
                self.locationTimeZone = timeZone
                self.conditions = conditions
                self.error = nil
                self.isLoading = false
            }
            await AppGroupStorage.saveWatchNightConditionsAsync(conditions)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("WatchConditionsManager: Failed to refresh conditions: \(error)")
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }

    func loadNewerSharedCacheIfAvailable() async {
        guard let cached = await AppGroupStorage.loadWatchNightConditionsAsync() else { return }

        let selectedLocation = await MainActor.run { locationManager.selectedLocation }
        if let selectedLocation,
           !Self.conditions(cached, match: selectedLocation) {
            return
        }

        let shouldUseCached = await MainActor.run {
            guard let conditions else { return true }
            return cached.fetchedAt > conditions.fetchedAt
        }

        guard shouldUseCached else { return }

        let timeZone = await Self.resolveTimeZone(for: cached)
        await MainActor.run {
            self.locationTimeZone = timeZone
            self.conditions = cached
        }
    }
    
    private func fetchConditions() async throws -> ViewingConditions {
        guard let selectedLocation = locationManager.selectedLocation else {
            throw ConditionsError.noLocationSelected
        }
        
        do {
            let (conditions, _) = try await connectivityManager.requestConditions()
            guard Self.isFresh(conditions) else {
                throw ConditionsError.fetchFailed("iOS returned stale conditions")
            }
            guard Self.conditions(conditions, match: selectedLocation) else {
                throw ConditionsError.fetchFailed("iOS returned conditions for a different location")
            }
            return conditions
        } catch {
            print("WatchConditionsManager: Watch connectivity failed: \(error.localizedDescription), computing locally")
            let coordinate = try await locationManager.getCurrentCoordinate()
            return try await computeConditionsLocally(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                locationName: selectedLocation.name
            )
        }
    }

    private static func isFresh(_ conditions: ViewingConditions) -> Bool {
        Date().timeIntervalSince(conditions.fetchedAt) <= freshConditionsInterval
    }

    private static func conditions(_ conditions: ViewingConditions, match selectedLocation: SelectedLocation) -> Bool {
        if let selectedID = selectedLocation.id,
           let conditionsID = conditions.location.id {
            return selectedID == conditionsID
        }

        if selectedLocation.source == .currentGPS,
           selectedLocation.latitude == 0,
           selectedLocation.longitude == 0 {
            return true
        }

        return coordinates(
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            matchLatitude: selectedLocation.latitude,
            matchLongitude: selectedLocation.longitude
        )
    }

    private static func coordinates(
        latitude: Double,
        longitude: Double,
        matchLatitude: Double,
        matchLongitude: Double
    ) -> Bool {
        abs(latitude - matchLatitude) <= locationMatchTolerance
            && abs(longitude - matchLongitude) <= locationMatchTolerance
    }
    
    private func computeConditionsLocally(
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws -> ViewingConditions {
        let tz = await LocationTimeZoneResolver.resolve(latitude: latitude, longitude: longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: tz)
        
        let weatherService = WeatherService()
        let forecasts = try await weatherService.fetchForecast(
            latitude: latitude,
            longitude: longitude,
            days: 2
        )
        
        let startOfToday = calendar.startOfDay(for: Date())
        
        let astronomyService = AstronomyService()
        var dailySunEvents: [SunEvents] = []
        var dailyMoonInfo: [MoonInfo] = []
        
        for dayOffset in 0..<2 {
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
        
        let fogScore = FogCalculator.calculateCurrent(from: forecasts)
        
        let cachedLocation = CachedLocation(
            name: locationName,
            latitude: latitude,
            longitude: longitude,
            elevation: nil
        )
        
        return ViewingConditions(
            fetchedAt: Date(),
            location: cachedLocation,
            hourlyForecasts: forecasts,
            dailySunEvents: dailySunEvents,
            dailyMoonInfo: dailyMoonInfo,
            issPasses: [],
            fogScore: fogScore,
            timeZoneIdentifier: tz.identifier
        )
    }
    
    private static func resolveTimeZone(for conditions: ViewingConditions) async -> TimeZone {
        if let identifier = conditions.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        
        return await resolveTimeZone(for: conditions.location)
    }
    
    private static func resolveTimeZone(for location: CachedLocation) async -> TimeZone {
        await LocationTimeZoneResolver.resolve(
            latitude: location.latitude,
            longitude: location.longitude
        )
    }
}
