import Foundation

public struct DeepSkyCatalogEntry: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let commonName: String
    public let catalogName: String
    public let objectType: DeepSkyObjectType
    public let constellation: String
    public let rightAscension: Double
    public let declination: Double
    /// Integrated visual magnitude when available; extended-object values are source-dependent.
    public let magnitude: Double
    public let apparentSize: String
    /// Approximate visual surface brightness in magnitudes per square arcminute, when available.
    public let surfaceBrightness: Double?
    /// App-specific observing difficulty heuristic on a 0...1 scale, not a catalog measurement.
    public let difficulty: Double
    public let observingIntent: TargetObservingIntent
    public let displayTypeNameOverride: String?
    public let recommendedEquipment: TargetEquipmentType
    public let notes: String

    public init(
        id: String,
        commonName: String,
        catalogName: String,
        objectType: DeepSkyObjectType,
        constellation: String,
        rightAscension: Double,
        declination: Double,
        magnitude: Double,
        apparentSize: String,
        surfaceBrightness: Double? = nil,
        difficulty: Double,
        observingIntent: TargetObservingIntent,
        recommendedEquipment: TargetEquipmentType,
        notes: String,
        displayTypeNameOverride: String? = nil
    ) {
        self.id = id
        self.commonName = commonName
        self.catalogName = catalogName
        self.objectType = objectType
        self.constellation = constellation
        self.rightAscension = rightAscension
        self.declination = declination
        self.magnitude = magnitude
        self.apparentSize = apparentSize
        self.surfaceBrightness = surfaceBrightness
        self.difficulty = min(max(difficulty, 0), 1)
        self.observingIntent = observingIntent
        self.displayTypeNameOverride = displayTypeNameOverride
        self.recommendedEquipment = recommendedEquipment
        self.notes = notes
    }
}

public protocol DeepSkyCatalogProviding: Sendable {
    func entries() -> [DeepSkyCatalogEntry]
}

public enum DeepSkyCatalogError: Error, Equatable, Sendable {
    case missingFile(String)
    case decode(String)
    case invalid(String)
    case missingBundledResources
    case missingContractsData(String)

    public var message: String {
        switch self {
        case .missingFile(let path):
            return "missing deep-sky catalog file: \(path)"
        case .decode(let detail):
            return "could not decode deep-sky catalog: \(detail)"
        case .invalid(let detail):
            return "invalid deep-sky catalog: \(detail)"
        case .missingBundledResources:
            return "AstroEngine deep-sky catalog JSON is missing from the application bundle. This is a packaging failure; rebuild so scripts/bundle-engine-data copies contracts/data/catalog into the product."
        case .missingContractsData(let detail):
            return "could not load deep-sky catalog from contracts/data: \(detail)"
        }
    }
}

/// Canonical curated catalog. Source-controlled JSON lives only under `contracts/data/catalog`.
public enum DeepSkyCatalog {
    public static let relativePath = "catalog/deep-sky.json"

    public static func loadResolved() throws -> [DeepSkyCatalogEntry] {
        #if os(iOS) || os(watchOS)
        guard let bundled = EngineCalibration.findBundledDataDirectory() else {
            throw DeepSkyCatalogError.missingBundledResources
        }
        return try load(fromDataDirectory: bundled)
        #else
        return try loadFromContractsRoot()
        #endif
    }

    public static func loadFromContractsRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> [DeepSkyCatalogEntry] {
        let root: URL
        do {
            root = try ContractsRoot.resolve(environment: environment, startingAt: start)
        } catch {
            throw DeepSkyCatalogError.missingContractsData(
                (error as? ContractsRootError)?.message ?? String(describing: error)
            )
        }
        return try load(fromDataDirectory: root.appendingPathComponent("data", isDirectory: true))
    }

    public static func load(fromDataDirectory dataRoot: URL) throws -> [DeepSkyCatalogEntry] {
        let url = dataRoot.appendingPathComponent(relativePath)
        let path = url.path
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw DeepSkyCatalogError.missingFile(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DeepSkyCatalogError.missingFile(path)
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DeepSkyCatalogError.decode(String(describing: error))
        }
        return try decodeDocument(raw)
    }

