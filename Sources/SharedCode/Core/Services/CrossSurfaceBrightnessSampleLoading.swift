import Foundation

/// Explicit brightness input for publication factories (avoids nil-overload ambiguity).
public enum CrossSurfaceBrightnessInput: Sendable {
    /// Load Phase 2/3 companion sample from App Group for the given context.
    case loadFromAppGroup
    /// Use a specific sample (or explicit nil = unavailable without App Group I/O).
    case sample(ModeledZenithBrightnessSample?)
}

/// Read-only App Group sample loading by explicit location context.
public enum CrossSurfaceBrightnessSampleLoading: Sendable {
    /// Returns a Phase-1-valid sample for the context, or nil.
    public static func loadSample(
        for context: CrossSurfaceLocationContext,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> ModeledZenithBrightnessSample? {
        guard context.isValidForBrightnessAssociation else { return nil }

        switch context.source {
        case .saved:
            guard let id = context.savedLocationID else { return nil }
            return SavedLocationModeledBrightnessReading.loadValidSample(
                for: SavedLocationBrightnessAnchor(
                    id: id,
                    latitude: context.latitude,
                    longitude: context.longitude
                ),
                baseURL: baseURL
            )
        case .currentGPS:
            // App/widget placeholder boundary — not a Phase 1 geo change.
            guard !context.isUnresolvedCurrentLocationPlaceholder else { return nil }
            return CurrentLocationModeledBrightnessReading.loadValidSample(
                for: CurrentLocationBrightnessAnchor(
                    latitude: context.latitude,
                    longitude: context.longitude
                ),
                baseURL: baseURL
            )
        }
    }

    /// Resolves brightness input without ambiguous nil semantics.
    public static func resolve(
        _ input: CrossSurfaceBrightnessInput,
        for context: CrossSurfaceLocationContext,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> ModeledZenithBrightnessSample? {
        switch input {
        case .loadFromAppGroup:
            return loadSample(for: context, baseURL: baseURL)
        case .sample(let sample):
            return sample
        }
    }
}
