import Foundation
import os

/// Package-internal disk I/O for the Current Location modeled-brightness companion file.
///
/// **Writes are internal** — only `CurrentLocationModeledBrightnessCoordinator` (and
/// `@testable` unit tests) may call `write`. Structural validation only.
struct CurrentLocationModeledBrightnessStore: Sendable {
    static let fileName = "currentLocationModeledBrightness.json"

    var baseURL: URL?

    private static let logger = Logger(
        subsystem: "com.astroviewing.conditions",
        category: "CurrentLocationModeledBrightness"
    )

    enum LoadOutcome: Sendable, Equatable {
        case ready(CurrentLocationModeledBrightnessDocument)
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

        if let version = Self.peekSchemaVersion(data),
           version > CurrentLocationModeledBrightnessDocument.currentSchemaVersion {
            return .unsupportedSchema(foundVersion: version)
        }

        let decoded: CurrentLocationModeledBrightnessDocument
        do {
            decoded = try JSONDecoder().decode(CurrentLocationModeledBrightnessDocument.self, from: data)
        } catch {
            Self.logger.warning("Failed to decode companion file: \(error.localizedDescription)")
            return .malformed
        }

        if decoded.schemaVersion > CurrentLocationModeledBrightnessDocument.currentSchemaVersion {
            return .unsupportedSchema(foundVersion: decoded.schemaVersion)
        }
        if decoded.schemaVersion != CurrentLocationModeledBrightnessDocument.currentSchemaVersion {
            return .malformed
        }

        return .ready(Self.scrub(decoded))
    }

    @discardableResult
    func write(_ document: CurrentLocationModeledBrightnessDocument) -> Bool {
        guard let fileURL else {
            Self.logger.error("Companion store base URL unavailable; cannot write")
            return false
        }
        var toWrite = document
        toWrite.schemaVersion = CurrentLocationModeledBrightnessDocument.currentSchemaVersion
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

    /// Structural scrub only. Does **not** treat `(0,0)` as invalid (Phase 1 geo allows it).
    static func scrub(
        _ document: CurrentLocationModeledBrightnessDocument
    ) -> CurrentLocationModeledBrightnessDocument {
        guard var sample = document.sample else {
            return CurrentLocationModeledBrightnessDocument(
                schemaVersion: CurrentLocationModeledBrightnessDocument.currentSchemaVersion,
                sample: nil
            )
        }
        // Current Location samples must not carry a saved-location association.
        guard sample.savedLocationID == nil else {
            return .empty()
        }
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: sample.latitude,
            longitude: sample.longitude
        ) else {
            return .empty()
        }
        guard ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(
            sample.modeledZenithSkyBrightness
        ) else {
            return .empty()
        }
        sample = ModeledZenithBrightnessSample(
            latitude: sample.latitude,
            longitude: sample.longitude,
            modeledZenithSkyBrightness: sample.modeledZenithSkyBrightness,
            dataset: sample.dataset,
            sampledAt: sample.sampledAt,
            savedLocationID: nil
        )
        return CurrentLocationModeledBrightnessDocument(
            schemaVersion: CurrentLocationModeledBrightnessDocument.currentSchemaVersion,
            sample: sample
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
