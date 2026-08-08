import Foundation

/// Pure canonical observing-quality resolution for widgets and future watch surfaces.
///
/// Does not load App Group files or atlas providers. Does not trust precomputed OQ scores.
public enum CrossSurfaceObservingQualityResolver: Sendable {
    public struct Request: Sendable {
        public var nightConditionsScore: Int
        public var location: CrossSurfaceLocationContext
        public var sample: ModeledZenithBrightnessSample?
        public var assessedAt: Date

        public init(
            nightConditionsScore: Int,
            location: CrossSurfaceLocationContext,
            sample: ModeledZenithBrightnessSample?,
            assessedAt: Date = Date()
        ) {
            self.nightConditionsScore = nightConditionsScore
            self.location = location
            self.sample = sample
            self.assessedAt = assessedAt
        }
    }

    /// Canonical snapshot. Delegates penalty math to `ObservingQualityCalculator` only.
    public static func resolve(_ request: Request) -> CrossSurfaceObservingQualitySnapshot {
        let assessment = ObservingQualityCalculator.assess(
            nightConditionsScore: request.nightConditionsScore,
            modeledZenithSkyBrightness: nil
        )
        let clampedNight = assessment.nightConditionsScore

        guard request.location.isValidForBrightnessAssociation else {
            return .nightOnly(nightConditionsScore: clampedNight, assessedAt: request.assessedAt)
        }

        guard let sample = request.sample else {
            return .nightOnly(nightConditionsScore: clampedNight, assessedAt: request.assessedAt)
        }

        let sampleValid: Bool
        switch request.location.source {
        case .saved:
            guard let id = request.location.savedLocationID else {
                return .nightOnly(nightConditionsScore: clampedNight, assessedAt: request.assessedAt)
            }
            sampleValid = ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forSavedLocationID: id,
                locationLatitude: request.location.latitude,
                locationLongitude: request.location.longitude,
                maxAge: nil,
                now: request.assessedAt
            )
        case .currentGPS:
            guard sample.savedLocationID == nil else {
                return .nightOnly(nightConditionsScore: clampedNight, assessedAt: request.assessedAt)
            }
            sampleValid = ModeledZenithBrightnessValidity.isValid(
                sample: sample,
                forRequestAtLatitude: request.location.latitude,
                longitude: request.location.longitude,
                maxAge: nil,
                now: request.assessedAt
            )
        }

        guard sampleValid else {
            return .nightOnly(nightConditionsScore: clampedNight, assessedAt: request.assessedAt)
        }

        let oq = ObservingQualityCalculator.assess(
            nightConditionsScore: clampedNight,
            modeledZenithSkyBrightness: sample.modeledZenithSkyBrightness
        )

        if oq.lightPollution == nil {
            return .nightOnly(nightConditionsScore: clampedNight, assessedAt: request.assessedAt)
        }

        return CrossSurfaceObservingQualitySnapshot(
            payloadVersion: CrossSurfaceObservingQualitySnapshot.currentPayloadVersion,
            nightConditionsScore: oq.nightConditionsScore,
            observingQualityScore: oq.score,
            brightnessAvailability: .available,
            modeledZenithBrightness: sample.modeledZenithSkyBrightness,
            brightnessDataset: sample.dataset,
            brightnessLookupLatitude: sample.latitude,
            brightnessLookupLongitude: sample.longitude,
            brightnessSavedLocationID: sample.savedLocationID,
            assessedAt: request.assessedAt
        )
    }
}
