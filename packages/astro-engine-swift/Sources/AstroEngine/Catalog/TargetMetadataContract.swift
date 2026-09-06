import Foundation
import CoreFoundation

public struct TargetMetadataInputError: Error, Sendable {
    public let message: String
}

/// Strict transport boundaries; host adapters call the typed resolver directly.
public enum TargetMetadataContract {
    public static func evaluate(_ capability: String, input: [String: Any]) throws -> [String: Any] {
        func invalid() -> TargetMetadataInputError { .init(message: "invalid \(capability) input") }
        switch capability {
        case "catalog.solar_system":
            guard input.isEmpty else { throw invalid() }
            return ["entries": try JSONSerialization.jsonObject(with: JSONEncoder().encode(TargetMetadata.solarSystemCandidates))]
        case "targets.moon_sensitivity":
            guard Set(input.keys).isSubset(of: ["object_type", "surface_brightness"]),
                  let raw = input["object_type"] as? String, let type = DeepSkyObjectType(rawValue: raw) else { throw invalid() }
            let brightness: Double?
            if input["surface_brightness"] == nil || input["surface_brightness"] is NSNull { brightness = nil }
            else {
                guard let n = input["surface_brightness"] as? NSNumber,
                      CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw invalid() }
                brightness = n.doubleValue
            }
            return ["sensitivity": TargetMetadata.moonSensitivity(objectType: type, surfaceBrightness: brightness)]
        case "targets.requirements":
            guard Set(input.keys).isSubset(of: ["id", "type", "object_type"]), let rawID = input["id"] as? String else { throw invalid() }
            let id = TargetMetadata.normalizedID(rawID)
            guard !id.isEmpty else { throw invalid() }
            let type: FrozenTargetType
            let objectType: DeepSkyObjectType?
            if let rawType = input["type"] {
                guard let raw = rawType as? String, ["moon", "planet", "deepSky"].contains(raw),
                      let parsed = FrozenTargetType(rawValue: raw) else { throw invalid() }
                type = parsed
                if input["object_type"] == nil || input["object_type"] is NSNull { objectType = nil }
                else {
                    guard let raw = input["object_type"] as? String, let parsed = DeepSkyObjectType(rawValue: raw) else { throw invalid() }
                    objectType = parsed
                }
            } else {
                guard input["object_type"] == nil else { throw invalid() }
                if let entry = CuratedDeepSkyCatalogProvider().entries().first(where: { $0.id == id }) {
                    type = .deepSky; objectType = entry.objectType
                } else if let entry = TargetMetadata.solarSystemCandidates.first(where: { $0.id == id }) {
                    type = entry.type; objectType = nil
                } else { throw invalid() }
            }
            return try TargetMetadata.requirementResult(id: id, type: type, objectType: objectType)
        default: throw invalid()
        }
    }
}
