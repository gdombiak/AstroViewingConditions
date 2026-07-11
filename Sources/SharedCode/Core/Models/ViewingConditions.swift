import Foundation
import SwiftUI

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
        referenceDate.timeIntervalSince(fetchedAt) <= maxAge
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

public extension CachedLocation {
    func matches(latitude: Double, longitude: Double, tolerance: Double = 0.01) -> Bool {
        abs(self.latitude - latitude) <= tolerance &&
            abs(self.longitude - longitude) <= tolerance
    }
}

// MARK: - Hourly Forecast

public struct HourlyForecast: Identifiable, Sendable, Codable {
    public let id: UUID
    public let time: Date
    public let cloudCover: Int
    public let humidity: Int
    public let windSpeed: Double
    public let windDirection: Int
    public let temperature: Double
    public let dewPoint: Double?
    public let visibility: Double?
    public let lowCloudCover: Int?
    public let midCloudCover: Int?
    public let highCloudCover: Int?
    public let windSpeed200hPa: Double?
    
    public init(
        id: UUID = UUID(),
        time: Date,
        cloudCover: Int,
        humidity: Int,
        windSpeed: Double,
        windDirection: Int,
        temperature: Double,
        dewPoint: Double? = nil,
        visibility: Double? = nil,
        lowCloudCover: Int? = nil,
        midCloudCover: Int? = nil,
        highCloudCover: Int? = nil,
        windSpeed200hPa: Double? = nil
    ) {
        self.id = id
        self.time = time
        self.cloudCover = cloudCover
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.temperature = temperature
        self.dewPoint = dewPoint
        self.visibility = visibility
        self.lowCloudCover = lowCloudCover
        self.midCloudCover = midCloudCover
        self.highCloudCover = highCloudCover
        self.windSpeed200hPa = windSpeed200hPa
    }
}

// MARK: - Fog Score

public struct FogScore: Sendable, Codable, Hashable {
    public let score: Int
    public let factors: [FogFactor]
    
    public init(score: Int, factors: [FogFactor]) {
        self.score = min(max(score, 0), 100)
        self.factors = factors
    }
    
    public enum FogFactor: String, CaseIterable, Sendable, Codable {
        case highHumidity = "High Humidity"
        case lowTempDewDiff = "Low Temp/Dew Point Difference"
        case lowVisibility = "Low Visibility"
        case highLowCloud = "High Low-Level Clouds"
        case lowWind = "Calm Winds"
    }
}

// MARK: - Sun Events

public struct SunEvents: Sendable, Codable {
    public let sunrise: Date
    public let sunset: Date
    public let civilTwilightBegin: Date
    public let civilTwilightEnd: Date
    public let nauticalTwilightBegin: Date
    public let nauticalTwilightEnd: Date
    public let astronomicalTwilightBegin: Date
    public let astronomicalTwilightEnd: Date
    
    public init(
        sunrise: Date,
        sunset: Date,
        civilTwilightBegin: Date,
        civilTwilightEnd: Date,
        nauticalTwilightBegin: Date,
        nauticalTwilightEnd: Date,
        astronomicalTwilightBegin: Date,
        astronomicalTwilightEnd: Date
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.civilTwilightBegin = civilTwilightBegin
        self.civilTwilightEnd = civilTwilightEnd
        self.nauticalTwilightBegin = nauticalTwilightBegin
        self.nauticalTwilightEnd = nauticalTwilightEnd
        self.astronomicalTwilightBegin = astronomicalTwilightBegin
        self.astronomicalTwilightEnd = astronomicalTwilightEnd
    }
    
    public var astronomicalNightStart: Date {
        astronomicalTwilightEnd
    }
    
    public var astronomicalNightEnd: Date {
        astronomicalTwilightBegin
    }
    
    public var astronomicalNightDuration: TimeInterval {
        astronomicalNightEnd.timeIntervalSince(astronomicalNightStart)
    }
    
    public func astronomicalNightEnd(using tomorrowSunEvents: SunEvents?) -> Date {
        tomorrowSunEvents?.astronomicalTwilightBegin ?? astronomicalNightEnd
    }
    
    public func astronomicalNightDuration(using tomorrowSunEvents: SunEvents?) -> TimeInterval {
        astronomicalNightEnd(using: tomorrowSunEvents).timeIntervalSince(astronomicalNightStart)
    }
}

// MARK: - Moon Info

