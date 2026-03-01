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
    
    public init(
        fetchedAt: Date,
        location: SavedLocation,
        hourlyForecasts: [HourlyForecast],
        dailySunEvents: [SunEvents],
        dailyMoonInfo: [MoonInfo],
        issPasses: [ISSPass],
        fogScore: FogScore
    ) {
        self.fetchedAt = fetchedAt
        self.location = CachedLocation(from: location)
        self.hourlyForecasts = hourlyForecasts
        self.dailySunEvents = dailySunEvents
        self.dailyMoonInfo = dailyMoonInfo
        self.issPasses = issPasses
        self.fogScore = fogScore
    }
    
    public init(
        fetchedAt: Date,
        location: CachedLocation,
        hourlyForecasts: [HourlyForecast],
        dailySunEvents: [SunEvents],
        dailyMoonInfo: [MoonInfo],
        issPasses: [ISSPass],
        fogScore: FogScore
    ) {
        self.fetchedAt = fetchedAt
        self.location = location
        self.hourlyForecasts = hourlyForecasts
        self.dailySunEvents = dailySunEvents
        self.dailyMoonInfo = dailyMoonInfo
        self.issPasses = issPasses
        self.fogScore = fogScore
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
        lowCloudCover: Int? = nil
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
    
    public func astronomicalNightDuration(on date: Date) -> TimeInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let nightStart = calendar.date(bySettingHour: calendar.component(.hour, from: astronomicalNightStart),
                                       minute: calendar.component(.minute, from: astronomicalNightStart),
                                       second: 0,
                                       of: startOfDay) ?? startOfDay
        
        var nightEnd = calendar.date(bySettingHour: calendar.component(.hour, from: astronomicalNightEnd),
                                     minute: calendar.component(.minute, from: astronomicalNightEnd),
                                     second: 0,
                                     of: startOfDay) ?? startOfDay
        
        if nightEnd < nightStart {
            nightEnd = calendar.date(byAdding: .day, value: 1, to: nightEnd) ?? nightEnd
        }
        
        return nightEnd.timeIntervalSince(nightStart)
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
    
    public init(
        rating: Rating,
        summary: String,
        details: Details,
        bestWindow: TimeWindow?,
        hourlyRatings: [HourlyRating],
        nightStart: Date,
        nightEnd: Date
    ) {
        self.rating = rating
        self.summary = summary
        self.details = details
        self.bestWindow = bestWindow
        self.hourlyRatings = hourlyRatings
        self.nightStart = nightStart
        self.nightEnd = nightEnd
    }
    
    public enum Rating: String, Sendable, Codable {
        case excellent
        case good
        case fair
        case poor
        
        public var emoji: String {
            switch self {
            case .excellent: return "🥉"
            case .good: return "🏅"
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
        
        public init(
            cloudCoverScore: Double,
            fogScoreAvg: Double,
            moonIlluminationAvg: Int,
            windSpeedAvg: Double
        ) {
            self.cloudCoverScore = cloudCoverScore
            self.fogScoreAvg = fogScoreAvg
            self.moonIlluminationAvg = moonIlluminationAvg
            self.windSpeedAvg = windSpeedAvg
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
        
        public init(
            id: UUID = UUID(),
            time: Date,
            score: Double,
            cloudCover: Int,
            fogScore: Int,
            moonIllumination: Int,
            moonAltitude: Double,
            windSpeed: Double
        ) {
            self.id = id
            self.time = time
            self.score = score
            self.cloudCover = cloudCover
            self.fogScore = fogScore
            self.moonIllumination = moonIllumination
            self.moonAltitude = moonAltitude
            self.windSpeed = windSpeed
        }
        
        public var rating: Rating {
            if score < 0.5 { return .excellent }
            else if score < 1.0 { return .good }
            else if score < 2.0 { return .fair }
            else { return .poor }
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
    public let id: UUID
    public let riseTime: Date
    public let duration: TimeInterval
    public let maxElevation: Double
    
    public init(
        id: UUID = UUID(),
        riseTime: Date,
        duration: TimeInterval,
        maxElevation: Double
    ) {
        self.id = id
        self.riseTime = riseTime
        self.duration = duration
        self.maxElevation = maxElevation
    }
    
    public var setTime: Date {
        riseTime.addingTimeInterval(duration)
    }
}
