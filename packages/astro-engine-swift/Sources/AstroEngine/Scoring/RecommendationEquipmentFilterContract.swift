import CoreFoundation
import Foundation

public struct RecommendationEquipmentFilterInputError: Error, Sendable {
    public let code: String
    public let message: String

    init() {
        code = "validation"
        message = "invalid \(RecommendationEquipmentFilterContract.capabilityID) input"
    }

    init(rowCap maximum: Int, label: String) {
        code = "sample_cap"
        message = "\(RecommendationEquipmentFilterContract.capabilityID) exceeds the 1.0 \(label) cap (\(maximum) rows)"
    }
}

/// Strict JSON transport for equipment filtering of already-ranked rows.
public enum RecommendationEquipmentFilterContract {
    public static let capabilityID = RecommendationEquipmentFilter.capabilityID
    public static let maxCandidateCount = 1_440
    public static let maxCapabilityCount = 1_440

    private static let requirementKeys: Set<String> = [
        "naked_eye_suitability",
        "binocular_suitability",
        "preferred_binocular_magnification",
        "practical_binocular_aperture_mm",
        "preferred_binocular_aperture_mm",
        "practical_visual_aperture_mm",
        "preferred_visual_aperture_mm",
        "practical_smart_eaa_aperture_mm",
        "preferred_smart_eaa_aperture_mm",
        "framing",
        "magnification_benefit",
        "smart_eaa_suitability",
    ]

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys) == ["candidates", "capabilities", "has_saved_inventory", "minimum_fit"] else {
            throw RecommendationEquipmentFilterInputError()
        }

        // Both array caps are checked before either array is iterated.
        guard let rawCandidates = input["candidates"] as? [Any] else {
            throw RecommendationEquipmentFilterInputError()
        }
        guard rawCandidates.count <= maxCandidateCount else {
            throw RecommendationEquipmentFilterInputError(rowCap: maxCandidateCount, label: "candidate-row")
        }
        guard let rawCapabilities = input["capabilities"] as? [Any] else {
            throw RecommendationEquipmentFilterInputError()
        }
        guard rawCapabilities.count <= maxCapabilityCount else {
            throw RecommendationEquipmentFilterInputError(rowCap: maxCapabilityCount, label: "capability-row")
        }

        let hasSavedInventory = try boolean(input["has_saved_inventory"])
        let minimumFit = try enumValue(input["minimum_fit"], RecommendationEquipmentFitThreshold.self)
        let capabilities = try parseCapabilities(rawCapabilities)
        let candidates = try rawCandidates.map(parseCandidate)

        let selected = RecommendationEquipmentFilter.selected(
            candidates: candidates,
            capabilities: capabilities,
            hasSavedInventory: hasSavedInventory,
            minimumFit: minimumFit
        )
        return ["selected": selected.map { ["index": $0.index, "key": $0.key] as [String: Any] }]
    }

    private static func parseCandidate(_ value: Any) throws -> RecommendationEquipmentFilter.Candidate {
        guard let row = value as? [String: Any],
              Set(row.keys) == ["key", "is_planet", "requirement"],
              let requirementRow = row["requirement"] as? [String: Any],
              Set(requirementRow.keys) == requirementKeys else {
            throw RecommendationEquipmentFilterInputError()
        }
        return try RecommendationEquipmentFilter.Candidate(
            key: key(row["key"]),
            isPlanet: boolean(row["is_planet"]),
            requirement: requirement(requirementRow)
        )
    }

    private static func parseCapabilities(_ rows: [Any]) throws -> [EquipmentMatchCapability] {
        var seen = Set<Data>()
        return try rows.map { value in
            guard let row = value as? [String: Any],
                  Set(row.keys) == ["key", "type", "aperture_mm", "magnification"] else {
                throw RecommendationEquipmentFilterInputError()
            }
            let capabilityKey = try key(row["key"])
            guard seen.insert(Data(capabilityKey.utf8)).inserted else {
                throw RecommendationEquipmentFilterInputError()
            }
            let rawType = try string(row["type"])
            let type: EquipmentType?
            if rawType == "nakedEye" {
                type = nil
            } else {
                type = try enumValue(rawType, EquipmentType.self)
            }
            return EquipmentMatchCapability(
                key: capabilityKey,
                type: type,
                apertureMillimeters: try optionalNumber(row["aperture_mm"]),
                magnification: try optionalNumber(row["magnification"])
            )
        }
    }

    private static func requirement(_ row: [String: Any]) throws -> TargetEquipmentRequirement {
        let range: ClosedRange<Double>?
        if absent(row["preferred_binocular_magnification"]) {
            range = nil
        } else {
            guard let bounds = row["preferred_binocular_magnification"] as? [Any], bounds.count == 2 else {
                throw RecommendationEquipmentFilterInputError()
            }
            let lower = try number(bounds[0])
            let upper = try number(bounds[1])
            guard lower > 0, upper >= lower else { throw RecommendationEquipmentFilterInputError() }
            range = lower...upper
        }

        func thresholds(_ prefix: String) throws -> (Double?, Double?) {
            let practical = try optionalNumber(row["practical_\(prefix)_aperture_mm"])
            let preferred = try optionalNumber(row["preferred_\(prefix)_aperture_mm"])
            if let practical, practical <= 0 { throw RecommendationEquipmentFilterInputError() }
            if let preferred, preferred <= 0 { throw RecommendationEquipmentFilterInputError() }
            if let practical, let preferred, preferred < practical {
                throw RecommendationEquipmentFilterInputError()
            }
            return (practical, preferred)
        }

        let binocular = try thresholds("binocular")
        let visual = try thresholds("visual")
        let smart = try thresholds("smart_eaa")
        guard TargetEquipmentRequirement.hasValidSmartEAAApertureThresholds(
            practical: smart.0,
            preferred: smart.1
        ) else {
            throw RecommendationEquipmentFilterInputError()
        }

        return TargetEquipmentRequirement(
            nakedEyeSuitability: try enumValue(row["naked_eye_suitability"], NakedEyeSuitability.self),
            binocularSuitability: try enumValue(row["binocular_suitability"], BinocularSuitability.self),
            preferredBinocularMagnification: range,
            practicalBinocularApertureMillimeters: binocular.0,
            preferredBinocularApertureMillimeters: binocular.1,
            practicalVisualApertureMillimeters: visual.0,
            preferredVisualApertureMillimeters: visual.1,
            practicalSmartEAAApertureMillimeters: smart.0,
            preferredSmartEAAApertureMillimeters: smart.1,
            framing: try enumValue(row["framing"], TargetEquipmentFraming.self),
            magnificationBenefit: try boolean(row["magnification_benefit"]),
            smartEAASuitability: try enumValue(row["smart_eaa_suitability"], SmartEAASuitability.self)
        )
    }

    private static func absent(_ value: Any?) -> Bool { value == nil || value is NSNull }

    private static func string(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw RecommendationEquipmentFilterInputError() }
        return value
    }

    private static func key(_ value: Any?) throws -> String {
        let value = try string(value)
        guard !value.isEmpty else { throw RecommendationEquipmentFilterInputError() }
        return value
    }

    private static func boolean(_ value: Any?) throws -> Bool {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw RecommendationEquipmentFilterInputError()
        }
        return value.boolValue
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite,
              abs(value.doubleValue) <= 1_000_000_000 else {
            throw RecommendationEquipmentFilterInputError()
        }
        return value.doubleValue
    }

    private static func optionalNumber(_ value: Any?) throws -> Double? {
        try absent(value) ? nil : number(value)
    }

    private static func enumValue<T: RawRepresentable>(_ value: Any?, _ type: T.Type) throws -> T
    where T.RawValue == String {
        guard let parsed = T(rawValue: try string(value)) else {
            throw RecommendationEquipmentFilterInputError()
        }
        return parsed
    }
}
