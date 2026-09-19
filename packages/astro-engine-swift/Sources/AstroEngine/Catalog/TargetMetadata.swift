import Foundation

/// Product metadata only. No positions, windows, scores, or presentation text.
public struct SolarSystemCandidate: Codable, Sendable {
    public let id: String
    public let type: FrozenTargetType
    public let preferredEquipment: TargetEquipmentType
    public let difficulty: Double
    public let observingIntent: TargetObservingIntent
    enum CodingKeys: String, CodingKey {
        case id, type, difficulty
        case preferredEquipment = "preferred_equipment"
        case observingIntent = "observing_intent"
    }
}

private struct RequirementRecord: Codable, Sendable {
    var nakedEyeSuitability: NakedEyeSuitability
    let binocularSuitability: BinocularSuitability
    let preferredBinocularMagnification: [Double]?
    let practicalBinocularApertureMillimeters: Double?
    let preferredBinocularApertureMillimeters: Double?
    let practicalVisualApertureMillimeters: Double?
    let preferredVisualApertureMillimeters: Double?
    let practicalSmartEAAApertureMillimeters: Double?
    let preferredSmartEAAApertureMillimeters: Double?
    let framing: TargetEquipmentFraming
    let magnificationBenefit: Bool
    let smartEAASuitability: SmartEAASuitability
    enum CodingKeys: String, CodingKey {
        case nakedEyeSuitability = "naked_eye_suitability"
        case binocularSuitability = "binocular_suitability"
        case preferredBinocularMagnification = "preferred_binocular_magnification"
        case practicalBinocularApertureMillimeters = "practical_binocular_aperture_mm"
        case preferredBinocularApertureMillimeters = "preferred_binocular_aperture_mm"
        case practicalVisualApertureMillimeters = "practical_visual_aperture_mm"
        case preferredVisualApertureMillimeters = "preferred_visual_aperture_mm"
        case practicalSmartEAAApertureMillimeters = "practical_smart_eaa_aperture_mm"
        case preferredSmartEAAApertureMillimeters = "preferred_smart_eaa_aperture_mm"
        case framing = "framing"
        case magnificationBenefit = "magnification_benefit"
        case smartEAASuitability = "smart_eaa_suitability"
    }
    var requirement: TargetEquipmentRequirement {
        .init(
            nakedEyeSuitability: nakedEyeSuitability,
            binocularSuitability: binocularSuitability,
            preferredBinocularMagnification: preferredBinocularMagnification.map { $0[0]...$0[1] },
            practicalBinocularApertureMillimeters: practicalBinocularApertureMillimeters,
            preferredBinocularApertureMillimeters: preferredBinocularApertureMillimeters,
            practicalVisualApertureMillimeters: practicalVisualApertureMillimeters,
            preferredVisualApertureMillimeters: preferredVisualApertureMillimeters,
            practicalSmartEAAApertureMillimeters: practicalSmartEAAApertureMillimeters,
            preferredSmartEAAApertureMillimeters: preferredSmartEAAApertureMillimeters,
            framing: framing,
            magnificationBenefit: magnificationBenefit,
            smartEAASuitability: smartEAASuitability
        )
    }
}

extension FrozenTargetType: Codable {}

public enum TargetMetadata {
    private struct Requirements: Decodable, Sendable {
        let `default`: RequirementRecord
        let fallbacks: [String: RequirementRecord]
        let overrides: [String: RequirementRecord]
        let naked_eye_planet_ids: [String]
    }
    private struct SolarCatalog: Decodable, Sendable { let entries: [SolarSystemCandidate] }

    private static func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        #if os(iOS) || os(watchOS)
        guard let root = EngineCalibration.findBundledDataDirectory() else {
            throw DeepSkyCatalogError.missingBundledResources
        }
        #else
        let root = try ContractsRoot.resolve().appendingPathComponent("data")
        #endif
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: root.appendingPathComponent("catalog/\(name).json")))
    }

    private static let requirements: Requirements = {
        do { return try load("target-requirements", as: Requirements.self) }
        catch { preconditionFailure("Missing or invalid canonical target requirements: \(error)") }
    }()

    public static let solarSystemCandidates: [SolarSystemCandidate] = {
        do { return try load("solar-system", as: SolarCatalog.self).entries }
        catch { preconditionFailure("Missing or invalid canonical solar-system catalog: \(error)") }
    }()

    public static func normalizedID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Overrides replace the entire fallback, even when a supplied type disagrees.
    public static func requirement(id: String, type: FrozenTargetType,
                                   objectType: DeepSkyObjectType? = nil) -> TargetEquipmentRequirement {
        record(id: id, type: type, objectType: objectType).requirement
    }

    private static func record(id: String, type: FrozenTargetType,
                               objectType: DeepSkyObjectType?) -> RequirementRecord {
        let id = normalizedID(id)
        if let override = requirements.overrides[id] { return override }
        let key = type == .deepSky ? objectType?.rawValue : type.rawValue
        var fallback = key.flatMap { requirements.fallbacks[$0] } ?? requirements.default
        if type == .planet, requirements.naked_eye_planet_ids.contains(id) {
            // Only naked-eye suitability changes for the planet fallback.
            fallback.nakedEyeSuitability = .preferred
        }
        return fallback
    }

    public static func moonSensitivity(objectType: DeepSkyObjectType, surfaceBrightness: Double?) -> Double {
        let sensitivity = EngineCalibration.current.targetScoring.moon.deep_sky_interference_sensitivity
        guard objectType == .planetaryNebula else { return sensitivity.non_planetary_nebula }
        guard let surfaceBrightness else { return sensitivity.default }
        let nebula = sensitivity.planetary_nebula_by_surface_brightness
        if surfaceBrightness <= nebula.high_surface_brightness_max { return nebula.high_surface_brightness_sensitivity }
        if surfaceBrightness >= nebula.low_surface_brightness_min { return nebula.low_surface_brightness_sensitivity }
        return nebula.mid_sensitivity
    }

    static func requirementResult(id: String, type: FrozenTargetType, objectType: DeepSkyObjectType?) throws -> [String: Any] {
        let value = record(id: id, type: type, objectType: objectType)
        var row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        for key in ["preferred_binocular_magnification", "practical_binocular_aperture_mm", "preferred_binocular_aperture_mm",
                    "practical_visual_aperture_mm", "preferred_visual_aperture_mm", "practical_smart_eaa_aperture_mm", "preferred_smart_eaa_aperture_mm"] {
            if row[key] == nil { row[key] = NSNull() }
        }
        return ["requirement": row, "is_planet": type == .planet]
    }
}
