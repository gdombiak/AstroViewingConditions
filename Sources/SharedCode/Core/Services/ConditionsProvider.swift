import Foundation

public actor ConditionsProvider {
    private let weatherService: WeatherService
    private let astronomyService: AstronomyService
    
    public init(
        weatherService: WeatherService = WeatherService(),
        astronomyService: AstronomyService = AstronomyService()
    ) {
        self.weatherService = weatherService
        self.astronomyService = astronomyService
    }
    
    public func fetchConditions(
        for location: CachedLocation,
        days: Int,
        apiKey: String? = nil
    ) async throws -> ViewingConditions {
        let tz = await LocationTimeZoneResolver.resolve(
            latitude: location.latitude,
            longitude: location.longitude
        )
        let calendar = LocationTimeZoneResolver.calendar(for: tz)
        let forecasts = try await weatherService.fetchForecast(
            latitude: location.latitude,
            longitude: location.longitude,
            days: days
        )
        
        let startOfToday = calendar.startOfDay(for: Date())
        var dailySunEvents: [SunEvents] = []
        var dailyMoonInfo: [MoonInfo] = []
        
        for dayOffset in 0..<days {
            let date = calendar.date(byAdding: Calendar.Component.day, value: dayOffset, to: startOfToday)
                ?? startOfToday.addingTimeInterval(Double(dayOffset) * 24 * 60 * 60)
            let sunEvents = await astronomyService.calculateSunEvents(
                latitude: location.latitude,
                longitude: location.longitude,
                on: date
            )
            let moonInfo = await astronomyService.calculateMoonInfo(
                latitude: location.latitude,
                longitude: location.longitude,
                on: date
            )
            dailySunEvents.append(sunEvents)
            dailyMoonInfo.append(moonInfo)
        }
        
        let issPasses: [ISSPass]
        if let apiKey, !apiKey.isEmpty {
            let issService = ISSService(apiKey: apiKey)
            issPasses = try await issService.fetchPasses(
                latitude: location.latitude,
                longitude: location.longitude,
                altitude: location.elevation ?? 0
            )
        } else {
            issPasses = []
        }
        
        return ViewingConditions(
            fetchedAt: Date(),
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: dailySunEvents,
            dailyMoonInfo: dailyMoonInfo,
            issPasses: issPasses,
            fogScore: FogCalculator.calculateCurrent(from: forecasts),
            timeZoneIdentifier: tz.identifier
        )
    }

    public func conditions(
        for location: CachedLocation,
        days: Int,
        apiKey: String? = nil,
        cacheService: CacheService,
        cacheMaxAge: TimeInterval,
        locationTolerance: Double = 0.01
    ) async throws -> ViewingConditions {
        if let cached = await cacheService.loadAsync(),
           cached.isFreshForLocalDay(within: cacheMaxAge),
           cached.locationMatches(
               latitude: location.latitude,
               longitude: location.longitude,
               tolerance: locationTolerance
           ) {
            return cached
        }

        let freshConditions = try await fetchConditions(
            for: location,
            days: days,
            apiKey: apiKey
        )
        await cacheService.saveAsync(freshConditions)
        return freshConditions
    }
}
