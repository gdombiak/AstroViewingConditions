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
        return Date().timeIntervalSince(conditions.fetchedAt) > 3600
    }

    private func loadCachedConditions() {
        guard let cached = AppGroupStorage.loadConditionsWithTimestamp() else { return }
        Task {
            let timeZone = await Self.resolveTimeZone(for: cached.conditions)
            await MainActor.run {
                self.locationTimeZone = timeZone
                self.conditions = cached.conditions
            }
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveConditions conditions: ViewingConditions) {
        AppGroupStorage.saveConditions(conditions)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            let timeZone = await Self.resolveTimeZone(for: conditions)
            await MainActor.run {
                self.locationTimeZone = timeZone
                self.conditions = conditions
                self.isLoading = false
            }
        }
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveLocations locations: [CachedLocation], selectedLocation: SelectedLocation?) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveSelectedLocation location: SelectedLocation) {
    }
    
    func connectivityManager(_ manager: WatchConnectivityManager, didReceiveUnitSystem unitSystem: UnitSystem) {
    }
    
    func refresh() async {
        await MainActor.run { isLoading = true }
        
        do {
            let conditions = try await fetchConditions()
            let timeZone = await Self.resolveTimeZone(for: conditions)
            await MainActor.run {
                self.locationTimeZone = timeZone
                self.conditions = conditions
                self.isLoading = false
            }
            AppGroupStorage.saveConditions(conditions)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("WatchConditionsManager: Failed to refresh conditions: \(error)")
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func fetchConditions() async throws -> ViewingConditions {
        guard let selectedLocation = locationManager.selectedLocation else {
            throw ConditionsError.noLocationSelected
        }
        
        let coordinate = try await locationManager.getCurrentCoordinate()
        let locationName = selectedLocation.name
        
        do {
            let (conditions, _) = try await connectivityManager.requestConditions()
            return conditions
        } catch {
            print("WatchConditionsManager: Watch connectivity failed: \(error.localizedDescription), computing locally")
            return try await computeConditionsLocally(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                locationName: locationName
            )
        }
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
