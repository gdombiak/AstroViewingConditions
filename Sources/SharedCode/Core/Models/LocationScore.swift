import Foundation
import SwiftUI

public enum LocationSuitabilityStatus: Sendable, Hashable {
    case suitable
    case unsuitable(reason: String)
    case unchecked
    case unknown(reason: UnknownReason)

    public enum UnknownReason: Sendable, Hashable {
        case notChecked
        case geocodingFailed
        case temporarilyUnavailable
    }

    public var isRecommendable: Bool {
        switch self {
        case .suitable, .unknown:
            return true
        case .unchecked, .unsuitable:
            return false
        }
    }

    public var verificationRank: Int {
        switch self {
        case .suitable:
            return 0
        case .unknown:
            return 1
        case .unchecked:
            return 2
        case .unsuitable:
            return 3
        }
    }

    public var indicatesIncompleteVerification: Bool {
        switch self {
        case .unknown(.geocodingFailed), .unknown(.temporarilyUnavailable):
            return true
        case .suitable, .unsuitable, .unchecked, .unknown(.notChecked):
            return false
        }
    }

    public var label: String {
        switch self {
        case .suitable:
            return "Land area"
        case .unsuitable(let reason):
            return reason
        case .unchecked:
            return "Weather-only estimate. Access not checked."
        case .unknown(.notChecked):
            return "Access not verified"
        case .unknown(.geocodingFailed):
            return "Verification unavailable"
        case .unknown(.temporarilyUnavailable):
            return "Verification temporarily unavailable"
        }
    }
}

/// Represents a scored location for viewing conditions
public struct LocationScore: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let point: GridPoint
    public let score: Int
    public let nightQuality: NightQualityAssessment
    public let fogScore: FogScore
    public let avgCloudCover: Double
    public let avgWindSpeed: Double
    public let suitability: LocationSuitabilityStatus
    public let improvementOverCenter: Int?
    public let summary: String
    
    public init(
        id: UUID = UUID(),
        point: GridPoint,
        score: Int,
        nightQuality: NightQualityAssessment,
        fogScore: FogScore,
        avgCloudCover: Double,
        avgWindSpeed: Double,
        suitability: LocationSuitabilityStatus = .unchecked,
        improvementOverCenter: Int? = nil,
        summary: String
    ) {
        self.id = id
        self.point = point
        self.score = score
        self.nightQuality = nightQuality
        self.fogScore = fogScore
        self.avgCloudCover = avgCloudCover
        self.avgWindSpeed = avgWindSpeed
        self.suitability = suitability
        self.improvementOverCenter = improvementOverCenter
        self.summary = summary
    }
    
    public var distanceString: String {
        String(format: "%.1f mi", point.distanceMiles)
    }
    
    public var bearingString: String {
        GeographicGridGenerator.bearingToCardinal(point.bearing)
    }
    
    public var fullLocationString: String {
        "\(distanceString) \(bearingString)"
    }

    public var averageFog: Double {
        Double(fogScore.score)
    }

    public var moonImpactSummary: String {
        let illumination = nightQuality.details.moonIlluminationAvg
        switch illumination {
        case 0..<15:
            return "Low moon impact"
        case 15..<50:
            return "Moderate moon impact"
        default:
            return "High moon impact"
        }
    }

    public var improvementSummary: String {
        guard let improvementOverCenter else { return "Current location not scored" }

        switch improvementOverCenter {
        case ...2:
            return "Not meaningfully better than your location"
        case 3...9:
            return "Small improvement"
        case 10...19:
            return "Worth considering"
        default:
            return "Strong improvement"
        }
    }

    public var canOpenInMaps: Bool {
        suitability.isRecommendable
    }

    public func withImprovement(comparedTo centerScore: Int?) -> LocationScore {
        with(
            suitability: suitability,
            improvementOverCenter: centerScore.map { score - $0 }
        )
    }

    public func with(
        suitability: LocationSuitabilityStatus? = nil,
        improvementOverCenter: Int? = nil
    ) -> LocationScore {
        LocationScore(
            id: id,
            point: point,
            score: score,
            nightQuality: nightQuality,
            fogScore: fogScore,
            avgCloudCover: avgCloudCover,
            avgWindSpeed: avgWindSpeed,
            suitability: suitability ?? self.suitability,
            improvementOverCenter: improvementOverCenter ?? self.improvementOverCenter,
            summary: summary
        )
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
    
    public var color: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
}

/// Result of a best spot search
public struct BestSpotResult: Sendable {
    public let centerLocation: CachedLocation
    public let searchRadiusMiles: Double
    public let gridSpacingMiles: Double
    public let allScoredLocations: [LocationScore]
    public let topLocations: [LocationScore]
    public let moonInfo: MoonInfo
    public let searchDate: Date
    public let searchDuration: TimeInterval
    public let suitabilityWarning: String?
    
    public var bestSpot: LocationScore? {
        topLocations.first
    }
    
    public var topSpots: [LocationScore] {
        topLocations
    }

    public var scoredLocations: [LocationScore] {
        topLocations
    }

    public func rank(of location: LocationScore) -> Int? {
        topLocations.firstIndex { $0.id == location.id }.map { $0 + 1 }
    }
    
    public init(
        centerLocation: CachedLocation,
        searchRadiusMiles: Double,
        gridSpacingMiles: Double,
        allScoredLocations: [LocationScore],
        topLocations: [LocationScore],
        moonInfo: MoonInfo,
        searchDate: Date,
        searchDuration: TimeInterval,
        suitabilityWarning: String? = nil
    ) {
        self.centerLocation = centerLocation
        self.searchRadiusMiles = searchRadiusMiles
        self.gridSpacingMiles = gridSpacingMiles
        self.allScoredLocations = allScoredLocations
        self.topLocations = topLocations
        self.moonInfo = moonInfo
        self.searchDate = searchDate
        self.searchDuration = searchDuration
        self.suitabilityWarning = suitabilityWarning
    }

    public init(
        centerLocation: CachedLocation,
        searchRadiusMiles: Double,
        gridSpacingMiles: Double,
        scoredLocations: [LocationScore],
        moonInfo: MoonInfo,
        searchDate: Date,
        searchDuration: TimeInterval,
        suitabilityWarning: String? = nil
    ) {
        self.init(
            centerLocation: centerLocation,
            searchRadiusMiles: searchRadiusMiles,
            gridSpacingMiles: gridSpacingMiles,
            allScoredLocations: scoredLocations,
            topLocations: scoredLocations,
            moonInfo: moonInfo,
            searchDate: searchDate,
            searchDuration: searchDuration,
            suitabilityWarning: suitabilityWarning
        )
    }
}
