import Foundation

/// Optional versioned OQ block transported beside `ViewingConditions` over WatchConnectivity.
///
/// - **v1 (Phase 4B):** saved-location OQ; `requestContext` is nil.
/// - **v2 (Phase 4C):** Current Location OQ may include correlated `requestContext`.
///
/// Watch validates, recomputes with `CrossSurfaceObservingQualityResolver`, and persists
/// only the recomputed snapshot. Transported scores are diagnostic only.
public struct WatchObservingQualityPayload: Codable, Sendable, Equatable {
    /// Highest version this binary can author (includes Current Location context).
    public static let currentPayloadVersion = 2
    /// Phase 4B saved-location payloads.
    public static let savedLocationPayloadVersion = 1
    /// Phase 4C Current Location payloads with request correlation.
    public static let currentLocationPayloadVersion = 2

    public var payloadVersion: Int
    public var location: CrossSurfaceLocationContext
    public var transportedSnapshot: CrossSurfaceObservingQualitySnapshot
    /// Echoed watch request context for Current Location (v2). Nil for saved-location v1.
    public var requestContext: WatchCurrentLocationRequestContext?

    public init(
        payloadVersion: Int = currentPayloadVersion,
        location: CrossSurfaceLocationContext,
        transportedSnapshot: CrossSurfaceObservingQualitySnapshot,
        requestContext: WatchCurrentLocationRequestContext? = nil
    ) {
        self.payloadVersion = payloadVersion
        self.location = location
        self.transportedSnapshot = transportedSnapshot
        self.requestContext = requestContext
    }

    /// Reconstruct a sample from transported metadata when availability is `.available`.
    public func makeSample() -> ModeledZenithBrightnessSample? {
        guard transportedSnapshot.brightnessAvailability == .available,
              let brightness = transportedSnapshot.modeledZenithBrightness,
              let dataset = transportedSnapshot.brightnessDataset,
              let lat = transportedSnapshot.brightnessLookupLatitude,
              let lon = transportedSnapshot.brightnessLookupLongitude
        else {
            return nil
        }
        return ModeledZenithBrightnessSample(
            latitude: lat,
            longitude: lon,
            modeledZenithSkyBrightness: brightness,
            dataset: dataset,
            sampledAt: transportedSnapshot.assessedAt,
            savedLocationID: transportedSnapshot.brightnessSavedLocationID
        )
    }
}

/// Persisted watch-side OQ document (recomputed only).
public struct WatchObservingQualityDocument: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var snapshot: CrossSurfaceObservingQualitySnapshot
    public var location: CrossSurfaceLocationContext
    /// Night score of the conditions this snapshot is associated with.
    public var associatedNightConditionsScore: Int
    /// Conditions location id when saved; nil for pure coordinate association.
    public var associatedConditionsLocationID: UUID?
    public var associatedLatitude: Double
    public var associatedLongitude: Double

    public init(
        schemaVersion: Int = currentSchemaVersion,
        snapshot: CrossSurfaceObservingQualitySnapshot,
        location: CrossSurfaceLocationContext,
        associatedNightConditionsScore: Int,
        associatedConditionsLocationID: UUID?,
        associatedLatitude: Double,
        associatedLongitude: Double
    ) {
        self.schemaVersion = schemaVersion
        self.snapshot = snapshot
        self.location = location
        self.associatedNightConditionsScore = associatedNightConditionsScore
        self.associatedConditionsLocationID = associatedConditionsLocationID
        self.associatedLatitude = associatedLatitude
        self.associatedLongitude = associatedLongitude
    }
}

/// Display-state fingerprint for complication reload coalescing (no timestamps).
public struct ObservingQualityDisplayFingerprint: Codable, Sendable, Hashable, Equatable {
    public static let coordinateBucketScale: Double = 100_000 // 1e-5°

    public var source: SelectedLocation.Source
    public var savedLocationID: UUID?
    public var latitudeBucket: Int
    public var longitudeBucket: Int
    public var nightConditionsScore: Int
    public var observingQualityScore: Int
    public var brightnessAvailability: BrightnessAvailability
    public var datasetID: String?
    public var datasetRevision: Int?
    public var formatVersion: Int?

    public init(
        source: SelectedLocation.Source,
        savedLocationID: UUID?,
        latitude: Double,
        longitude: Double,
        nightConditionsScore: Int,
        observingQualityScore: Int,
        brightnessAvailability: BrightnessAvailability,
        dataset: LightPollutionDatasetIdentity?
    ) {
        self.source = source
        self.savedLocationID = savedLocationID
        self.latitudeBucket = Self.bucket(latitude)
        self.longitudeBucket = Self.bucket(longitude)
        self.nightConditionsScore = nightConditionsScore
        self.observingQualityScore = observingQualityScore
        self.brightnessAvailability = brightnessAvailability
        self.datasetID = dataset?.datasetID
        self.datasetRevision = dataset?.datasetRevision
        self.formatVersion = dataset?.formatVersion
    }

    public init(snapshot: CrossSurfaceObservingQualitySnapshot, location: CrossSurfaceLocationContext) {
        self.init(
            source: location.source,
            savedLocationID: location.savedLocationID,
            latitude: location.latitude,
            longitude: location.longitude,
            nightConditionsScore: snapshot.nightConditionsScore,
            observingQualityScore: snapshot.observingQualityScore,
            brightnessAvailability: snapshot.brightnessAvailability,
            dataset: snapshot.brightnessDataset
        )
    }

    public static func bucket(_ degrees: Double) -> Int {
        Int((degrees * coordinateBucketScale).rounded())
    }
}

/// Resolved headline for watch dashboard / complications.
public struct WatchObservingQualityHeadline: Sendable, Equatable {
    public var nightConditionsScore: Int
    public var observingQualityScore: Int
    public var brightnessAvailability: BrightnessAvailability
    public var verdict: String
    public var fingerprint: ObservingQualityDisplayFingerprint

    public init(
        nightConditionsScore: Int,
        observingQualityScore: Int,
        brightnessAvailability: BrightnessAvailability,
        location: CrossSurfaceLocationContext,
        dataset: LightPollutionDatasetIdentity?
    ) {
        self.nightConditionsScore = nightConditionsScore
        self.observingQualityScore = observingQualityScore
        self.brightnessAvailability = brightnessAvailability
        self.verdict = CrossSurfaceHeadlineScorePresentation.verdict(for: observingQualityScore)
        self.fingerprint = ObservingQualityDisplayFingerprint(
            source: location.source,
            savedLocationID: location.savedLocationID,
            latitude: location.latitude,
            longitude: location.longitude,
            nightConditionsScore: nightConditionsScore,
            observingQualityScore: observingQualityScore,
            brightnessAvailability: brightnessAvailability,
            dataset: dataset
        )
    }

    public static func nightOnly(
        nightScore: Int,
        location: CrossSurfaceLocationContext
    ) -> WatchObservingQualityHeadline {
        WatchObservingQualityHeadline(
            nightConditionsScore: nightScore,
            observingQualityScore: nightScore,
            brightnessAvailability: .unavailable,
            location: location,
            dataset: nil
        )
    }
}
