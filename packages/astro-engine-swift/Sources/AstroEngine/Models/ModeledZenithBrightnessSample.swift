import Foundation

/// Portable, versioned modeled zenith sky brightness sample (mag/arcsec²).
///
/// Prefer sharing this environmental input across surfaces and applying
/// `ObservingQualityCalculator` rather than forking penalty math.
///
/// - Larger mag/arcsec² ⇒ darker sky (not a Bortle class).
/// - `nil` from a provider must never be stored as pristine darkness.
public struct ModeledZenithBrightnessSample: Codable, Sendable, Equatable, Hashable {
    /// Coordinates used for the atlas lookup (not necessarily a saved pin after edit).
    public let latitude: Double
    public let longitude: Double
    /// Modeled zenith sky brightness in mag/arcsec².
    public let modeledZenithSkyBrightness: Double
    /// Logical dataset identity for stale-cache detection.
    public let dataset: LightPollutionDatasetIdentity
    /// When this sample was produced.
    public let sampledAt: Date
    /// Stable saved-location association when applicable; `nil` for pure coordinate samples
    /// (e.g. Current Location / watch-requested coordinates).
    public let savedLocationID: UUID?

    public init(
        latitude: Double,
        longitude: Double,
        modeledZenithSkyBrightness: Double,
        dataset: LightPollutionDatasetIdentity = .current,
        sampledAt: Date = Date(),
        savedLocationID: UUID? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.modeledZenithSkyBrightness = modeledZenithSkyBrightness
        self.dataset = dataset
        self.sampledAt = sampledAt
        self.savedLocationID = savedLocationID
    }
}
