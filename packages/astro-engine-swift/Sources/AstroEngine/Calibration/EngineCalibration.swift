import Foundation

public enum EngineCalibrationError: Error, Equatable, Sendable {
    case missingFile(String)
    case decode(String, String)
    case invalid(String)
    case missingBundledResources
    case missingContractsData(String)

    public var message: String {
        switch self {
        case .missingFile(let path):
            return "missing engine calibration file: \(path)"
        case .decode(let path, let detail):
            return "could not decode engine calibration \(path): \(detail)"
        case .invalid(let detail):
            return "invalid engine calibration: \(detail)"
        case .missingBundledResources:
            return "AstroEngine calibration JSON is missing from the application bundle. This is a packaging failure; rebuild so scripts/bundle-engine-data copies contracts/data/calibration into the product."
        case .missingContractsData(let detail):
            return "could not load engine calibration from contracts/data: \(detail)"
        }
    }
}

/// Immutable snapshot of the scoring calibration domains bound in production.
///
/// Canonical source-controlled files live only under `contracts/data/calibration`.
/// Production iOS/watchOS read a generated copy from the resource bundle.
/// Package tests and `astro-engine-eval` read the canonical files via `CONTRACTS_ROOT`.
public struct EngineCalibration: Hashable, Sendable {
    public let observingQuality: ObservingQualityCalibration
    public let nightQuality: NightQualityCalibration
    public let fog: FogCalibration
    public let seeing: SeeingCalibration
    public let equipmentMatching: EquipmentMatchingCalibration
    public let targetScoring: TargetScoringCalibration
    public let transparency: TransparencyCalibration

    /// Production/default snapshot, loaded once.
    ///
    /// Missing or corrupt bundled resources are a packaging failure and trap.
    /// The throwing `load` APIs remain independently testable.
    public static let current: EngineCalibration = {
        do {
            return try loadResolved()
        } catch {
            let detail = (error as? EngineCalibrationError)?.message ?? String(describing: error)
            fatalError("AstroEngine calibration is missing or corrupt: \(detail)")
        }
    }()

    public static func load(fromDataDirectory dataRoot: URL) throws -> EngineCalibration {
        let calibrationDir = dataRoot.appendingPathComponent("calibration", isDirectory: true)
        let observingQuality: ObservingQualityCalibration = try decode(
            ObservingQualityCalibration.self,
            from: calibrationDir.appendingPathComponent("observing-quality.json")
        )
        let nightQuality: NightQualityCalibration = try decode(
            NightQualityCalibration.self,
            from: calibrationDir.appendingPathComponent("night-quality.json")
        )
        let fog: FogCalibration = try decode(
            FogCalibration.self,
            from: calibrationDir.appendingPathComponent("fog.json")
        )
        let seeing: SeeingCalibration = try decode(
            SeeingCalibration.self,
            from: calibrationDir.appendingPathComponent("seeing.json")
        )
        let transparency: TransparencyCalibration = try decode(
            TransparencyCalibration.self,
            from: calibrationDir.appendingPathComponent("transparency.json")
        )

        let equipmentMatching = try decode(EquipmentMatchingCalibration.self,
            from: calibrationDir.appendingPathComponent("equipment-matching.json"))
        let targetScoring = try decode(TargetScoringCalibration.self,
            from: calibrationDir.appendingPathComponent("target-scoring.json"))
        try targetScoring.validate()
        try observingQuality.validate()
        try nightQuality.validate()
        try fog.validate()
        try seeing.validate()
        try transparency.validate()

        return EngineCalibration(
            observingQuality: observingQuality,
            nightQuality: nightQuality,
            fog: fog,
            seeing: seeing,
            equipmentMatching: equipmentMatching,
            targetScoring: targetScoring,
            transparency: transparency
        )
    }

    public static func loadFromContractsRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startingAt start: URL = URL(fileURLWithPath: #filePath)
    ) throws -> EngineCalibration {
        let root: URL
        do {
            root = try ContractsRoot.resolve(environment: environment, startingAt: start)
        } catch {
            throw EngineCalibrationError.missingContractsData(
                (error as? ContractsRootError)?.message ?? String(describing: error)
            )
        }
        return try load(fromDataDirectory: root.appendingPathComponent("data", isDirectory: true))
    }

    static func loadResolved() throws -> EngineCalibration {
        #if os(iOS) || os(watchOS)
        guard let bundled = findBundledDataDirectory() else {
            throw EngineCalibrationError.missingBundledResources
        }
        return try load(fromDataDirectory: bundled)
        #else
        return try loadFromContractsRoot()
        #endif
    }

    static func findBundledDataDirectory() -> URL? {
        var bundles: [Bundle] = []
        #if SWIFT_PACKAGE
        bundles.append(Bundle.module)
        #endif
        bundles.append(Bundle(for: EngineCalibrationBundleToken.self))
        bundles.append(Bundle.main)
        bundles.append(contentsOf: Bundle.allFrameworks)
        bundles.append(contentsOf: Bundle.allBundles)

        var seen: Set<String> = []
        for bundle in bundles {
            let path = bundle.bundlePath
            if seen.contains(path) { continue }
            seen.insert(path)
            if let directory = dataDirectory(in: bundle) {
                return directory
            }
        }
        return nil
    }

    private static func dataDirectory(in bundle: Bundle) -> URL? {
        if let url = bundle.url(
            forResource: "observing-quality",
            withExtension: "json",
            subdirectory: "data/calibration"
        ) {
            return url.deletingLastPathComponent().deletingLastPathComponent()
        }
        if let url = bundle.url(
            forResource: "observing-quality",
            withExtension: "json",
            subdirectory: "calibration"
        ) {
            return url.deletingLastPathComponent().deletingLastPathComponent()
        }
        return nil
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let path = url.path
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw EngineCalibrationError.missingFile(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EngineCalibrationError.missingFile(path)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EngineCalibrationError.decode(path, String(describing: error))
        }
    }
}

private final class EngineCalibrationBundleToken {}