    public static func contractResult(from entries: [DeepSkyCatalogEntry]) -> [String: Any] {
        ["entries": entries.map(encodeContractEntry)]
    }

    static func decodeDocument(_ raw: Any) throws -> [DeepSkyCatalogEntry] {
        guard let object = raw as? [String: Any] else {
            throw DeepSkyCatalogError.invalid("deep-sky catalog must be a JSON object")
        }
        let extra = Set(object.keys).subtracting(["entries"])
        if !extra.isEmpty {
            throw DeepSkyCatalogError.invalid(
                "unexpected deep-sky catalog keys: \(extra.sorted())"
            )
        }
        guard let rows = object["entries"] as? [Any] else {
            throw DeepSkyCatalogError.invalid("deep-sky catalog entries must be an array")
        }
        return try rows.enumerated().map { index, item in
            try decodeEntry(item, index: index)
        }
    }

    private static let requiredKeys: Set<String> = [
        "id", "common_name", "catalog_name", "object_type", "constellation",
        "right_ascension", "declination", "magnitude", "apparent_size",
        "surface_brightness", "difficulty", "recommended_equipment",
        "observing_intent", "notes",
    ]
    private static let allowedKeys: Set<String> = requiredKeys.union(["display_type_name_override"])

    private static func decodeEntry(_ raw: Any, index: Int) throws -> DeepSkyCatalogEntry {
        let prefix = "entries[\(index)]"
        guard let object = raw as? [String: Any] else {
            throw DeepSkyCatalogError.invalid("\(prefix) must be an object")
        }
        let extra = Set(object.keys).subtracting(allowedKeys)
        if !extra.isEmpty {
            throw DeepSkyCatalogError.invalid("\(prefix) unexpected keys: \(extra.sorted())")
        }
        let missing = requiredKeys.subtracting(object.keys)
        if !missing.isEmpty {
            throw DeepSkyCatalogError.invalid("\(prefix) missing keys: \(missing.sorted())")
        }
        let override: String?
        if object.keys.contains("display_type_name_override") {
            if object["display_type_name_override"] is NSNull {
                override = nil
            } else {
                override = try requireString(object["display_type_name_override"], "\(prefix).display_type_name_override")
            }
        } else {
            override = nil
        }
        return DeepSkyCatalogEntry(
            id: try requireString(object["id"], "\(prefix).id"),
            commonName: try requireString(object["common_name"], "\(prefix).common_name"),
            catalogName: try requireString(object["catalog_name"], "\(prefix).catalog_name"),
            objectType: try objectType(object["object_type"], "\(prefix).object_type"),
            constellation: try requireString(object["constellation"], "\(prefix).constellation"),
            rightAscension: try requireDouble(object["right_ascension"], "\(prefix).right_ascension"),
            declination: try requireDouble(object["declination"], "\(prefix).declination"),
            magnitude: try requireDouble(object["magnitude"], "\(prefix).magnitude"),
            apparentSize: try requireString(object["apparent_size"], "\(prefix).apparent_size"),
            surfaceBrightness: try optionalDouble(object["surface_brightness"], "\(prefix).surface_brightness"),
            difficulty: try requireDouble(object["difficulty"], "\(prefix).difficulty"),
            observingIntent: try observingIntent(object["observing_intent"], "\(prefix).observing_intent"),
            recommendedEquipment: try equipment(object["recommended_equipment"], "\(prefix).recommended_equipment"),
            notes: try requireString(object["notes"], "\(prefix).notes"),
            displayTypeNameOverride: override
        )
    }

