import Foundation

/// Durable watch-side cache of validated modeled zenith brightness samples.
///
/// Independent of `watchObservingQuality.json`. Populated from phone OQ transport after
/// canonical validation succeeds. Consumed on local weather fallback when Connectivity fails.
///
/// Read paths reject samples that fail ``ModeledZenithBrightnessValidity`` (dataset current,
/// coordinates, saved-location ID). Stale atlas revisions never produce OQ.
public protocol WatchModeledBrightnessCaching: Sendable {
    /// Upsert a structurally valid sample (saved or Current Location).
    func upsert(_ sample: ModeledZenithBrightnessSample)

    /// Product-valid sample for a saved location pin, or `nil`.
    func sample(
        forSavedLocationID id: UUID,
        latitude: Double,
        longitude: Double
    ) -> ModeledZenithBrightnessSample?

    /// Product-valid Current Location sample near the given GPS, or `nil`.
    func sample(
        forCurrentLocationLatitude latitude: Double,
        longitude: Double
    ) -> ModeledZenithBrightnessSample?

    /// Lookup for a selected location + observing coordinates.
    func sample(
        for selectedLocation: SelectedLocation,
        latitude: Double,
        longitude: Double
    ) -> ModeledZenithBrightnessSample?
}

extension WatchModeledBrightnessCaching {
    public func sample(
        for selectedLocation: SelectedLocation,
        latitude: Double,
        longitude: Double
    ) -> ModeledZenithBrightnessSample? {
        switch selectedLocation.source {
        case .saved:
            guard let id = selectedLocation.id else { return nil }
            return sample(
                forSavedLocationID: id,
                latitude: latitude,
                longitude: longitude
            )
        case .currentGPS:
            return sample(
                forCurrentLocationLatitude: latitude,
                longitude: longitude
            )
        }
    }
}

/// App Group-backed production cache for watch modeled brightness.
public final class AppGroupWatchModeledBrightnessCache: WatchModeledBrightnessCaching, @unchecked Sendable {
    /// Shared production instance so locations-list priming and conditions local-refresh
    /// see the same in-memory + disk state.
    public static let shared = AppGroupWatchModeledBrightnessCache()

    private let lock = NSLock()
    private var store: WatchModeledBrightnessStore
    private var memory: WatchModeledBrightnessDocument

    public init(baseURL: URL? = AppGroupStorage.containerURL) {
        self.store = WatchModeledBrightnessStore(baseURL: baseURL)
        switch store.load() {
        case let .ready(document):
            self.memory = document
        case .missing, .malformed, .unsupportedSchema:
            self.memory = .empty()
        }
    }

    /// Test injection: start from an in-memory document without disk.
    public init(document: WatchModeledBrightnessDocument, baseURL: URL? = nil) {
        self.store = WatchModeledBrightnessStore(baseURL: baseURL)
        self.memory = WatchModeledBrightnessStore.scrub(document)
    }

    public func upsert(_ sample: ModeledZenithBrightnessSample) {
        lock.lock()
        defer { lock.unlock() }

        // Structural gate only — product validity is enforced on read.
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: sample.latitude,
            longitude: sample.longitude
        ),
        ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(
            sample.modeledZenithSkyBrightness
        ) else {
            return
        }

        if let id = sample.savedLocationID {
            memory.samplesBySavedLocationID[id.uuidString] = sample
        } else {
            memory.currentLocationSample = sample
        }
        _ = store.write(memory)
    }

    public func sample(
        forSavedLocationID id: UUID,
        latitude: Double,
        longitude: Double
    ) -> ModeledZenithBrightnessSample? {
        lock.lock()
        let candidate = memory.samplesBySavedLocationID[id.uuidString]
        lock.unlock()

        guard let sample = candidate else { return nil }
        guard ModeledZenithBrightnessValidity.isValid(
            sample: sample,
            forSavedLocationID: id,
            locationLatitude: latitude,
            locationLongitude: longitude,
            maxAge: nil
        ) else {
            return nil
        }
        return sample
    }

    public func sample(
        forCurrentLocationLatitude latitude: Double,
        longitude: Double
    ) -> ModeledZenithBrightnessSample? {
        lock.lock()
        let candidate = memory.currentLocationSample
        lock.unlock()

        guard let sample = candidate, sample.savedLocationID == nil else { return nil }
        guard ModeledZenithBrightnessValidity.isValid(
            sample: sample,
            forRequestAtLatitude: latitude,
            longitude: longitude,
            maxAge: nil
        ) else {
            return nil
        }
        return sample
    }

    /// Test helper: reload document from disk into memory.
    public func reloadFromDiskForTesting() {
        lock.lock()
        defer { lock.unlock() }
        switch store.load() {
        case let .ready(document):
            memory = document
        case .missing, .malformed, .unsupportedSchema:
            memory = .empty()
        }
    }

    /// Test helper: snapshot of in-memory document (includes structurally valid stale datasets).
    public func documentSnapshotForTesting() -> WatchModeledBrightnessDocument {
        lock.lock()
        defer { lock.unlock() }
        return memory
    }
}
