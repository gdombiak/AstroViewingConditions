import Foundation
import CoreFoundation

public struct Phase15InputError: Error, Sendable {
    public let message: String
}

/// JSON adapters validate transport facts; typed scoring/matching stays reusable by Apple hosts.
public enum Phase15Contracts {
    public static func targets(_ input: [String: Any]) throws -> [String: Any] {
        do { return try recommend(input) }
        catch is InputError { throw Phase15InputError(message: "invalid targets.recommend input") }
    }

    public static func equipment(_ input: [String: Any]) throws -> [String: Any] {
        do { return try match(input) }
        catch is InputError { throw Phase15InputError(message: "invalid equipment.match input") }
    }

    private static func recommend(_ input: [String: Any]) throws -> [String: Any] {
        let darkness = try object(input["darkness_window"])
        let darknessStart = try date(darkness["start"]), darknessEnd = try date(darkness["end"])
        let cloud = try number(input["cloud_cover_score"])
        let moon = try object(input["moon"])
        let moonAltitude = try number(moon["altitude"]), illumination = try number(moon["illumination"])
        guard illumination.rounded(.towardZero) == illumination else { throw InputError.invalid }
        let hours = try array(input["hourly_ratings"]).map { row -> (time: Date, score: Double) in
            let row = try object(row)
            return (try date(row["time"]), try number(row["score"]))
        }
        let limitValue = try number(input["limit"] ?? 5)
        guard limitValue >= 0, limitValue.rounded(.towardZero) == limitValue else { throw InputError.invalid }
        var keys: [String] = [], scores: [Int] = [], times: [Date] = []
        var seen = Set<Data>()
        for value in try array(input["candidates"]) {
            let row = try object(value), key = try key(row["key"])
            guard seen.insert(Data(key.utf8)).inserted,
                  let type = FrozenTargetType(rawValue: try string(row["type"])) else { throw InputError.invalid }
            let objectType: DeepSkyObjectType?
            if absent(row["object_type"]) { objectType = nil }
            else {
                guard let value = DeepSkyObjectType(rawValue: try string(row["object_type"])) else { throw InputError.invalid }
                objectType = value
            }
            let window = try object(row["window"])
            let bestTime = try date(window["best_time"])
            let result = try TargetScoring.score(type: type, objectType: objectType,
                difficulty: number(row["difficulty"]), sensitivity: optionalNumber(row["sensitivity"]),
                maxAltitude: optionalNumber(window["max_altitude"]), start: date(window["start"]), end: date(window["end"]),
                darknessStart: darknessStart, darknessEnd: darknessEnd, cloudCoverScore: cloud,
                hourlyRatings: hours, moonAltitude: moonAltitude, moonIllumination: illumination)
            keys.append(key); scores.append(result.score); times.append(bestTime)
        }
        let indices = TargetScoring.rankedIndices(scores: scores, bestTimes: times, limit: Int(limitValue))
        return ["recommendations": indices.map { ["key": keys[$0], "score": scores[$0]] as [String: Any] }]
    }

