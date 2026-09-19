import Foundation
import os
import AstroEngine

/// Package-internal disk I/O for the watch modeled-brightness companion file.
///
/// Structural scrub only; product validity (dataset current, pin distance) lives on
/// ``WatchModeledBrightnessCache`` read paths.
struct WatchModeledBrightnessStore: Sendable {
    static let fileName = "watchModeledBrightness.json"

    var baseURL: URL?

    private static let logger = Logger(
        subsystem: "com.astroviewing.conditions",
        category: "WatchModeledBrightness"
    )

    enum LoadOutcome: Sendable, Equatable {
        case ready(WatchModeledBrightnessDocument)
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
            Self.logger.error("Watch brightness store base URL unavailable")
            return .missing
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            Self.logger.warning("Failed to read watch brightness file: \(error.localizedDescription)")
            return .malformed
        }

        if let version = Self.peekSchemaVersion(data),
           version > WatchModeledBrightnessDocument.currentSchemaVersion {
            return .unsupportedSchema(foundVersion: version)
        }

        let decoded: WatchModeledBrightnessDocument
        do {
            decoded = try JSONDecoder().decode(WatchModeledBrightnessDocument.self, from: data)
        } catch {
            Self.logger.warning("Failed to decode watch brightness file: \(error.localizedDescription)")
            return .malformed
        }

        if decoded.schemaVersion > WatchModeledBrightnessDocument.currentSchemaVersion {
            return .unsupportedSchema(foundVersion: decoded.schemaVersion)
        }
        if decoded.schemaVersion != WatchModeledBrightnessDocument.currentSchemaVersion {
            return .malformed
        }

        return .ready(Self.scrub(decoded))
    }

    @discardableResult
    func write(_ document: WatchModeledBrightnessDocument) -> Bool {
        guard let fileURL else {
            Self.logger.error("Watch brightness store base URL unavailable; cannot write")
            return false
        }
        var toWrite = document
        toWrite.schemaVersion = WatchModeledBrightnessDocument.currentSchemaVersion
        toWrite = Self.scrub(toWrite)

        do {
            let data = try JSONEncoder().encode(toWrite)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            Self.logger.error("Failed to write watch brightness file: \(error.localizedDescription)")
            return false
        }
    }

    static func scrub(_ document: WatchModeledBrightnessDocument) -> WatchModeledBrightnessDocument {
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

        var current = document.currentLocationSample
        if let sample = current {
            let ok = sample.savedLocationID == nil
                && ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
                    latitude: sample.latitude,
                    longitude: sample.longitude
                )
                && ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(
                    sample.modeledZenithSkyBrightness
                )
            if !ok { current = nil }
        }

        return WatchModeledBrightnessDocument(
            schemaVersion: WatchModeledBrightnessDocument.currentSchemaVersion,
            samplesBySavedLocationID: samples,
            currentLocationSample: current
        )
    }

    private static func peekSchemaVersion(_ data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = obj["schemaVersion"] as? Int else {
            return nil
        }
        return version
    }
}
