import Foundation

/// Sole production factory for Night Conditions widget cache publication.
///
/// Requires explicit location context for OQ enrichment — never infers identity
/// from weather/`CachedLocation` alone.
public enum WidgetNightSummaryPublisher: Sendable {
    /// Builds a complete v1 `WidgetNightSummary` with dual night/OQ scores.
    ///
    /// - Parameters:
    ///   - conditions: Weather/night conditions for the target location.
    ///   - location: Explicit source identity for brightness association.
    ///   - brightness: Explicit load policy (App Group vs supplied sample / unavailable).
    ///   - baseURL: Companion file base (tests inject temp dirs).
    public static func makeEnriched(
        from conditions: ViewingConditions,
        location: CrossSurfaceLocationContext,
        brightness: CrossSurfaceBrightnessInput = .loadFromAppGroup,
        baseURL: URL? = AppGroupStorage.containerURL
    ) -> WidgetNightSummary? {
        guard let base = makeNightBase(from: conditions) else { return nil }

        let sample = CrossSurfaceBrightnessSampleLoading.resolve(
            brightness,
            for: location,
            baseURL: baseURL
        )
        let snapshot = CrossSurfaceObservingQualityResolver.resolve(
            .init(
                nightConditionsScore: base.nightScore,
                location: location,
                sample: sample,
                assessedAt: conditions.fetchedAt
            )
        )

        return assemble(base: base, snapshot: snapshot)
    }

    /// Complete v1 schema with brightness unavailable and OQ equal to night score.
    ///
    /// Use when the caller has no authoritative location source identity.
    /// Does not fabricate a dummy Current Location context and performs no App Group sample I/O.
    public static func makeNightOnlyV1(
        from conditions: ViewingConditions
    ) -> WidgetNightSummary? {
        guard let base = makeNightBase(from: conditions) else { return nil }
        let snapshot = CrossSurfaceObservingQualitySnapshot.nightOnly(
            nightConditionsScore: base.nightScore,
            assessedAt: conditions.fetchedAt,
            payloadVersion: CrossSurfaceObservingQualitySnapshot.currentPayloadVersion
        )
        return assemble(base: base, snapshot: snapshot)
    }

    private static func assemble(
        base: NightBase,
        snapshot: CrossSurfaceObservingQualitySnapshot
    ) -> WidgetNightSummary {
        // Headline verdict tracks OQ band; early/late/factors remain night-condition details.
        let headlineVerdict = CrossSurfaceHeadlineScorePresentation.verdict(
            for: snapshot.observingQualityScore
        )
        return WidgetNightSummary(
            generatedAt: base.generatedAt,
            locationName: base.locationName,
            latitude: base.latitude,
            longitude: base.longitude,
            savedLocationID: base.savedLocationID,
            timeZoneIdentifier: base.timeZoneIdentifier,
            score: snapshot.observingQualityScore,
            verdict: headlineVerdict,
            earlyQuality: base.earlyQuality,
            lateQuality: base.lateQuality,
            trend: base.trend,
            bestWindow: base.bestWindow,
            primaryMessage: base.primaryMessage,
            factors: base.factors,
            hasAstronomicalNight: base.hasAstronomicalNight,
            payloadVersion: CrossSurfaceObservingQualitySnapshot.currentPayloadVersion,
            nightConditionsScore: snapshot.nightConditionsScore,
            observingQualityScore: snapshot.observingQualityScore,
            brightnessAvailability: snapshot.brightnessAvailability,
            modeledZenithBrightness: snapshot.modeledZenithBrightness,
            brightnessDataset: snapshot.brightnessDataset,
            brightnessLookupLatitude: snapshot.brightnessLookupLatitude,
            brightnessLookupLongitude: snapshot.brightnessLookupLongitude,
            brightnessSavedLocationID: snapshot.brightnessSavedLocationID
        )
    }

    // MARK: - Internal night base (no OQ)

    struct NightBase {
        var generatedAt: Date
        var locationName: String
        var latitude: Double
        var longitude: Double
        var savedLocationID: UUID?
        var timeZoneIdentifier: String?
        var nightScore: Int
        var verdict: String
        var earlyQuality: String
        var lateQuality: String
        var trend: NightQualityAssessment.Trend
        var bestWindow: NightQualityAssessment.TimeWindow?
        var primaryMessage: String
        var factors: [NightQualityDisplayFactor]
        var hasAstronomicalNight: Bool
    }

    static func makeNightBase(from conditions: ViewingConditions) -> NightBase? {
        guard let assessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return nil
        }
        let presentation = NightQualityPresentation(assessment: assessment)
        let firstHalf = assessment.firstHalfScore.map(NightQualityAssessment.Rating.from)
        let secondHalf = assessment.secondHalfScore.map(NightQualityAssessment.Rating.from)
        return NightBase(
            generatedAt: conditions.fetchedAt,
            locationName: conditions.location.name,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            savedLocationID: conditions.location.id,
            timeZoneIdentifier: conditions.timeZoneIdentifier,
            nightScore: assessment.calculatedScore,
            verdict: assessment.rating.shortLabel,
            earlyQuality: (firstHalf ?? assessment.rating).shortLabel,
            lateQuality: (secondHalf ?? assessment.rating).shortLabel,
            trend: assessment.trend,
            bestWindow: assessment.bestWindow,
            primaryMessage: presentation.primaryMessage,
            factors: presentation.factors,
            hasAstronomicalNight: !assessment.hourlyRatings.isEmpty
        )
    }
}