    private static func match(_ input: [String: Any]) throws -> [String: Any] {
        let row = try object(input["requirement"])
        let naked = try enumValue(row["naked_eye_suitability"] ?? "unsupported", NakedEyeSuitability.self)
        let binocular = try enumValue(row["binocular_suitability"] ?? "unsuitable", BinocularSuitability.self)
        let smart = try enumValue(row["smart_eaa_suitability"] ?? "poorMatch", SmartEAASuitability.self)
        let framing = try enumValue(row["framing"] ?? "medium", TargetEquipmentFraming.self)
        let benefit = try boolean(row["magnification_benefit"] ?? false)
        let range: ClosedRange<Double>?
        if absent(row["preferred_binocular_magnification"]) { range = nil }
        else {
            let bounds = try array(row["preferred_binocular_magnification"])
            guard bounds.count == 2 else { throw InputError.invalid }
            let lower = try number(bounds[0]), upper = try number(bounds[1])
            guard lower > 0, upper >= lower else { throw InputError.invalid }
            range = lower...upper
        }
        func thresholds(_ prefix: String) throws -> (Double?, Double?) {
            let practical = try optionalNumber(row["practical_\(prefix)_aperture_mm"])
            let preferred = try optionalNumber(row["preferred_\(prefix)_aperture_mm"])
            // Partial visual/binocular requirements are meaningful unknown requirements.
            if let practical, practical <= 0 { throw InputError.invalid }
            if let preferred, preferred <= 0 { throw InputError.invalid }
            if let practical, let preferred, preferred < practical { throw InputError.invalid }
            return (practical, preferred)
        }
        let b = try thresholds("binocular"), v = try thresholds("visual"), s = try thresholds("smart_eaa")
        guard TargetEquipmentRequirement.hasValidSmartEAAApertureThresholds(practical: s.0, preferred: s.1) else { throw InputError.invalid }
        let requirement = TargetEquipmentRequirement(nakedEyeSuitability: naked, binocularSuitability: binocular,
            preferredBinocularMagnification: range, practicalBinocularApertureMillimeters: b.0,
            preferredBinocularApertureMillimeters: b.1, practicalVisualApertureMillimeters: v.0,
            preferredVisualApertureMillimeters: v.1, practicalSmartEAAApertureMillimeters: s.0,
            preferredSmartEAAApertureMillimeters: s.1, framing: framing, magnificationBenefit: benefit, smartEAASuitability: smart)
        var seen = Set<Data>()
        let capabilities = try array(input["capabilities"]).map { value -> EquipmentMatchCapability in
            let row = try object(value), key = try key(row["key"]), raw = try string(row["type"])
            guard seen.insert(Data(key.utf8)).inserted else { throw InputError.invalid }
            let type: EquipmentType? = raw == "nakedEye" ? nil : try enumValue(raw, EquipmentType.self)
            return try EquipmentMatchCapability(key: key, type: type, apertureMillimeters: optionalNumber(row["aperture_mm"]), magnification: optionalNumber(row["magnification"]))
        }
        let ranked = try EquipmentMatchingRules().ranked(isPlanet: boolean(input["is_planet"] ?? false), requirement: requirement, capabilities: capabilities)
        guard let best = ranked.first else { return ["match": NSNull()] }
        return ["match": ["key": best.capability.key, "level": best.level.rawValue,
            "reason": best.reason.rawValue, "mode": best.mode.rawValue,
            "other_suitable_keys": ranked.dropFirst().filter { $0.level == .excellent || $0.level == .good }.map(\.capability.key)] as [String: Any]]
    }

    private enum InputError: Error { case invalid }
    private static func absent(_ x: Any?) -> Bool { x == nil || x is NSNull }
    private static func object(_ x: Any?) throws -> [String: Any] {
        guard let x = x as? [String: Any] else { throw InputError.invalid }; return x
    }
    private static func array(_ x: Any?) throws -> [Any] {
        guard let x = x as? [Any] else { throw InputError.invalid }; return x
    }
    private static func string(_ x: Any?) throws -> String {
        guard let x = x as? String else { throw InputError.invalid }; return x
    }
    private static func key(_ x: Any?) throws -> String {
        let x = try string(x); guard !x.isEmpty else { throw InputError.invalid }; return x
    }
    private static func number(_ x: Any?) throws -> Double {
        guard let x = x as? NSNumber, CFGetTypeID(x) != CFBooleanGetTypeID(), x.doubleValue.isFinite,
              abs(x.doubleValue) <= 1_000_000_000 else { throw InputError.invalid }; return x.doubleValue
    }
    private static func optionalNumber(_ x: Any?) throws -> Double? { try absent(x) ? nil : number(x) }
    private static func boolean(_ x: Any?) throws -> Bool {
        guard let x = x as? NSNumber, CFGetTypeID(x) == CFBooleanGetTypeID() else { throw InputError.invalid }; return x.boolValue
    }
    private static func enumValue<T: RawRepresentable>(_ x: Any?, _ type: T.Type) throws -> T where T.RawValue == String {
        guard let value = T(rawValue: try string(x)) else { throw InputError.invalid }; return value
    }
    private static func date(_ x: Any?) throws -> Date {
        guard let date = NightConditionsEnvelope.parseUTCInstant(x) else { throw InputError.invalid }; return date
    }
}
