import Foundation

/// On-disk envelope for Current Location modeled zenith brightness companion metadata.
///
/// Storage schema only (`schemaVersion`). Not the public widget contract — consumers use
/// `CurrentLocationModeledBrightnessReading` or the coordinator.
struct CurrentLocationModeledBrightnessDocument: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// At most one sample; must have `savedLocationID == nil` when present.
    var sample: ModeledZenithBrightnessSample?

    static func empty() -> CurrentLocationModeledBrightnessDocument {
        CurrentLocationModeledBrightnessDocument(
            schemaVersion: currentSchemaVersion,
            sample: nil
        )
    }
}
