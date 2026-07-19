import Foundation

public enum TargetEquipmentFraming: String, Codable, Sendable, Hashable {
    case veryWide
    case wide
    case medium
    case compact
}

public enum BinocularSuitability: String, Codable, Sendable, Hashable {
    case unsuitable
    case practical
    case preferred
}

/// Whether electronically assisted observing is a poor fit, supported, or a
/// particularly helpful way to observe the target.
public enum SmartEAASuitability: String, Codable, Sendable, Hashable {
    case poorMatch
    case supported
    case preferred
}

public struct TargetEquipmentRequirement: Sendable, Hashable, Codable {
    public let nakedEyeSuitable: Bool
    public let binocularSuitability: BinocularSuitability
    public let preferredBinocularMagnification: ClosedRange<Double>?
    public let practicalBinocularApertureMillimeters: Double?
    public let preferredBinocularApertureMillimeters: Double?
    public let practicalVisualApertureMillimeters: Double?
    public let preferredVisualApertureMillimeters: Double?
    public let practicalSmartEAAApertureMillimeters: Double?
    public let preferredSmartEAAApertureMillimeters: Double?
    public let framing: TargetEquipmentFraming
    public let magnificationBenefit: Bool
    public let smartEAASuitability: SmartEAASuitability

    public init(
        nakedEyeSuitable: Bool = false,
        binocularSuitability: BinocularSuitability = .unsuitable,
        preferredBinocularMagnification: ClosedRange<Double>? = nil,
        practicalBinocularApertureMillimeters: Double? = nil,
        preferredBinocularApertureMillimeters: Double? = nil,
        practicalVisualApertureMillimeters: Double? = nil,
        preferredVisualApertureMillimeters: Double? = nil,
        practicalSmartEAAApertureMillimeters: Double? = nil,
        preferredSmartEAAApertureMillimeters: Double? = nil,
        framing: TargetEquipmentFraming = .medium,
        magnificationBenefit: Bool = false,
        smartEAASuitability: SmartEAASuitability = .poorMatch
    ) {
        self.nakedEyeSuitable = nakedEyeSuitable
        self.binocularSuitability = binocularSuitability
        self.preferredBinocularMagnification = preferredBinocularMagnification
        self.practicalBinocularApertureMillimeters = practicalBinocularApertureMillimeters
        self.preferredBinocularApertureMillimeters = preferredBinocularApertureMillimeters
        self.practicalVisualApertureMillimeters = practicalVisualApertureMillimeters
        self.preferredVisualApertureMillimeters = preferredVisualApertureMillimeters
        precondition(
            (practicalSmartEAAApertureMillimeters != nil) == (preferredSmartEAAApertureMillimeters != nil),
            "Smart/EAA practical and preferred aperture thresholds must be provided together."
        )
        precondition(
            Self.hasValidSmartEAAApertureThresholds(
                practical: practicalSmartEAAApertureMillimeters,
                preferred: preferredSmartEAAApertureMillimeters
            ),
            "Smart/EAA aperture thresholds must be finite, positive, and ordered from practical to preferred."
        )
        self.practicalSmartEAAApertureMillimeters = practicalSmartEAAApertureMillimeters
        self.preferredSmartEAAApertureMillimeters = preferredSmartEAAApertureMillimeters
        self.framing = framing
        self.magnificationBenefit = magnificationBenefit
        self.smartEAASuitability = smartEAASuitability
    }

    static func hasValidSmartEAAApertureThresholds(
        practical: Double?,
        preferred: Double?
    ) -> Bool {
        switch (practical, preferred) {
        case (nil, nil):
            return true
        case let (practical?, preferred?):
            return practical.isFinite
                && practical > 0
                && preferred.isFinite
                && preferred > 0
                && preferred >= practical
        default:
            return false
        }
    }
}

/// Catalog-driven metadata with conservative type fallbacks and overrides for
/// targets whose framing or surface brightness changes the observing advice.
public enum TargetEquipmentRequirements {
    public static func requirement(for target: ObservableTarget) -> TargetEquipmentRequirement {
        overrides[normalizedID(target.id)] ?? fallback(for: target)
    }

