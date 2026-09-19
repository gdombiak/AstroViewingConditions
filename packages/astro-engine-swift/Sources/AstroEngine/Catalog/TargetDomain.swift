import Foundation

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

public enum TargetObservingIntent: String, CaseIterable, Sendable, Codable, Hashable {
    case easy
    case standard
    case challenge

    public var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .standard: return "Standard"
        case .challenge: return "Challenge"
        }
    }
}
