import Foundation

/// Additive WatchConnectivity locations-reply field for priming Watch LP cache.
///
/// Transports compact ``ModeledZenithBrightnessSample`` values only — not weather, OQ scores,
/// or the LP atlas. Backward-compatible: absence of the field preserves pre-priming behavior.
public enum WatchLocationsBrightnessPriming: Sendable {
    /// Application-context / message-reply payload key.
    public static let replyPayloadKey = "modeledBrightnessSamples"

    // MARK: - Phone: collect samples already known on iOS

    /// Product-valid saved-location samples from the durable iOS companion store.
    ///
    /// Omits pins with no usable current sample. Does not resample the atlas.
    public static func validSamples(
        for locations: [CachedLocation],
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> [ModeledZenithBrightnessSample] {
        var out: [ModeledZenithBrightnessSample] = []
        out.reserveCapacity(locations.count)
        for location in locations {
            guard let anchor = SavedLocationBrightnessAnchor(cachedLocation: location) else {
                continue
            }
            if let sample = SavedLocationModeledBrightnessReading.loadValidSample(
                for: anchor,
                baseURL: baseURL
            ) {
                out.append(sample)
            }
        }
        return out
    }

    public static func encodeSamples(
        _ samples: [ModeledZenithBrightnessSample]
    ) -> Data? {
        guard !samples.isEmpty else { return nil }
        return try? JSONEncoder().encode(samples)
    }

    // MARK: - Watch: decode + re-validate before cache write

    /// Decodes optional additive field; missing/malformed → empty (old phones).
    public static func decodeSamples(from payload: [String: Any]) -> [ModeledZenithBrightnessSample] {
        guard let data = payload[replyPayloadKey] as? Data else { return [] }
        return (try? JSONDecoder().decode([ModeledZenithBrightnessSample].self, from: data)) ?? []
    }

    /// Upserts only samples that are product-valid for a pin in `locations`.
    ///
    /// - Rejects: `savedLocationID == nil` (Current Location), wrong ID, moved coords,
    ///   stale dataset, structural invalidity.
    /// - Does **not** clear cache entries omitted from `samples`.
    /// - One bad sample does not block others.
    public static func applyToCache(
        samples: [ModeledZenithBrightnessSample],
        locations: [CachedLocation],
        cache: any WatchModeledBrightnessCaching
    ) {
        guard !samples.isEmpty else { return }

        var pinsByID: [UUID: CachedLocation] = [:]
        for location in locations {
            guard let id = location.id else { continue }
            pinsByID[id] = location
        }

        for sample in samples {
            // Saved-location bulk priming only — never treat CL samples as pin priming.
            guard let id = sample.savedLocationID,
                  let pin = pinsByID[id] else {
                continue
            }
            guard ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forSavedLocationID: id,
                locationLatitude: pin.latitude,
                locationLongitude: pin.longitude,
                maxAge: nil
            ) else {
                continue
            }
            cache.upsert(sample)
        }
    }
}
