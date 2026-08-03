import Foundation
import os

/// Package-internal disk I/O for the saved-location modeled-brightness companion file.
///
/// **Writes are internal** — only `SavedLocationModeledBrightnessCoordinator` (and
/// `@testable` unit tests) may call `write`. Structural validation only; product
/// validity (dataset current, pin distance) lives in the coordinator / Phase 1 APIs.
struct SavedLocationModeledBrightnessStore: Sendable {
    static let fileName = "savedLocationModeledBrightness.json"

    /// Defaults to the App Group container; tests inject a temporary directory.
    var baseURL: URL?

    private static let logger = Logger(
        subsystem: "com.astroviewing.conditions",
        category: "SavedLocationModeledBrightness"
    )

    enum LoadOutcome: Sendable, Equatable {
        /// Supported schema; entries scrubbed for structural legality.
        case ready(SavedLocationModeledBrightnessDocument)
        case missing
        case malformed
        case unsupportedSchema(foundVersion: Int)
    }

    init(baseURL: URL? = AppGroupStorage.containerURL) {
        self.baseURL = baseURL
    }

    private var fileURL: URL? {
        baseURL?.appendingPathComponent(Self.fileName)
    }

    func load() -> LoadOutcome {
        guard let fileURL else {
            Self.logger.error("Companion store base URL unavailable")
            return .missing
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.warning("Failed to read companion file: \(error.localizedDescription)")
            return .malformed
        }

        // Probe schemaVersion without requiring a full successful decode of samples.
        if let version = Self.peekSchemaVersion(data),
           version > SavedLocationModeledBrightnessDocument.currentSchemaVersion {
            return .unsupportedSchema(foundVersion: version)
        }

        let decoded: SavedLocationModeledBrightnessDocument
        do {
            decoded = try JSONDecoder().decode(SavedLocationModeledBrightnessDocument.self, from: data)
        } catch {
            Self.logger.warning("Failed to decode companion file: \(error.localizedDescription)")
            return .malformed
        }

        if decoded.schemaVersion > SavedLocationModeledBrightnessDocument.currentSchemaVersion {
            return .unsupportedSchema(foundVersion: decoded.schemaVersion)
        }
        if decoded.schemaVersion != SavedLocationModeledBrightnessDocument.currentSchemaVersion {
            // Only v1 is defined; anything else on a lower version is unreadable.
            return .malformed
        }

        return .ready(Self.scrub(decoded))
    }

    /// Atomic full-document write. Package-internal sole write path for production
    /// (coordinator). Not part of the public SharedCode surface for widgets/features.
    @discardableResult
    func write(_ document: SavedLocationModeledBrightnessDocument) -> Bool {
        guard let fileURL else {
            Self.logger.error("Companion store base URL unavailable; cannot write")
            return false
        }
        var toWrite = document
        toWrite.schemaVersion = SavedLocationModeledBrightnessDocument.currentSchemaVersion
        toWrite = Self.scrub(toWrite)

        do {
            let data = try JSONEncoder().encode(toWrite)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            Self.logger.error("Failed to write companion file: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Structural scrub

    /// Drops illegal entries; does not apply pin-distance or dataset-current product rules.
    static func scrub(
        _ document: SavedLocationModeledBrightnessDocument
    ) -> SavedLocationModeledBrightnessDocument {
        var samples: [String: ModeledZenithBrightnessSample] = [:]
        for (key, sample) in document.samplesBySavedLocationID {
            guard let uuid = UUID(uuidString: key) else { continue }
            guard sample.savedLocationID == uuid else { continue }
            guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
                latitude: sample.latitude,
                longitude: sample.longitude
            ) else { continue }
            guard ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(
                sample.modeledZenithSkyBrightness
            ) else { continue }
            samples[key] = sample
        }
        return SavedLocationModeledBrightnessDocument(
            schemaVersion: SavedLocationModeledBrightnessDocument.currentSchemaVersion,
            samplesBySavedLocationID: samples
        )
    }

    private static func peekSchemaVersion(_ data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let intValue = json["schemaVersion"] as? Int {
            return intValue
        }
        if let number = json["schemaVersion"] as? NSNumber {
            return number.intValue
        }
        return nil
    }
}
