import Foundation

/// Shared validity rules for modeled zenith brightness samples.
///
/// **All** consumers (saved-location metadata, Current Location, widgets, watch)
/// must use these rules so tolerances and dataset checks cannot diverge later.
public enum ModeledZenithBrightnessValidity: Sendable {
    /// Maximum great-circle distance between sample lookup coordinates and a request
    /// for the sample to be considered geographically applicable.
    ///
    /// Rationale:
    /// - LPATLAS1 finest hierarchical leaves are ~0.025° (~2.8 km at the equator).
    /// - Native atlas cells are 1/120° (~0.93 km).
    /// - Urban gradients can change by >0.1 mag over short distances; re-sample when the
    ///   request moves more than about one native cell scale.
    /// - **1000 m** is slightly larger than one native cell, well under a finest leaf,
    ///   and larger than typical GPS jitter without treating a moved pin as the same sample.
    ///
    /// Prefer this geographic-distance check over decimal rounding of lat/lon.
    public static let maxCoordinateDistanceMeters: Double = 1_000

    /// Inclusive lower bound for a plausible atlas mag/arcsec² value (slightly below
    /// production quant min 13.01 to allow tiny float noise).
    public static let minimumPlausibleBrightness: Double = 13.0

    /// Inclusive upper bound for a plausible atlas mag/arcsec² value (production quant max).
    public static let maximumPlausibleBrightness: Double = 22.5

    /// Maximum amount a sample's `sampledAt` may lie in the future relative to `now`
    /// when `maxAge` is supplied (clock skew allowance).
    public static let maxSampledAtClockSkewSeconds: TimeInterval = 1

    // MARK: - Geographic coordinates

