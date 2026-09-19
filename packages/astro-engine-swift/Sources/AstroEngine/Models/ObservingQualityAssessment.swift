import Foundation

/// Assessment of modeled zenith sky brightness (mag/arcsec²) for light-pollution scoring.
///
/// - Note: Values are **modeled zenith sky brightness**, not Bortle classes.
///   “Light pollution” is the product concept; brightness is the atlas quantity.
public struct LightPollutionAssessment: Sendable, Equatable {
    /// Modeled zenith sky brightness in mag/arcsec² (larger = darker).
    public let modeledZenithSkyBrightness: Double
    /// Base penalty in score points before usability weighting (0…8 provisional scale).
    public let basePenalty: Double
    /// Penalty actually subtracted after usability weighting.
    public let appliedPenalty: Double

    public init(
        modeledZenithSkyBrightness: Double,
        basePenalty: Double,
        appliedPenalty: Double
    ) {
        self.modeledZenithSkyBrightness = modeledZenithSkyBrightness
        self.basePenalty = basePenalty
        self.appliedPenalty = appliedPenalty
    }
}

/// Overall observing-quality score: existing night-conditions score adjusted for light pollution.
///
/// `nightConditionsScore` is the existing 0–100 public-looking night assessment
/// (weather + darkness + Moon). `score` is `observingQualityScore` after the light-pollution penalty.
/// Rating bands are intentionally **not** applied here — they remain calibrated for night conditions only.
public struct ObservingQualityAssessment: Sendable, Equatable {
    /// Final observing-quality score, clamped to 0…100.
    public let score: Int
    /// Existing night-conditions score used as the base (also clamped to 0…100 for calculation).
    public let nightConditionsScore: Int
    /// Present when supported modeled zenith sky brightness was supplied; `nil` if unavailable.
    public let lightPollution: LightPollutionAssessment?

    public init(
        score: Int,
        nightConditionsScore: Int,
        lightPollution: LightPollutionAssessment?
    ) {
        self.score = score
        self.nightConditionsScore = nightConditionsScore
        self.lightPollution = lightPollution
    }

    /// True when modeled zenith brightness was missing or outside the supported atlas range.
    public var lightPollutionDataUnavailable: Bool {
        lightPollution == nil
    }
}