public struct MoonInfo: Sendable, Codable {
    public let phase: Double
    public let phaseName: String
    public let altitude: Double
    public let illumination: Int
    public let emoji: String
    
    public init(
        phase: Double,
        phaseName: String,
        altitude: Double,
        illumination: Int,
        emoji: String
    ) {
        self.phase = phase
        self.phaseName = phaseName
        self.altitude = altitude
        self.illumination = illumination
        self.emoji = emoji
    }
}

// MARK: - Night Quality Assessment

public struct NightQualityAssessment: Sendable, Codable, Hashable {
    public let rating: Rating
    public let summary: String
    public let details: Details
    public let bestWindow: TimeWindow?
    public let hourlyRatings: [HourlyRating]
    public let nightStart: Date
    public let nightEnd: Date
    public let trend: Trend
    public let firstHalfScore: Double?
    public let secondHalfScore: Double?
    
    public var calculatedScore: Int {
        BestSpotSearcher.calculateScore(self)
    }
    
    public init(
        rating: Rating,
        summary: String,
        details: Details,
        bestWindow: TimeWindow?,
        hourlyRatings: [HourlyRating],
        nightStart: Date,
        nightEnd: Date,
        trend: Trend = .stable,
        firstHalfScore: Double? = nil,
        secondHalfScore: Double? = nil
    ) {
        self.rating = rating
        self.summary = summary
        self.details = details
        self.bestWindow = bestWindow
        self.hourlyRatings = hourlyRatings
        self.nightStart = nightStart
        self.nightEnd = nightEnd
        self.trend = trend
        self.firstHalfScore = firstHalfScore
        self.secondHalfScore = secondHalfScore
    }
    
    public enum Trend: String, Sendable, Codable {
        case improving
        case stable
        case degrading
        
        public var icon: String {
            switch self {
            case .improving: return "↗"
            case .stable: return "→"
            case .degrading: return "↘"
            }
        }
        
        public var label: String {
            switch self {
            case .improving: return "Conditions improve after midnight"
            case .stable: return "Conditions stable all night"
            case .degrading: return "Conditions degrade after midnight"
            }
        }
    }
    
    public enum Rating: String, Sendable, Codable {
        case excellent
        case good
        case fair
        case poor
        
        public enum Thresholds {
            public static let excellentMax: Double = 0.3
            public static let goodMax: Double = 0.7
            public static let fairMax: Double = 1.0
        }
        
        public static func from(score: Double) -> Self {
            if score < Thresholds.excellentMax { return .excellent }
            else if score < Thresholds.goodMax { return .good }
            else if score < Thresholds.fairMax { return .fair }
            else { return .poor }
        }
        
        public var emoji: String {
            switch self {
            case .excellent: return "🥇"
            case .good: return "🥈"
            case .fair: return "⚠️"
            case .poor: return "❌"
            }
        }
        
        public var colorName: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "orange"
            case .poor: return "red"
            }
        }
    }
    
    public struct Details: Sendable, Codable, Hashable {
        public let cloudCoverScore: Double
        public let fogScoreAvg: Double
        public let moonIlluminationAvg: Int
        public let windSpeedAvg: Double
        public let seeingScoreAvg: Double?
        public let transparencyScoreAvg: Double?
        
        public init(
            cloudCoverScore: Double,
            fogScoreAvg: Double,
            moonIlluminationAvg: Int,
            windSpeedAvg: Double,
            seeingScoreAvg: Double? = nil,
            transparencyScoreAvg: Double? = nil
        ) {
            self.cloudCoverScore = cloudCoverScore
            self.fogScoreAvg = fogScoreAvg
            self.moonIlluminationAvg = moonIlluminationAvg
            self.windSpeedAvg = windSpeedAvg
            self.seeingScoreAvg = seeingScoreAvg
            self.transparencyScoreAvg = transparencyScoreAvg
        }
    }
    
    public struct HourlyRating: Identifiable, Sendable, Codable, Hashable {
        public let id: UUID
        public let time: Date
        public let score: Double
        public let cloudCover: Int
        public let fogScore: Int
        public let moonIllumination: Int
        public let moonAltitude: Double
        public let windSpeed: Double
        public let seeingScore: Double?
        public let transparencyScore: Double?
        
        public init(
            id: UUID = UUID(),
            time: Date,
            score: Double,
            cloudCover: Int,
            fogScore: Int,
            moonIllumination: Int,
            moonAltitude: Double,
            windSpeed: Double,
            seeingScore: Double? = nil,
            transparencyScore: Double? = nil
        ) {
            self.id = id
            self.time = time
            self.score = score
            self.cloudCover = cloudCover
            self.fogScore = fogScore
            self.moonIllumination = moonIllumination
            self.moonAltitude = moonAltitude
            self.windSpeed = windSpeed
            self.seeingScore = seeingScore
            self.transparencyScore = transparencyScore
        }
        
        public var rating: Rating {
            Rating.from(score: score)
        }
    }
    
    public struct TimeWindow: Sendable, Codable, Hashable {
        public let start: Date
        public let end: Date
        
        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
        
        public var duration: TimeInterval {
            end.timeIntervalSince(start)
        }
    }
}

