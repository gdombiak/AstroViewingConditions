import Foundation

/// On-disk envelope for saved-location modeled zenith brightness companion metadata.
///
/// This is a **storage** schema (`schemaVersion`), distinct from
/// `LightPollutionDatasetIdentity` on each sample. Not the public widget contract —
/// consumers obtain validated samples via `SavedLocationModeledBrightnessReading`
/// or the coordinator.
struct SavedLocationModeledBrightnessDocument: Codable, Sendable, Equatable {
    /// Companion file layout version. Bump only when the envelope shape changes.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// Key = `SavedLocation.id.uuidString`. Value = Phase 1 sample.
    var samplesBySavedLocationID: [String: ModeledZenithBrightnessSample]

    static func empty() -> SavedLocationModeledBrightnessDocument {
        SavedLocationModeledBrightnessDocument(
            schemaVersion: currentSchemaVersion,
            samplesBySavedLocationID: [:]
        )
    }
}
