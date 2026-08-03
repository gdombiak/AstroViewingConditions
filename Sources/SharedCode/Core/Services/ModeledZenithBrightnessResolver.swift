import Foundation

/// Thin helpers over `LightPollutionProviding` that attach dataset identity and
/// produce portable `ModeledZenithBrightnessSample` values.
///
/// Does **not** own bundle I/O, bootstrap, or persistence. Callers inject a ready provider.
public enum ModeledZenithBrightnessResolver: Sendable {
    /// Sample the provider at a coordinate and wrap a versioned sample.
    ///
    /// Returns `nil` when:
    /// - request coordinates are outside valid geographic domains;
    /// - the provider returns `nil`;
    /// - the brightness is non-finite or out of the plausible range.
    ///
    /// Never fabricates pristine darkness. Does **not** call the provider for invalid coordinates.
    public static func sample(
        from provider: any LightPollutionProviding,
        latitude: Double,
        longitude: Double,
        dataset: LightPollutionDatasetIdentity = .current,
        savedLocationID: UUID? = nil,
        sampledAt: Date = Date()
    ) -> ModeledZenithBrightnessSample? {
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: latitude,
            longitude: longitude
        ) else {
            return nil
        }
        guard let brightness = provider.modeledZenithSkyBrightness(
            latitude: latitude,
            longitude: longitude
        ) else {
            return nil
        }
        guard ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(brightness) else {
            return nil
        }
        return ModeledZenithBrightnessSample(
            latitude: latitude,
            longitude: longitude,
            modeledZenithSkyBrightness: brightness,
            dataset: dataset,
            sampledAt: sampledAt,
            savedLocationID: savedLocationID
        )
    }

    /// Resolve a usable sample for a request: return `cached` when valid for the request
    /// (including **exact** saved-location association), otherwise sample the provider.
    ///
    /// Association semantics (exact):
    /// - requested saved ID A + cached saved ID A → association valid
    /// - requested saved ID A + cached nil or B → invalid
    /// - coordinate-only (`nil`) + cached `nil` → association valid
    /// - coordinate-only (`nil`) + cached saved ID A → invalid
    ///
    /// Does **not** call the provider for invalid request coordinates.
    public static func resolve(
        requestLatitude: Double,
        requestLongitude: Double,
        cached: ModeledZenithBrightnessSample?,
        provider: (any LightPollutionProviding)?,
        dataset: LightPollutionDatasetIdentity = .current,
        savedLocationID: UUID? = nil,
        maxAge: TimeInterval? = nil,
        now: Date = Date()
    ) -> ModeledZenithBrightnessSample? {
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: requestLatitude,
            longitude: requestLongitude
        ) else {
            return nil
        }

        if let cached, isCacheUsable(
            cached: cached,
            requestLatitude: requestLatitude,
            requestLongitude: requestLongitude,
            dataset: dataset,
            savedLocationID: savedLocationID,
            maxAge: maxAge,
            now: now
        ) {
            return cached
        }

        guard let provider else { return nil }
        return sample(
            from: provider,
            latitude: requestLatitude,
            longitude: requestLongitude,
            dataset: dataset,
            savedLocationID: savedLocationID,
            sampledAt: now
        )
    }

    /// Exact association + coordinate/dataset/age validity for a cached sample.
    private static func isCacheUsable(
        cached: ModeledZenithBrightnessSample,
        requestLatitude: Double,
        requestLongitude: Double,
        dataset: LightPollutionDatasetIdentity,
        savedLocationID: UUID?,
        maxAge: TimeInterval?,
        now: Date
    ) -> Bool {
        guard ModeledZenithBrightnessValidity.savedLocationAssociationMatches(
            sample: cached,
            requestedSavedLocationID: savedLocationID
        ) else {
            return false
        }

        if let savedLocationID {
            return ModeledZenithBrightnessValidity.isValid(
                sample: cached,
                forSavedLocationID: savedLocationID,
                locationLatitude: requestLatitude,
                locationLongitude: requestLongitude,
                currentDataset: dataset,
                maxAge: maxAge,
                now: now
            )
        }

        // Coordinate-only: association already requires cached.savedLocationID == nil.
        return ModeledZenithBrightnessValidity.isValid(
            sample: cached,
            forRequestAtLatitude: requestLatitude,
            longitude: requestLongitude,
            currentDataset: dataset,
            maxAge: maxAge,
            now: now
        )
    }
}
