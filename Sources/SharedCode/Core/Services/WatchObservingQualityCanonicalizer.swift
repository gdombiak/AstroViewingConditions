import Foundation

/// Watch-side validation + canonical recomputation of transported OQ (Phase 4B).
///
/// Transported scores are diagnostic only; the recomputed snapshot is authoritative.
public enum WatchObservingQualityCanonicalizer: Sendable {
    public enum Outcome: Sendable, Equatable {
        case enhanced(CrossSurfaceObservingQualitySnapshot, CrossSurfaceLocationContext)
        case nightOnly(nightScore: Int, location: CrossSurfaceLocationContext?)
    }

    /// Validates optional transport and returns recomputed enhancement or night-only fallback.
    public static func resolve(
        conditions: ViewingConditions,
        transported: WatchObservingQualityPayload?,
        selectedLocation: SelectedLocation?
    ) -> Outcome {
        guard let nightAssessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return .nightOnly(nightScore: 0, location: selectedLocation.flatMap(CrossSurfaceLocationContext.make(from:)))
        }
        let nightScore = nightAssessment.calculatedScore
        let fallbackLocation = selectedLocation.flatMap(CrossSurfaceLocationContext.make(from:))
            ?? transported?.location

        guard let transported else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Future / unknown version → night only
        guard transported.payloadVersion > 0,
              transported.payloadVersion <= WatchObservingQualityPayload.currentPayloadVersion else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        let location = transported.location
        guard location.source == .saved,
              location.savedLocationID != nil,
              location.hasConsistentIdentity,
              location.hasValidGeographicCoordinates else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Transported saved context must strictly match received conditions location.
        guard WatchObservingQualitySavedLocationAssociation.matches(
            context: location,
            conditionsLocation: conditions.location
        ) else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        // Selected saved location must strictly match transported context when known.
        if let selectedLocation {
            guard WatchObservingQualitySavedLocationAssociation.matches(
                selected: selectedLocation,
                context: location
            ) else {
                return .nightOnly(nightScore: nightScore, location: fallbackLocation)
            }
        }

        // Transported night must match conditions night score.
        guard transported.transportedSnapshot.nightConditionsScore == nightScore else {
            return .nightOnly(nightScore: nightScore, location: fallbackLocation)
        }

        guard let sample = transported.makeSample() else {
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

        // Compare recomputed vs transported (transport is diagnostic, not authority).
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
        case let .nightOnly(nightScore, location):
            guard let location else { return nil }
            let snap = CrossSurfaceObservingQualitySnapshot.nightOnly(
                nightConditionsScore: nightScore,
                assessedAt: conditions.fetchedAt,
                payloadVersion: CrossSurfaceObservingQualitySnapshot.currentPayloadVersion
            )
            return WatchObservingQualityDocument(
                snapshot: snap,
                location: location,
                associatedNightConditionsScore: nightScore,
                associatedConditionsLocationID: conditions.location.id,
                associatedLatitude: conditions.location.latitude,
                associatedLongitude: conditions.location.longitude
            )
        }
    }

    /// Whether a persisted document is still associated with the given conditions + selection.
    public static func isAssociated(
        document: WatchObservingQualityDocument,
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation?
    ) -> Bool {
        guard let nightAssessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return false
        }
        let nightScore = nightAssessment.calculatedScore
        guard document.associatedNightConditionsScore == nightScore else { return false }
        guard document.snapshot.nightConditionsScore == nightScore else { return false }

        // Document saved context versus current conditions location (ID + coordinates).
        guard WatchObservingQualitySavedLocationAssociation.matches(
            context: document.location,
            conditionsLocation: conditions.location
        ) else {
            return false
        }

        // Associated conditions coordinates must also agree strictly with current conditions.
        guard WatchObservingQualitySavedLocationAssociation.matches(
            savedLocationID: document.associatedConditionsLocationID,
            latitude: document.associatedLatitude,
            longitude: document.associatedLongitude,
            otherSavedLocationID: conditions.location.id,
            otherLatitude: conditions.location.latitude,
            otherLongitude: conditions.location.longitude
        ) else {
            return false
        }

        // Selected saved location versus document context when known.
        if let selectedLocation {
            guard WatchObservingQualitySavedLocationAssociation.matches(
                selected: selectedLocation,
                context: document.location
            ) else {
                return false
            }
        }

        return true
    }
}
