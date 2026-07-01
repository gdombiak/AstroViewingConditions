import Foundation

public enum ObservableTargetType: String, CaseIterable, Sendable, Codable, Hashable {
    case moon
    case planet
    case deepSky
    case satellite
    case meteorShower

    public var displayName: String {
        switch self {
        case .moon:
            return "Moon"
        case .planet:
            return "Planet"
        case .deepSky:
            return "Deep Sky"
        case .satellite:
            return "Satellite"
        case .meteorShower:
            return "Meteor Shower"
        }
    }
}

public enum TargetEquipmentType: String, CaseIterable, Sendable, Codable, Hashable {
    case nakedEye
    case binoculars
    case smallTelescope
    case telescope

    public var displayName: String {
        switch self {
        case .nakedEye:
            return "Naked eye"
        case .binoculars:
            return "Binoculars"
        case .smallTelescope:
            return "Small scope"
        case .telescope:
            return "Telescope"
        }
    }
}

public enum DeepSkyObjectType: String, CaseIterable, Sendable, Codable, Hashable {
    case galaxy
    case diffuseNebula
    case globularCluster
    case openCluster
    case doubleStar
    case planetaryNebula

    public var displayName: String {
        switch self {
        case .galaxy: return "Galaxy"
        case .diffuseNebula: return "Diffuse Nebula"
        case .globularCluster: return "Globular Cluster"
        case .openCluster: return "Open Cluster"
        case .doubleStar: return "Double Star"
        case .planetaryNebula: return "Planetary Nebula"
        }
    }
}

public struct ObservableTarget: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let name: String
    public let type: ObservableTargetType
    public let preferredEquipment: TargetEquipmentType
    public let difficulty: Double
    public let deepSkyObjectType: DeepSkyObjectType?
    public let moonInterferenceSensitivity: Double?

    public init(
        id: String,
        name: String,
        type: ObservableTargetType,
        preferredEquipment: TargetEquipmentType,
        difficulty: Double,
        deepSkyObjectType: DeepSkyObjectType? = nil,
        moonInterferenceSensitivity: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.preferredEquipment = preferredEquipment
        self.difficulty = min(max(difficulty, 0), 1)
        self.deepSkyObjectType = deepSkyObjectType
        self.moonInterferenceSensitivity = moonInterferenceSensitivity.map { min(max($0, 0), 1.5) }
    }

    public var displayTypeName: String {
        guard type == .deepSky else { return type.displayName }

        switch deepSkyObjectType {
        case .galaxy: return "Galaxy"
        case .diffuseNebula: return "Nebula"
        case .globularCluster: return "Globular Cluster"
        case .openCluster: return "Open Cluster"
        case .doubleStar: return "Double Star"
        case .planetaryNebula: return "Planetary Nebula"
        case nil: return type.displayName
        }
    }
}

public struct TargetVisibilityWindow: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let start: Date
    public let end: Date
    public let bestTime: Date
    public let maxAltitude: Double?
    public let direction: String?
    public let azimuth: Double?

    public init(
        id: String? = nil,
        start: Date,
        end: Date,
        bestTime: Date,
        maxAltitude: Double?,
        direction: String?,
        azimuth: Double? = nil
    ) {
        self.id = id ?? "\(start.timeIntervalSince1970.bitPattern)-\(end.timeIntervalSince1970.bitPattern)-\(direction ?? "")"
        self.start = start
        self.end = end
        self.bestTime = bestTime
        self.maxAltitude = maxAltitude
        self.direction = direction
        self.azimuth = azimuth
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

public enum TargetRecommendationReason: String, CaseIterable, Sendable, Codable, Hashable {
    case highAltitude
    case astronomicalDarkness
    case goodNightQuality
    case moonInterference
    case poorWeather
    case lowAltitude
    case difficultTarget
    case outsideAstronomicalDarkness
    case excellentMoonCraterDetail
    case brightFullMoonDeepSkyImpact
    case newMoonDarkSky
    case moonSetsEarlyDarkSkyLater
    case moonBelowUsefulWindow
    case moonVisibleUsefulWindow
    case convenientPlanetWindow
    case lateOrEarlyPlanetWindow
    case planetMoonlightResistant

    public var message: String {
        switch self {
        case .highAltitude:
            return "High in the sky during the best window."
        case .astronomicalDarkness:
            return "Visible during astronomical darkness."
        case .goodNightQuality:
            return "Weather and sky quality look favorable."
        case .moonInterference:
            return "Moonlight may reduce deep-sky contrast."
        case .poorWeather:
            return "Clouds or haze may reduce visibility."
        case .lowAltitude:
            return "Lower in the sky, so horizon obstructions may matter."
        case .difficultTarget:
            return "Best with more capable equipment."
        case .outsideAstronomicalDarkness:
            return "Best visibility falls outside astronomical darkness."
        case .excellentMoonCraterDetail:
            return "Excellent for crater detail near first quarter."
        case .brightFullMoonDeepSkyImpact:
            return "Bright full Moon; good lunar target but poor for faint deep-sky objects."
        case .newMoonDarkSky:
            return "New Moon is poor for lunar observing but favorable for deep-sky darkness."
        case .moonSetsEarlyDarkSkyLater:
            return "Moon sets early, leaving a darker deep-sky window later."
        case .moonBelowUsefulWindow:
            return "Moon is below the horizon during most of the useful observing window."
        case .moonVisibleUsefulWindow:
            return "Moon is visible during the useful observing window."
        case .convenientPlanetWindow:
            return "Visible during convenient evening observing hours."
        case .lateOrEarlyPlanetWindow:
            return "Best visibility is late at night or before dawn."
        case .planetMoonlightResistant:
            return "Bright planets are only mildly affected by moonlight."
        }
    }
}

public struct TargetRecommendation: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let target: ObservableTarget
    public let score: Int
    public let visibilityWindow: TargetVisibilityWindow
    public let reasons: [TargetRecommendationReason]
    public let summary: String

    public init(
        id: String? = nil,
        target: ObservableTarget,
        score: Int,
        visibilityWindow: TargetVisibilityWindow,
        reasons: [TargetRecommendationReason],
        summary: String
    ) {
        self.id = id ?? "\(target.id)-\(visibilityWindow.id)"
        self.target = target
        self.score = min(max(score, 0), 100)
        self.visibilityWindow = visibilityWindow
        self.reasons = reasons
        self.summary = summary
    }
}
