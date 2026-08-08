import Foundation

/// Public **read-only** facade for saved-location modeled brightness companion data.
///
/// Intended for widgets/extensions (separate process). Loads the latest complete
/// atomic file from disk and applies Phase 1 validity. Never writes.
public enum SavedLocationModeledBrightnessReading: Sendable {
    /// Returns a sample only when present and valid for the anchor under Phase 1 rules
    /// (`maxAge: nil`). Missing, malformed, unsupported schema, or invalid → `nil`.
    /// Never invents pristine darkness.
    public static func loadValidSample(
        for anchor: SavedLocationBrightnessAnchor,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> ModeledZenithBrightnessSample? {
        let store = SavedLocationModeledBrightnessStore(baseURL: baseURL)
        switch store.load() {
        case .missing, .malformed, .unsupportedSchema:
            return nil
        case .ready(let document):
            guard let sample = document.samplesBySavedLocationID[anchor.id.uuidString] else {
                return nil
            }
            guard ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forSavedLocationID: anchor.id,
                locationLatitude: anchor.latitude,
                locationLongitude: anchor.longitude,
                maxAge: nil
            ) else {
                return nil
            }
            return sample
        }
    }
}