// MARK: - ISS Pass

public struct ISSPass: Identifiable, Sendable, Codable {
    public let id: String
    public let riseTime: Date
    public let duration: TimeInterval
    public let maxElevation: Double
    public let maxTime: Date?
    public let endTime: Date?
    public let startDirection: String?
    public let maxDirection: String?
    public let endDirection: String?
    public let startElevation: Double?
    public let endElevation: Double?
    
    public init(
        id: String? = nil,
        riseTime: Date,
        duration: TimeInterval,
        maxElevation: Double,
        maxTime: Date? = nil,
        endTime: Date? = nil,
        startDirection: String? = nil,
        maxDirection: String? = nil,
        endDirection: String? = nil,
        startElevation: Double? = nil,
        endElevation: Double? = nil
    ) {
        self.id = id ?? Self.stableID(
            riseTime: riseTime,
            duration: duration
        )
        self.riseTime = riseTime
        self.duration = duration
        self.maxElevation = maxElevation
        self.maxTime = maxTime
        self.endTime = endTime
        self.startDirection = startDirection
        self.maxDirection = maxDirection
        self.endDirection = endDirection
        self.startElevation = startElevation
        self.endElevation = endElevation
    }
    
    public var setTime: Date {
        endTime ?? riseTime.addingTimeInterval(duration)
    }

    private static func stableID(
        riseTime: Date,
        duration: TimeInterval
    ) -> String {
        "\(riseTime.timeIntervalSince1970.bitPattern)-\(duration.bitPattern)"
    }
}

// MARK: - Color Extensions

extension NightQualityAssessment.Rating {
    public var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

extension NightQualityAssessment {
    public func scoreColor(for score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    public var scoreColor: Color {
        scoreColor(for: calculatedScore)
    }
    
    public var ratingColor: Color {
        rating.color
    }
    
    public func scoreToColor(_ score: Double) -> Color {
        if score < 0.3 { return .green }
        else if score < 0.7 { return .blue }
        else if score < 1.0 { return .orange }
        else { return .red }
    }
    
    public func scoreLabel(_ score: Double) -> String {
        if score < 0.3 { return "Excellent" }
        else if score < 0.7 { return "Good" }
        else if score < 1.0 { return "Fair" }
        else { return "Poor" }
    }
    
    public func cloudColor(_ coverage: Double) -> Color {
        switch Int(coverage) {
        case 0..<20: return .green
        case 20..<50: return .blue
        case 50..<80: return .orange
        default: return .red
        }
    }
    
    public func moonColor(_ illumination: Int) -> Color {
        switch illumination {
        case 0..<25: return .green
        case 25..<50: return .blue
        case 50..<75: return .orange
        default: return .red
        }
    }
    
    public func windColor(_ speed: Double) -> Color {
        switch speed {
        case 0..<5: return .green
        case 5..<10: return .blue
        case 10..<15: return .orange
        default: return .red
        }
    }
    
    public func fogColor(_ score: Int) -> Color {
        switch score {
        case 0..<25: return .green
        case 25..<50: return .blue
        case 50..<75: return .orange
        default: return .red
        }
    }
}

public enum ConditionColorPalette {
    public static func astronomyRiskBackground(for percentage: Int) -> Color {
        let coverage = Double(min(max(percentage, 0), 100)) / 100.0
        let red = 10 + (230 * coverage)
        let green = 20 + (220 * coverage)
        let blue = 80 + (155 * coverage)
        return Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
    
    public static func astronomyRiskText(for percentage: Int) -> Color {
        percentage > 60 ? .black : .white
    }
}
