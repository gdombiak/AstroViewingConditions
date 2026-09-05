import Foundation

/// Canonical pure scorer that adjusts an existing night-conditions score for light pollution.
///
/// Formula:
/// ```
/// observingQualityScore = round(
///     nightConditionsScore
///     - baseLightPollutionPenalty(modeledZenithSkyBrightness)
///       * usabilityWeight(nightConditionsScore)
/// )
/// ```
/// Clamped to 0…100. No second Moon term (Moon is already in night conditions).
///
/// Canonical hybrid score used by the dashboard, widgets, watch, complications,
/// and Best Nearby (when every candidate has valid light-pollution data).
public enum ObservingQualityCalculator: Sendable {

    // MARK: - Public API

    /// Assess overall observing quality from an existing night-conditions score and optional atlas brightness.
    ///
    /// - Parameters:
    ///   - nightConditionsScore: Existing 0–100 night-conditions score (weather, darkness, Moon).
    ///   - modeledZenithSkyBrightness: Modeled zenith sky brightness in mag/arcsec², or `nil` if unavailable.
    ///     Values outside the supported atlas range, including non-finite values, are treated
    ///     as unavailable (not as pristine skies).
    public static func assess(
        nightConditionsScore: Int,
        modeledZenithSkyBrightness: Double?
    ) -> ObservingQualityAssessment {
        assess(
            nightConditionsScore: nightConditionsScore,
            modeledZenithSkyBrightness: modeledZenithSkyBrightness,
            calibration: EngineCalibration.current.observingQuality
        )
    }

    public static func assess(
        nightConditionsScore: Int,
        modeledZenithSkyBrightness: Double?,
        calibration: ObservingQualityCalibration
    ) -> ObservingQualityAssessment {
        let clampedNight = clampScore(nightConditionsScore, calibration: calibration)

        guard let brightness = modeledZenithSkyBrightness,
              let base = baseLightPollutionPenalty(
                modeledZenithSkyBrightness: brightness,
                calibration: calibration
              )
        else {
            return ObservingQualityAssessment(
                score: clampedNight,
                nightConditionsScore: clampedNight,
                lightPollution: nil
            )
        }

        let weight = usabilityWeight(nightConditionsScore: clampedNight, calibration: calibration)
        let applied = base * weight
        let raw = Double(clampedNight) - applied
        let overall = clampScore(Int(raw.rounded()), calibration: calibration)

        return ObservingQualityAssessment(
            score: overall,
            nightConditionsScore: clampedNight,
            lightPollution: LightPollutionAssessment(
                modeledZenithSkyBrightness: brightness,
                basePenalty: base,
                appliedPenalty: applied
            )
        )
    }

    // MARK: - Internal helpers (visible to tests via @testable import SharedCode)

    /// Base light-pollution penalty for a modeled zenith sky brightness (mag/arcsec²).
    /// Returns `nil` outside the supported atlas range so invalid values cannot be
    /// endpoint-clamped and mistaken for valid polluted or pristine skies.
    static func baseLightPollutionPenalty(modeledZenithSkyBrightness: Double) -> Double? {
        baseLightPollutionPenalty(
            modeledZenithSkyBrightness: modeledZenithSkyBrightness,
            calibration: EngineCalibration.current.observingQuality
        )
    }

    static func baseLightPollutionPenalty(
        modeledZenithSkyBrightness: Double,
        calibration: ObservingQualityCalibration
    ) -> Double? {
        guard calibration.isBrightnessInPlausibleRange(modeledZenithSkyBrightness) else {
            return nil
        }
        return piecewiseLinear(
            x: modeledZenithSkyBrightness,
            anchors: calibration.basePenaltyAnchors.map { ($0.brightness, $0.penalty) }
        )
    }

    /// Usability weight for an existing night-conditions score (0…1).
    static func usabilityWeight(nightConditionsScore: Int) -> Double {
        usabilityWeight(
            nightConditionsScore: nightConditionsScore,
            calibration: EngineCalibration.current.observingQuality
        )
    }

    static func usabilityWeight(
        nightConditionsScore: Int,
        calibration: ObservingQualityCalibration
    ) -> Double {
        piecewiseLinear(
            x: Double(clampScore(nightConditionsScore, calibration: calibration)),
            anchors: calibration.usabilityWeightAnchors.map { ($0.score, $0.weight) }
        )
    }

    /// Piecewise-linear interpolation with endpoint clamping. Anchors must be sorted by x ascending.
    static func piecewiseLinear(
        x: Double,
        anchors: [(Double, Double)]
    ) -> Double {
        precondition(!anchors.isEmpty, "anchors must not be empty")
        if x <= anchors[0].0 {
            return anchors[0].1
        }
        if x >= anchors[anchors.count - 1].0 {
            return anchors[anchors.count - 1].1
        }
        for index in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[index]
            let (x1, y1) = anchors[index + 1]
            if x >= x0 && x <= x1 {
                if x1 == x0 {
                    return y0
                }
                let t = (x - x0) / (x1 - x0)
                return y0 + t * (y1 - y0)
            }
        }
        return anchors[anchors.count - 1].1
    }

    static func clampScore(_ score: Int) -> Int {
        clampScore(score, calibration: EngineCalibration.current.observingQuality)
    }

    static func clampScore(_ score: Int, calibration: ObservingQualityCalibration) -> Int {
        min(calibration.scoreMax, max(calibration.scoreMin, score))
    }
}