    private static func normalizedID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func fallback(for target: ObservableTarget) -> TargetEquipmentRequirement {
        switch target.type {
        case .moon:
            return .init(nakedEyeSuitable: true, binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 100, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .medium, magnificationBenefit: true, smartEAASuitability: .supported)
        case .planet:
            let nakedEyePlanetIDs: Set<String> = ["mercury", "venus", "mars", "jupiter", "saturn"]
            return .init(nakedEyeSuitable: nakedEyePlanetIDs.contains(normalizedID(target.id)), binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 80, preferredVisualApertureMillimeters: 120, framing: .compact, magnificationBenefit: true)
        case .deepSky:
            switch target.deepSkyObjectType {
            case .openCluster:
                return .init(binocularSuitability: .preferred, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 100, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .wide, smartEAASuitability: .supported)
            case .globularCluster:
                return .init(binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 50, preferredBinocularApertureMillimeters: 70, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 130, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .medium, magnificationBenefit: true, smartEAASuitability: .supported)
            case .doubleStar:
                return .init(practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 100, framing: .compact, magnificationBenefit: true)
            case .planetaryNebula:
                return .init(binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 50, preferredBinocularApertureMillimeters: 70, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 130, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .compact, magnificationBenefit: true, smartEAASuitability: .preferred)
            case .diffuseNebula:
                return .init(binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 150, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .wide, smartEAASuitability: .preferred)
            case .galaxy:
                return .init(binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 50, preferredBinocularApertureMillimeters: 70, practicalVisualApertureMillimeters: 100, preferredVisualApertureMillimeters: 200, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .medium, smartEAASuitability: .preferred)
            case nil:
                return .init()
            }
        default:
            return .init()
        }
    }

    private static let overrides: [String: TargetEquipmentRequirement] = [
        "m31": .init(binocularSuitability: .preferred, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 120, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 50, framing: .veryWide, smartEAASuitability: .preferred),
        "m45": .init(nakedEyeSuitable: true, binocularSuitability: .preferred, preferredBinocularMagnification: 7...10, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 80, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .veryWide, smartEAASuitability: .supported),
        "double-cluster": .init(binocularSuitability: .preferred, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 90, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .wide, smartEAASuitability: .supported),
        "m36": .init(binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 100, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .medium, smartEAASuitability: .supported),
        "m38": .init(binocularSuitability: .preferred, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 90, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .wide, smartEAASuitability: .supported),
        "m77": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .compact, magnificationBenefit: true, smartEAASuitability: .preferred),
        "m51": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .medium, smartEAASuitability: .preferred),
        "m101": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .wide, smartEAASuitability: .preferred),
        "m33": .init(binocularSuitability: .practical, preferredBinocularMagnification: 7...10, practicalBinocularApertureMillimeters: 50, preferredBinocularApertureMillimeters: 70, practicalVisualApertureMillimeters: 125, preferredVisualApertureMillimeters: 200, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .wide, smartEAASuitability: .preferred),
        "m57": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 125, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .compact, magnificationBenefit: true, smartEAASuitability: .preferred),
        "ngc7009": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 100, preferredVisualApertureMillimeters: 150, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .compact, magnificationBenefit: true, smartEAASuitability: .preferred),
        "ngc7293": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .veryWide, smartEAASuitability: .preferred),
        "jupiter": .init(nakedEyeSuitable: true, binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 80, preferredVisualApertureMillimeters: 120, framing: .compact, magnificationBenefit: true),
        "saturn": .init(nakedEyeSuitable: true, binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 80, preferredVisualApertureMillimeters: 120, framing: .compact, magnificationBenefit: true),
        "mars": .init(nakedEyeSuitable: true, binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 90, preferredVisualApertureMillimeters: 150, framing: .compact, magnificationBenefit: true)
    ]
}

public extension ObservableTarget {
    var equipmentRequirement: TargetEquipmentRequirement {
        TargetEquipmentRequirements.requirement(for: self)
    }
}
