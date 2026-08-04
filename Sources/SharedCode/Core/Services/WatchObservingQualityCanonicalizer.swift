import Foundation

/// Watch-side validation + canonical recomputation of transported OQ (Phase 4B + 4C).
///
/// Transported scores are diagnostic only; the recomputed snapshot is authoritative.
public enum WatchObservingQualityCanonicalizer: Sendable {
    public enum Outcome: Sendable, Equatable {
        case enhanced(CrossSurfaceObservingQualitySnapshot, CrossSurfaceLocationContext)
        case nightOnly(nightScore: Int, location: CrossSurfaceLocationContext?)
    }

    /// Validates optional transport and returns recomputed enhancement or night-only fallback.
    ///
    /// - Parameter expectedCurrentLocationRequest: Outstanding watch CL request for correlation.
    ///   Required for Current Location enhancement; must be nil for pure saved-location paths.
    public static func resolve(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload?,
        selectedLocation: SelectedLocation?,
        expectedCurrentLocationRequest: WatchCurrentLocationRequestContext? = nil
    ) -> Outcome {
        guard let nightAssessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return .nightOnly(
                nightScore: 0,
                location: selectedLocation.flatMap(CrossSurfaceLocationContext.make(from:))
            )
        }
        let nightScore = nightAssessment.calculatedScore
        let fallbackLocation = selectedLocation.flatMap(CrossSurfaceLocationContext.make(from:))
            ?? transported?.location
            ?? expectedCurrentLocationRequest?.asLocationContext