    /// True when latitude is finite and in **[-90, 90]** and longitude is finite and
    /// in **[-180, 180]** (inclusive bounds).
    public static func isValidGeographicCoordinate(
        latitude: Double,
        longitude: Double
    ) -> Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        return latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
    }

    /// True when a distance tolerance may be used by public validity APIs:
    /// finite and **nonnegative**.
    public static func isValidMaxDistanceMeters(_ maxDistanceMeters: Double) -> Bool {
        maxDistanceMeters.isFinite && maxDistanceMeters >= 0
    }

    // MARK: - Dataset / brightness

    public static func isDatasetCurrent(
        _ dataset: LightPollutionDatasetIdentity,
        current: LightPollutionDatasetIdentity = .current
    ) -> Bool {
        current.isCompatible(with: dataset)
    }

    public static func isBrightnessInPlausibleRange(_ brightness: Double) -> Bool {
        guard brightness.isFinite else { return false }
        return brightness >= minimumPlausibleBrightness
            && brightness <= maximumPlausibleBrightness
    }

    // MARK: - Distance

    /// Great-circle distance in meters (WGS-84 spherical approximation).
    ///
    /// This is a **mathematical primitive**: it does not validate geographic domains.
    /// Public validity paths (`coordinatesMatch`, `isValid`) must reject invalid
    /// coordinates and invalid distance tolerances before treating a distance as
    /// decisive. Callers that need domain safety should use `coordinatesMatch` or
    /// `isValidGeographicCoordinate` first.
    public static func distanceMeters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let r = 6_371_000.0 // mean Earth radius (m)
        let φ1 = latitude1 * .pi / 180
        let φ2 = latitude2 * .pi / 180
        let Δφ = (latitude2 - latitude1) * .pi / 180
        let Δλ = (longitude2 - longitude1) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2)
            + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return r * c
    }

    public static func coordinatesMatch(
        sampleLatitude: Double,
        sampleLongitude: Double,
        requestLatitude: Double,
        requestLongitude: Double,
        maxDistanceMeters: Double = maxCoordinateDistanceMeters
    ) -> Bool {
        guard isValidMaxDistanceMeters(maxDistanceMeters) else {
            return false
        }
        guard isValidGeographicCoordinate(latitude: sampleLatitude, longitude: sampleLongitude),
              isValidGeographicCoordinate(latitude: requestLatitude, longitude: requestLongitude)
        else {
            return false
        }
        let d = distanceMeters(
            latitude1: sampleLatitude,
            longitude1: sampleLongitude,
            latitude2: requestLatitude,
            longitude2: requestLongitude
        )
        return d <= maxDistanceMeters
    }

    // MARK: - Saved-location association

    /// Exact association between a sample and a request's optional saved-location ID.
    ///
    /// | Requested | Cached | Match |
    /// |-----------|--------|-------|
    /// | A         | A      | yes   |
    /// | A         | nil/B  | no    |
    /// | nil       | nil    | yes   |
    /// | nil       | A      | no    |
    public static func savedLocationAssociationMatches(
        sample: ModeledZenithBrightnessSample,
        requestedSavedLocationID: UUID?
    ) -> Bool {
        sample.savedLocationID == requestedSavedLocationID
    }

    // MARK: - Full sample validity

    /// Full sample validity for a **coordinate-only** request against the current dataset.
    ///
    /// Does **not** enforce saved-location association. For saved pins use
    /// `isValid(sample:forSavedLocationID:...)`. For exact association at resolve time
    /// use `ModeledZenithBrightnessResolver` (or `savedLocationAssociationMatches`).
    ///
    /// Does **not** treat missing data as pristine. Invalid samples must be ignored
    /// and re-sampled when a provider is available.
    ///
    /// ### `maxAge` contract
    /// - `nil`: age is not checked.
    /// - non-`nil`: must be **finite and ≥ 0**; otherwise the sample is invalid.
    /// - When age is checked, `sampledAt` may be at most
    ///   `maxSampledAtClockSkewSeconds` (1 s) ahead of `now` (clock skew).
    /// - A sample older than `maxAge` relative to `now` is invalid.
    /// - A sample with `sampledAt` more than 1 s in the future is invalid.
    public static func isValid(
        sample: ModeledZenithBrightnessSample,
        forRequestAtLatitude requestLatitude: Double,
        longitude requestLongitude: Double,
        currentDataset: LightPollutionDatasetIdentity = .current,
        maxDistanceMeters: Double = maxCoordinateDistanceMeters,
        maxAge: TimeInterval? = nil,
        now: Date = Date()
    ) -> Bool {
        guard isDatasetCurrent(sample.dataset, current: currentDataset) else {
            return false
        }
        guard isBrightnessInPlausibleRange(sample.modeledZenithSkyBrightness) else {
            return false
        }
        guard coordinatesMatch(
            sampleLatitude: sample.latitude,
            sampleLongitude: sample.longitude,
            requestLatitude: requestLatitude,
            requestLongitude: requestLongitude,
            maxDistanceMeters: maxDistanceMeters
        ) else {
            return false
        }
        return isSampleAgeValid(sampledAt: sample.sampledAt, maxAge: maxAge, now: now)
    }

    /// Validity when association is by saved-location ID (coordinates still checked
    /// so a pin move invalidates the sample). Requires **exact** ID match
    /// (`sample.savedLocationID == savedLocationID`).
    public static func isValid(
        sample: ModeledZenithBrightnessSample,
        forSavedLocationID savedLocationID: UUID,
        locationLatitude: Double,
        locationLongitude: Double,
        currentDataset: LightPollutionDatasetIdentity = .current,
        maxDistanceMeters: Double = maxCoordinateDistanceMeters,
        maxAge: TimeInterval? = nil,
        now: Date = Date()
    ) -> Bool {
        guard sample.savedLocationID == savedLocationID else {
            return false
        }
        return isValid(
            sample: sample,
            forRequestAtLatitude: locationLatitude,
            longitude: locationLongitude,
            currentDataset: currentDataset,
            maxDistanceMeters: maxDistanceMeters,
            maxAge: maxAge,
            now: now
        )
    }

    // MARK: - Age

    /// Applies the `maxAge` contract (see `isValid` documentation).
    public static func isSampleAgeValid(
        sampledAt: Date,
        maxAge: TimeInterval?,
        now: Date = Date()
    ) -> Bool {
        guard let maxAge else { return true }
        guard maxAge.isFinite, maxAge >= 0 else { return false }
        guard sampledAt <= now.addingTimeInterval(maxSampledAtClockSkewSeconds) else {
            return false
        }
        return now.timeIntervalSince(sampledAt) <= maxAge
    }
}
