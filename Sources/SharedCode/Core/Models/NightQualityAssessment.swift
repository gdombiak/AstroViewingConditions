import Foundation

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
        NightConditionsScoring.publicScore(self)
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
