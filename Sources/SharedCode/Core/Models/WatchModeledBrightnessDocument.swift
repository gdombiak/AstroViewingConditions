import Foundation

/// On-disk envelope for watch-side durable modeled zenith brightness samples.
///
/// Independent of `watchObservingQuality.json` (which is conditions/night-associated and
/// may be cleared for night-only outcomes). Brightness validity is primarily location +
/// ``LightPollutionDatasetIdentity``, not a single night's OQ document.
public struct WatchModeledBrightnessDocument: Codable, Sendable, Equatable {
    /// Companion file layout version. Bump only when the envelope shape changes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Key = saved location `UUID.uuidString`.
    public var samplesBySavedLocationID: [String: ModeledZenithBrightnessSample]
    /// Last validated Current Location sample (must have `savedLocationID == nil`).
    public var currentLocationSample: ModeledZenithBrightnessSample?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        samplesBySavedLocationID: [String: ModeledZenithBrightnessSample] = [:],
        currentLocationSample: ModeledZenithBrightnessSample? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.samplesBySavedLocationID = samplesBySavedLocationID
        self.currentLocationSample = currentLocationSample
    }

    public static func empty() -> WatchModeledBrightnessDocument {
        WatchModeledBrightnessDocument()
    }
}
