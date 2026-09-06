import Foundation
import AstroEngine

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
            return .init(nakedEyeSuitability: .preferred, binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 100, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .medium, magnificationBenefit: true, smartEAASuitability: .supported)
        case .planet:
            let nakedEyePlanetIDs: Set<String> = ["mercury", "venus", "mars", "jupiter", "saturn"]
            let nakedEyeSuitability: NakedEyeSuitability = nakedEyePlanetIDs.contains(normalizedID(target.id)) ? .preferred : .unsupported
            return .init(nakedEyeSuitability: nakedEyeSuitability, binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 80, preferredVisualApertureMillimeters: 120, framing: .compact, magnificationBenefit: true)
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
        "m31": .init(nakedEyeSuitability: .challenging, binocularSuitability: .preferred, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 120, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 50, framing: .veryWide, smartEAASuitability: .preferred),
        "m42": .init(nakedEyeSuitability: .challenging, binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 150, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .wide, smartEAASuitability: .preferred),
        "m45": .init(nakedEyeSuitability: .preferred, binocularSuitability: .preferred, preferredBinocularMagnification: 7...10, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 80, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .veryWide, smartEAASuitability: .supported),
        "double-cluster": .init(binocularSuitability: .preferred, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 90, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .wide, smartEAASuitability: .supported),
        "m36": .init(binocularSuitability: .practical, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 100, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .medium, smartEAASuitability: .supported),
        "m38": .init(binocularSuitability: .preferred, preferredBinocularMagnification: 7...12, practicalBinocularApertureMillimeters: 42, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 60, preferredVisualApertureMillimeters: 90, practicalSmartEAAApertureMillimeters: 25, preferredSmartEAAApertureMillimeters: 40, framing: .wide, smartEAASuitability: .supported),
        "m77": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .compact, magnificationBenefit: true, smartEAASuitability: .preferred),
        "m51": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .medium, smartEAASuitability: .preferred),
        "m101": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .wide, smartEAASuitability: .preferred),
        "m33": .init(binocularSuitability: .practical, preferredBinocularMagnification: 7...10, practicalBinocularApertureMillimeters: 50, preferredBinocularApertureMillimeters: 70, practicalVisualApertureMillimeters: 125, preferredVisualApertureMillimeters: 200, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .wide, smartEAASuitability: .preferred),
        "m64": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 100, preferredVisualApertureMillimeters: 200, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .medium, smartEAASuitability: .preferred),
        "m20": .init(binocularSuitability: .practical, preferredBinocularMagnification: 15...20, practicalBinocularApertureMillimeters: 70, preferredBinocularApertureMillimeters: 70, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 150, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .wide, smartEAASuitability: .preferred),
        "albireo": .init(practicalVisualApertureMillimeters: 50, preferredVisualApertureMillimeters: 50, framing: .compact, magnificationBenefit: false),
        "epsilon-lyrae": .init(practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 100, framing: .compact, magnificationBenefit: true),
        "m57": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 75, preferredVisualApertureMillimeters: 125, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .compact, magnificationBenefit: true, smartEAASuitability: .preferred),
        "ngc7009": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 100, preferredVisualApertureMillimeters: 150, practicalSmartEAAApertureMillimeters: 30, preferredSmartEAAApertureMillimeters: 50, framing: .compact, magnificationBenefit: true, smartEAASuitability: .preferred),
        "ngc7293": .init(binocularSuitability: .unsuitable, practicalVisualApertureMillimeters: 150, preferredVisualApertureMillimeters: 250, practicalSmartEAAApertureMillimeters: 40, preferredSmartEAAApertureMillimeters: 70, framing: .veryWide, smartEAASuitability: .preferred),
        "jupiter": .init(nakedEyeSuitability: .preferred, binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 80, preferredVisualApertureMillimeters: 120, framing: .compact, magnificationBenefit: true),
        "saturn": .init(nakedEyeSuitability: .preferred, binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 80, preferredVisualApertureMillimeters: 120, framing: .compact, magnificationBenefit: true),
        "mars": .init(nakedEyeSuitability: .preferred, binocularSuitability: .practical, preferredBinocularMagnification: 10...15, practicalBinocularApertureMillimeters: 35, preferredBinocularApertureMillimeters: 50, practicalVisualApertureMillimeters: 90, preferredVisualApertureMillimeters: 150, framing: .compact, magnificationBenefit: true)
    ]
}

public extension ObservableTarget {
    var equipmentRequirement: TargetEquipmentRequirement {
        TargetEquipmentRequirements.requirement(for: self)
    }
}
