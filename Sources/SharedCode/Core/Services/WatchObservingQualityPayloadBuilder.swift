import Foundation

/// Phone-side factory for optional watch OQ transport (Phase 4B saved + Phase 4C Current Location).
public enum WatchObservingQualityPayloadBuilder: Sendable {
    /// Builds a transport payload when authoritative saved identity + valid Phase 2 sample exist.
    public static func makeSavedLocationPayload(
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation,
        brightness: CrossSurfaceBrightnessInput = .loadFromAppGroup,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> WatchObservingQualityPayload? {
        guard selectedLocation.source == .saved else { return nil }
        guard let context = CrossSurfaceLocationContext.make(from: selectedLocation) else {
            return nil
        }
        guard context.source == .saved, context.savedLocationID != nil else { return nil }

        guard WatchObservingQualitySavedLocationAssociation.matches(
            selected: selectedLocation,
            conditionsLocation: conditions.location
        ) else {
            return nil
        }

        guard let nightAssessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return nil
        }
        let nightScore = nightAssessment.calculatedScore

        let sample = CrossSurfaceBrightnessSampleLoading.resolve(
            brightness,
            for: context,
            baseURL: baseURL
        )
        let snapshot = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: nightScore,
                location: context,
                sample: sample,
                assessedAt: conditions.fetchedAt
            )
        )
        guard snapshot.brightnessAvailability == .available else { return nil }

        return WatchObservingQualityPayload(
            payloadVersion: WatchObservingQualityPayload.savedLocationPayloadVersion,
            location: context,
            transportedSnapshot: snapshot,
            requestContext: nil
        )
    }

    /// Builds a Current Location OQ payload correlated to a watch-supplied request.
    ///
    /// - Parameters:
    ///   - conditions: Conditions for the **watch-requested** coordinate.
    ///   - request: Watch request context (must be structurally valid).
    ///   - sample: Explicit brightness sample at the requested coordinate, or nil.
    ///
    /// Does not load App Group Current Location companions (those are phone-selected, not watch GPS).
    public static func makeCurrentLocationPayload(
        conditions: ViewingConditions,
        request: WatchCurrentLocationRequestContext,
        sample: ModeledZenithBrightnessSample?
    ) -> WatchObservingQualityPayload? {
        guard request.isStructurallyValid else { return nil }
        guard WatchObservingQualityCurrentLocationAssociation.matches(
            request: request,
            conditionsLocation: conditions.location
        ) else {
            return nil
        }

        guard let nightAssessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return nil
        }
        let nightScore = nightAssessment.calculatedScore
        let context = request.asLocationContext

        // Sample must be coordinate-only (no saved ID) when present.
        if let sample, sample.savedLocationID != nil {
            return nil
        }

        let snapshot = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: nightScore,
                location: context,
                sample: sample,
                assessedAt: conditions.fetchedAt
            )
        )
        guard snapshot.brightnessAvailability == .available else { return nil }

        return WatchObservingQualityPayload(
            payloadVersion: WatchObservingQualityPayload.currentLocationPayloadVersion,
            location: context,
            transportedSnapshot: snapshot,
            requestContext: request
        )
    }
}
