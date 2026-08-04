import Foundation

/// Phone-side factory for optional saved-location OQ transport (Phase 4B).
///
/// Current Location is intentionally never enhanced here (Phase 4C).
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

        // Strict Phase 4B association: matching saved ID **and** coordinates.
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
            location: context,
            transportedSnapshot: snapshot
        )
    }
}
