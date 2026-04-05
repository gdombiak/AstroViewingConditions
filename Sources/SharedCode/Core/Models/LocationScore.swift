import Foundation

/// Represents a scored location for viewing conditions
public struct LocationScore: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let point: GridPoint
    public let score: Int
    public let nightQuality: NightQualityAssessment
    public let fogScore: FogScore
    public let avgCloudCover: Double
    public let avgWindSpeed: Double
    public let summary: String
    
    public init(
        id: UUID = UUID(),
        point: GridPoint,
        score: Int,
        nightQuality: NightQualityAssessment,
        fogScore: FogScore,
        avgCloudCover: Double,
        avgWindSpeed: Double,
        summary: String
    ) {
        self.id = id
        self.point = point
        self.score = score
        self.nightQuality = nightQuality
        self.fogScore = fogScore
        self.avgCloudCover = avgCloudCover
        self.avgWindSpeed = avgWindSpeed
        self.summary = summary
    }
    
    public var distanceString: String {
        if point.distanceMiles < 1 {
            return String(format: "%.1f mi", point.distanceMiles)
        } else {
            return String(format: "%.1f mi", point.distanceMiles)
        }
    }
    
    public var bearingString: String {
        GeographicGridGenerator.bearingToCardinal(point.bearing)
    }
    
    public var fullLocationString: String {
        "\(distanceString) \(bearingString)"
    }
    
    public var scoreColor: String {
        switch score {
        case 80...100:
            return "green"
        case 60..<80:
            return "blue"
        case 40..<60:
            return "orange"
        default:
            return "red"
        }
    }
}

/// Result of a best spot search
public struct BestSpotResult: Sendable {
    public let centerLocation: CachedLocation
    public let searchRadiusMiles: Double
    public let gridSpacingMiles: Double
    public let scoredLocations: [LocationScore]
    public let moonInfo: MoonInfo
    public let searchDate: Date
    public let searchDuration: TimeInterval
    
    public var bestSpot: LocationScore? {
        scoredLocations.first
    }
    
    public var topSpots: [LocationScore] {
        scoredLocations
    }
    
    public init(
        centerLocation: CachedLocation,
        searchRadiusMiles: Double,
        gridSpacingMiles: Double,
        scoredLocations: [LocationScore],
        moonInfo: MoonInfo,
        searchDate: Date,
        searchDuration: TimeInterval
    ) {
        self.centerLocation = centerLocation
        self.searchRadiusMiles = searchRadiusMiles
        self.gridSpacingMiles = gridSpacingMiles
        self.scoredLocations = scoredLocations
        self.moonInfo = moonInfo
        self.searchDate = searchDate
        self.searchDuration = searchDuration
    }
}
