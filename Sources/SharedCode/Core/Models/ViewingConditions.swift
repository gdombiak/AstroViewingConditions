import Foundation

// MARK: - Viewing Conditions

public struct ViewingConditions: Sendable, Codable {
    public let fetchedAt: Date
    public let location: CachedLocation
    public let hourlyForecasts: [HourlyForecast]
    public let dailySunEvents: [SunEvents]
    public let dailyMoonInfo: [MoonInfo]
    public let issPasses: [ISSPass]
    public let fogScore: FogScore
    public let timeZoneIdentifier: String?
    
#if os(iOS)
    public init(
        fetchedAt: Date,
        location: SavedLocation,
        hourlyForecasts: [HourlyForecast],
        dailySunEvents: [SunEvents],
        dailyMoonInfo: [MoonInfo],
        issPasses: [ISSPass],
        fogScore: FogScore,
        timeZoneIdentifier: String? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.location = CachedLocation(from: location)
        self.hourlyForecasts = hourlyForecasts
        self.dailySunEvents = dailySunEvents
        self.dailyMoonInfo = dailyMoonInfo
        self.issPasses = issPasses
        self.fogScore = fogScore
        self.timeZoneIdentifier = timeZoneIdentifier
    }
#endif
    
    public init(
        fetchedAt: Date,
        location: CachedLocation,
        hourlyForecasts: [HourlyForecast],
        dailySunEvents: [SunEvents],
        dailyMoonInfo: [MoonInfo],
        issPasses: [ISSPass],
        fogScore: FogScore,
        timeZoneIdentifier: String? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.location = location
        self.hourlyForecasts = hourlyForecasts
        self.dailySunEvents = dailySunEvents
        self.dailyMoonInfo = dailyMoonInfo
        self.issPasses = issPasses
        self.fogScore = fogScore
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public extension ViewingConditions {
    func isFresh(within maxAge: TimeInterval, relativeTo referenceDate: Date = Date()) -> Bool {
        let age = referenceDate.timeIntervalSince(fetchedAt)
        return age >= 0 && age < maxAge
    }

    func isFreshForLocalDay(within maxAge: TimeInterval, relativeTo referenceDate: Date = Date()) -> Bool {
        guard isFresh(within: maxAge, relativeTo: referenceDate) else {
            return false
        }

        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        return calendar.isDate(fetchedAt, inSameDayAs: referenceDate)
    }

    func locationMatches(latitude: Double, longitude: Double, tolerance: Double = 0.01) -> Bool {
        location.matches(latitude: latitude, longitude: longitude, tolerance: tolerance)
    }

    func limitedToTonightCache() -> ViewingConditions {
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let referenceDate = hourlyForecasts.first?.time ?? fetchedAt
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? referenceDate
        let limitedForecasts = hourlyForecasts.filter { forecast in
            forecast.time >= startOfToday && forecast.time < endOfTomorrow
        }

        return ViewingConditions(
            fetchedAt: fetchedAt,
            location: location,
            hourlyForecasts: limitedForecasts,
            dailySunEvents: Array(dailySunEvents.prefix(2)),
            dailyMoonInfo: Array(dailyMoonInfo.prefix(2)),
            issPasses: [],
            fogScore: fogScore,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}