        guard let transported else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Reject version 0 / future versions before source dispatch.
        guard transported.payloadVersion > 0,
              transported.payloadVersion <= WatchObservingQualityPayload.currentPayloadVersion else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        switch transported.location.source {
        case .saved:
            return resolveSaved(
                conditions: conditions,
                transported: transported,
                selectedLocation: selectedLocation,
                nightScore: nightScore,
                fallbackLocation: fallbackLocation
            )
        case .currentGPS:
            return resolveCurrentLocation(
                conditions: conditions,
                transported: transported,
                selectedLocation: selectedLocation,
                expectedRequest: expectedCurrentLocationRequest,
                nightScore: nightScore,
                fallbackLocation: fallbackLocation
            )
        }
    }

    // MARK: - Saved (Phase 4B)

    private static func resolveSaved(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload,
        selectedLocation: SelectedLocation?,
        nightScore: Int,
        fallbackLocation: CrossSurfaceLocationContext?
    ) -> Outcome {
        // Exact schema: v1 saved-location only. v2 is Current Location transport.
        guard transported.payloadVersion
                == WatchObservingQualityPayload.savedLocationPayloadVersion else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        // CL request context must not appear on saved payloads.
        guard transported.requestContext == nil else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        let location = transported.location
        guard location.source == .saved,
              location.savedLocationID != nil,
              location.hasConsistentIdentity,
              location.hasValidGeographicCoordinates else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        guard WatchObservingQualitySavedLocationAssociation.matches(
            context: location,
            conditionsLocation: conditions.location
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        if let selectedLocation {
            guard WatchObservingQualitySavedLocationAssociation.matches(
                selected: selectedLocation,
                context: location
            ) else {
                return .nightOnly(nightScore: nightScore, location: fallbackLocation)
            }
        }

        return recomputeAndAgree(
            conditions: conditions,
            transported: transported,
            location: location,
            nightScore: nightScore
        )
    }

    // MARK: - Current Location (Phase 4C)

    private static func resolveCurrentLocation(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload,
        selectedLocation: SelectedLocation?,
        expectedRequest: WatchCurrentLocationRequestContext?,
        nightScore: Int,
        fallbackLocation: CrossSurfaceLocationContext?
    ) -> Outcome {
        // Exact schema: v2 Current Location only. Do not reinterpret v1 as CL transport.
        guard transported.payloadVersion
                == WatchObservingQualityPayload.currentLocationPayloadVersion else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        // v2 CL transport requires echoed request correlation context.
        guard let requestContext = transported.requestContext else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Uncorrelated CL transport (push / no outstanding request) → night only.
        guard let expectedRequest, expectedRequest.isStructurallyValid else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        guard WatchObservingQualityCurrentLocationAssociation.requestCorrelationMatches(
            expected: expectedRequest,
            transported: requestContext
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        let location = transported.location
        guard location.source == .currentGPS,
              location.savedLocationID == nil,
              location.hasConsistentIdentity,
              location.hasValidGeographicCoordinates else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Transported context must match request and conditions coordinates.
        guard WatchObservingQualityCurrentLocationAssociation.matches(
            request: expectedRequest,
            context: location
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        guard WatchObservingQualityCurrentLocationAssociation.matches(
            context: location,
            conditionsLocation: conditions.location
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        guard WatchObservingQualityCurrentLocationAssociation.matches(
            request: expectedRequest,
            conditionsLocation: conditions.location
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Selected location, when known, must be Current Location (coords optional if placeholder).
        if let selectedLocation {
            guard selectedLocation.source == .currentGPS,
                  selectedLocation.id == nil else {
                return .nightOnly(nightScore: nightScore, location: fallbackLocation)
            }
        }

        // Snapshot must not claim a saved brightness ID.
        if transported.transportedSnapshot.brightnessSavedLocationID != nil {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        return recomputeAndAgree(
            conditions: conditions,
            transported: transported,
            location: location,
            nightScore: nightScore
        )
    }

    // MARK: - Shared recompute

    private static func recomputeAndAgree(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload,
        location: CrossSurfaceLocationContext,
        nightScore: Int
    ) -> Outcome {
        guard transported.transportedSnapshot.nightConditionsScore == nightScore else {
            return .nightOnly(nightScore: nightScore, location: location)
        }

        guard let sample = transported.makeSample() else {
            return .nightOnly(nightScore: nightScore, location: location)
        }

        // CL samples must not carry savedLocationID.
        if location.source == .currentGPS, sample.savedLocationID != nil {
            return .nightOnly(nightScore: nightScore, location: location)
        }

        let recomputed = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: nightScore,
                location: location,
                sample: sample,
                assessedAt: transported.transportedSnapshot.assessedAt
            )
        )

        let t = transported.transportedSnapshot
        let agrees =
            recomputed.brightnessAvailability == t.brightnessAvailability
            && recomputed.nightConditionsScore == t.nightConditionsScore
            && recomputed.observingQualityScore == t.observingQualityScore
            && recomputed.modeledZenithBrightness == t.modeledZenithBrightness
            && recomputed.brightnessDataset == t.brightnessDataset
            && recomputed.brightnessSavedLocationID == t.brightnessSavedLocationID
            && recomputed.brightnessLookupLatitude == t.brightnessLookupLatitude
            && recomputed.brightnessLookupLongitude == t.brightnessLookupLongitude

        guard agrees, recomputed.brightnessAvailability == .available else {
            return .nightOnly(nightScore: nightScore, location: location)
        }

        return .enhanced(recomputed, location)
    }

    /// Persisted document for an enhanced outcome only.
    ///
    /// Night-only outcomes return `nil` so the staged pair path **clears**
    /// `watchObservingQuality.json` rather than storing an unavailable snapshot.
    public static func document(
        from outcome: Outcome,
        conditions: ViewingConditions
    ) -> WatchObservingQualityDocument? {
        switch outcome {
        case let .enhanced(snapshot, location):
            return WatchObservingQualityDocument(
                snapshot: snapshot,
                location: location,
                associatedNightConditionsScore: snapshot.nightConditionsScore,
                associatedConditionsLocationID: conditions.location.id,
                associatedLatitude: conditions.location.latitude,
                associatedLongitude: conditions.location.longitude
            )
        case .nightOnly:
            return nil
        }
    }

    // MARK: - Durable restore (canonical recompute)

    /// Validates a persisted OQ document and returns a **recomputed** outcome.
    ///
    /// Raw persisted scores are diagnostic only — the same trust model as live transport.
    /// Request UUID is **not** required. Malformed/tampered available documents fall back
    /// to exact night score (never “enhanced” with untrusted fields).
    public static func resolvePersisted(
        document: WatchObservingQualityDocument?,
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?
    ) -> Outcome {
        guard let nightAssessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return .nightOnly(
                nightScore: 0,
                location: selectedLocation.flatMap(CrossSurfaceLocationContext.make(from:))
            )
        }
        let nightScore = nightAssessment.calculatedScore
        let fallbackLocation = selectedLocation.flatMap(CrossSurfaceLocationContext.make(from:))
            ?? document?.location

        guard let document else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Exact supported schema only (unknown future → night).
        guard document.schemaVersion == WatchObservingQualityDocument.currentSchemaVersion else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        switch document.location.source {
        case .saved:
            return resolvePersistedSaved(
                document: document,
                conditions: conditions,
                selectedLocation: selectedLocation,
                nightScore: nightScore,
                fallbackLocation: fallbackLocation
            )
        case .currentGPS:
            return resolvePersistedCurrentLocation(
                document: document,
                conditions: conditions,
                selectedLocation: selectedLocation,
                nightScore: nightScore,
                fallbackLocation: fallbackLocation
            )
        }
    }

    /// True when durable restore would enhance (after full canonical recompute agreement).
    public static func isAssociated(
        document: WatchObservingQualityDocument,
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?
    ) -> Bool {
        if case .enhanced = resolvePersisted(
            document: document,
            conditions: conditions,
            selectedLocation: selectedLocation
        ) {
            return true
        }
        return false
    }

    private static func resolvePersistedSaved(
        document: WatchObservingQualityDocument,
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?,
        nightScore: Int,
        fallbackLocation: CrossSurfaceLocationContext?
    ) -> Outcome {
        let location = document.location
        guard location.source == .saved,
              location.savedLocationID != nil,
              location.hasConsistentIdentity,
              location.hasValidGeographicCoordinates else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        guard document.associatedNightConditionsScore == nightScore,
              document.snapshot.nightConditionsScore == nightScore else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        guard WatchObservingQualitySavedLocationAssociation.matches(
            context: location,
            conditionsLocation: conditions.location
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        guard WatchObservingQualitySavedLocationAssociation.matches(
            savedLocationID: document.associatedConditionsLocationID,
            latitude: document.associatedLatitude,
            longitude: document.associatedLongitude,
            otherSavedLocationID: conditions.location.id,
            otherLatitude: conditions.location.latitude,
            otherLongitude: conditions.location.longitude
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        if let selectedLocation {
            guard WatchObservingQualitySavedLocationAssociation.matches(
                selected: selectedLocation,
                context: location
            ) else {
                return .nightOnly(nightScore: nightScore, location: fallbackLocation)
            }
        }

        return recomputePersistedAndAgree(
            document: document,
            location: location,
            nightScore: nightScore,
            fallbackLocation: fallbackLocation,
            requireNilBrightnessSavedID: false
        )
    }

    private static func resolvePersistedCurrentLocation(
        document: WatchObservingQualityDocument,
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?,
        nightScore: Int,
        fallbackLocation: CrossSurfaceLocationContext?
    ) -> Outcome {
        let location = document.location
        guard location.source == .currentGPS,
              location.savedLocationID == nil,
              location.hasConsistentIdentity,
              location.hasValidGeographicCoordinates,
              !(location.latitude == 0 && location.longitude == 0) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Associated conditions identity: nil saved IDs + strict coords + night score.
        guard document.associatedConditionsLocationID == nil,
              conditions.location.id == nil,
              document.associatedNightConditionsScore == nightScore,
              document.snapshot.nightConditionsScore == nightScore else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        guard WatchObservingQualityCurrentLocationAssociation.matches(
            context: location,
            conditionsLocation: conditions.location
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        guard WatchObservingQualityCurrentLocationAssociation.coordinatesMatch(
            latitude: document.associatedLatitude,
            longitude: document.associatedLongitude,
            otherLatitude: conditions.location.latitude,
            otherLongitude: conditions.location.longitude
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        if let selectedLocation {
            guard selectedLocation.source == .currentGPS, selectedLocation.id == nil else {
                return .nightOnly(nightScore: nightScore, location: fallbackLocation)
            }
            if !(selectedLocation.latitude == 0 && selectedLocation.longitude == 0) {
                guard WatchObservingQualityCurrentLocationAssociation.coordinatesMatch(
                    latitude: selectedLocation.latitude,
                    longitude: selectedLocation.longitude,
                    otherLatitude: location.latitude,
                    otherLongitude: location.longitude
                ) else {
                    return .nightOnly(nightScore: nightScore, location: fallbackLocation)
                }
            }
        }

        // Snapshot must not claim saved brightness association on CL.
        if document.snapshot.brightnessSavedLocationID != nil {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        return recomputePersistedAndAgree(
            document: document,
            location: location,
            nightScore: nightScore,
            fallbackLocation: fallbackLocation,
            requireNilBrightnessSavedID: true
        )
    }

    /// Reconstruct sample from persisted snapshot, recompute via shared resolver, require agreement.
    private static func recomputePersistedAndAgree(
        document: WatchObservingQualityDocument,
        location: CrossSurfaceLocationContext,
        nightScore: Int,
        fallbackLocation: CrossSurfaceLocationContext?,
        requireNilBrightnessSavedID: Bool
    ) -> Outcome {
        let snap = document.snapshot

        // Only available documents may enhance; unavailable/night docs are not durable OQ authority.
        guard snap.brightnessAvailability == .available else {
            return .nightOnly(nightScore: nightScore, location: location)
        }

        guard let brightness = snap.modeledZenithBrightness,
              brightness.isFinite,
              ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(brightness) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        guard let dataset = snap.brightnessDataset,
              ModeledZenithBrightnessValidity.isDatasetCurrent(dataset) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        guard let lookupLat = snap.brightnessLookupLatitude,
              let lookupLon = snap.brightnessLookupLongitude,
              ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
                latitude: lookupLat,
                longitude: lookupLon
              ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }
        if requireNilBrightnessSavedID, snap.brightnessSavedLocationID != nil {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        let sample = ModeledZenithBrightnessSample(
            latitude: lookupLat,
            longitude: lookupLon,
            modeledZenithSkyBrightness: brightness,
            dataset: dataset,
            sampledAt: snap.assessedAt,
            savedLocationID: snap.brightnessSavedLocationID
        )
        if requireNilBrightnessSavedID, sample.savedLocationID != nil {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        let recomputed = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: nightScore,
                location: location,
                sample: sample,
                assessedAt: snap.assessedAt
            )
        )

        let agrees =
            recomputed.brightnessAvailability == .available
            && recomputed.brightnessAvailability == snap.brightnessAvailability
            && recomputed.nightConditionsScore == snap.nightConditionsScore
            && recomputed.observingQualityScore == snap.observingQualityScore
            && recomputed.modeledZenithBrightness == snap.modeledZenithBrightness
            && recomputed.brightnessDataset == snap.brightnessDataset
            && recomputed.brightnessSavedLocationID == snap.brightnessSavedLocationID
            && recomputed.brightnessLookupLatitude == snap.brightnessLookupLatitude
            && recomputed.brightnessLookupLongitude == snap.brightnessLookupLongitude

        guard agrees else {
            return .nightOnly(nightScore: nightScore, location: location)
        }

        // Display authority is the recomputed snapshot, not the raw file bytes.
        return .enhanced(recomputed, location)
    }
}
