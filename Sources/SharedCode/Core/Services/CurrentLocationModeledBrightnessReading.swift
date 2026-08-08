import Foundation

/// Public **read-only** facade for Current Location modeled brightness companion data.
///
/// For widgets/extensions (separate process). Never writes.
public enum CurrentLocationModeledBrightnessReading: Sendable {
    /// Loads the latest atomic file and applies Phase 1 coordinate validity (`maxAge: nil`).
    /// Requires `savedLocationID == nil`. Missing/malformed/unsupported/invalid → `nil`.
    public static func loadValidSample(
        for anchor: CurrentLocationBrightnessAnchor,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> ModeledZenithBrightnessSample? {
        let store = CurrentLocationModeledBrightnessStore(baseURL: baseURL)
        switch store.load() {
        case .missing, .malformed, .unsupportedSchema:
            return nil
        case .ready(let document):
            guard let sample = document.sample else { return nil }
            guard sample.savedLocationID == nil else { return nil }
            guard ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: anchor.latitude,
                longitude: anchor.longitude,
                maxAge: nil
            ) else {
                return nil
            }
            return sample
        }
    }
}
