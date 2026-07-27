import Foundation

public actor ConditionsProvider {
    private let weatherService: WeatherService
    private let astronomyService: AstronomyService
    private let issServiceFactory: @Sendable (String) -> ISSService
    
    public init(
        weatherService: WeatherService = WeatherService(),
        astronomyService: AstronomyService = AstronomyService(),
        issServiceFactory: @escaping @Sendable (String) -> ISSService = { ISSService(apiKey: $0) }
    ) {
        self.weatherService = weatherService
        self.astronomyService = astronomyService
        self.issServiceFactory = issServiceFactory
    }
    
    public func fetchConditions(
        for location: CachedLocation,
        days: Int,
        apiKey: String? = nil
    ) async throws -> ViewingConditions {
        try await fetchConditionsWithDiagnostics(
            for: location,
            days: days,
            apiKey: apiKey
        ).conditions
    }

    public func fetchConditionsWithDiagnostics(
        for location: CachedLocation,
        days: Int,
        apiKey: String? = nil
    ) async throws -> ConditionsFetchResult {
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
        
        let issResult: ISSFetchResult
        if let apiKey, !apiKey.isEmpty {
            issResult = await fetchISSPasses(for: location, apiKey: apiKey)
        } else {
            issResult = ISSFetchResult(passes: [], state: .notRequested)
        }
        
        let conditions = ViewingConditions(
            fetchedAt: Date(),
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: dailySunEvents,
            dailyMoonInfo: dailyMoonInfo,
            issPasses: issResult.passes,
            fogScore: FogCalculator.calculateCurrent(from: forecasts),
            timeZoneIdentifier: tz.identifier
        )
        return ConditionsFetchResult(
            conditions: conditions,
            issError: issResult.error,
            issFetchState: issResult.state
        )
    }

    /// Fetches only the ISS data needed to enrich an already-fresh weather
    /// payload. A successful empty response is deliberately distinguishable
    /// from a request that was never attempted.
    public func fetchISSPasses(for location: CachedLocation, apiKey: String) async -> ISSFetchResult {
        let issService = issServiceFactory(apiKey)
        do {
            let passes = try await issService.fetchPasses(
                latitude: location.latitude,
                longitude: location.longitude,
                altitude: location.elevation ?? 0
            )
            return ISSFetchResult(passes: passes, state: .succeeded)
        } catch let error as ISSError {
            return ISSFetchResult(passes: [], state: .failed(error))
        } catch {
            let error = ISSError.apiError(statusCode: nil, message: error.localizedDescription)
            return ISSFetchResult(passes: [], state: .failed(error))
        }
    }

}

public enum ISSFetchState: Sendable, Equatable {
    case notRequested
    case succeeded
    case failed(ISSError)
}

public struct ISSFetchResult: Sendable {
    public let passes: [ISSPass]
    public let state: ISSFetchState

    public init(passes: [ISSPass], state: ISSFetchState) {
        self.passes = passes
        self.state = state
    }

    public var error: ISSError? {
        guard case let .failed(error) = state else { return nil }
        return error
    }
}

public struct ConditionsFetchResult: Sendable {
    public let conditions: ViewingConditions
    public let issError: ISSError?
    public let issFetchState: ISSFetchState

    public init(
        conditions: ViewingConditions,
        issError: ISSError?,
        issFetchState: ISSFetchState? = nil
    ) {
        self.conditions = conditions
        self.issError = issError
        self.issFetchState = issFetchState
            ?? issError.map(ISSFetchState.failed)
            ?? .notRequested
    }
}