    private static func encodeContractEntry(_ entry: DeepSkyCatalogEntry) -> [String: Any] {
        var object: [String: Any] = [
            "id": entry.id,
            "common_name": entry.commonName,
            "catalog_name": entry.catalogName,
            "object_type": contractObjectType(entry.objectType),
            "constellation": entry.constellation,
            "right_ascension": entry.rightAscension,
            "declination": entry.declination,
            "magnitude": entry.magnitude,
            "apparent_size": entry.apparentSize,
            "surface_brightness": entry.surfaceBrightness as Any? ?? NSNull(),
            "difficulty": entry.difficulty,
            "recommended_equipment": contractEquipment(entry.recommendedEquipment),
            "observing_intent": entry.observingIntent.rawValue,
            "notes": entry.notes,
        ]
        if let override = entry.displayTypeNameOverride {
            object["display_type_name_override"] = override
        }
        return object
    }

    private static func objectType(_ value: Any?, _ name: String) throws -> DeepSkyObjectType {
        let raw = try requireString(value, name)
        switch raw {
        case "galaxy": return .galaxy
        case "diffuse_nebula": return .diffuseNebula
        case "globular_cluster": return .globularCluster
        case "open_cluster": return .openCluster
        case "double_star": return .doubleStar
        case "planetary_nebula": return .planetaryNebula
        default:
            throw DeepSkyCatalogError.invalid("\(name) is not a known catalog value")
        }
    }

    private static func equipment(_ value: Any?, _ name: String) throws -> TargetEquipmentType {
        let raw = try requireString(value, name)
        switch raw {
        case "naked_eye": return .nakedEye
        case "binoculars": return .binoculars
        case "small_telescope": return .smallTelescope
        case "telescope": return .telescope
        default:
            throw DeepSkyCatalogError.invalid("\(name) is not a known catalog value")
        }
    }

    private static func observingIntent(_ value: Any?, _ name: String) throws -> TargetObservingIntent {
        let raw = try requireString(value, name)
        guard let intent = TargetObservingIntent(rawValue: raw) else {
            throw DeepSkyCatalogError.invalid("\(name) is not a known catalog value")
        }
        return intent
    }

    private static func contractObjectType(_ type: DeepSkyObjectType) -> String {
        switch type {
        case .galaxy: return "galaxy"
        case .diffuseNebula: return "diffuse_nebula"
        case .globularCluster: return "globular_cluster"
        case .openCluster: return "open_cluster"
        case .doubleStar: return "double_star"
        case .planetaryNebula: return "planetary_nebula"
        }
    }

    private static func contractEquipment(_ type: TargetEquipmentType) -> String {
        switch type {
        case .nakedEye: return "naked_eye"
        case .binoculars: return "binoculars"
        case .smallTelescope: return "small_telescope"
        case .telescope: return "telescope"
        }
    }

    private static func requireString(_ value: Any?, _ name: String) throws -> String {
        guard let text = value as? String else {
            throw DeepSkyCatalogError.invalid("\(name) must be a string")
        }
        return text
    }

    private static func requireDouble(_ value: Any?, _ name: String) throws -> Double {
        guard let number = jsonDouble(value) else {
            throw DeepSkyCatalogError.invalid("\(name) must be a finite JSON number")
        }
        return number
    }

    private static func optionalDouble(_ value: Any?, _ name: String) throws -> Double? {
        if value == nil || value is NSNull { return nil }
        return try requireDouble(value, name)
    }

    private static func jsonDouble(_ value: Any?) -> Double? {
        if value is NSNull { return nil }
        if value is Bool { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return nil }
            let doubleValue = number.doubleValue
            return doubleValue.isFinite ? doubleValue : nil
        }
        if let number = value as? Double { return number.isFinite ? number : nil }
        if let number = value as? Int { return Double(number) }
        return nil
    }
}

public struct CuratedDeepSkyCatalogProvider: DeepSkyCatalogProviding {
    public init() {}

    public func entries() -> [DeepSkyCatalogEntry] {
        Self.catalog
    }

    private static let catalog: [DeepSkyCatalogEntry] = {
        do {
            return try DeepSkyCatalog.loadResolved()
        } catch {
            let detail = (error as? DeepSkyCatalogError)?.message ?? String(describing: error)
            fatalError("AstroEngine deep-sky catalog is missing or corrupt: \(detail)")
        }
    }()
}
