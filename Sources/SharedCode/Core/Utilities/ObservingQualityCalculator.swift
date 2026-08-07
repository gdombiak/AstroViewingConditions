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

    // MARK: - Product calibration anchors (not Bortle classes; internal)

    /// Provisional base-penalty anchors: (mag/arcsec², base penalty points).
    static let basePenaltyAnchors: [(brightness: Double, penalty: Double)] = [
        (17.5, 8.0),
        (18.5, 7.0),
        (19.5, 5.0),
        (20.5, 3.0),
        (21.3, 1.0),
        (21.75, 0.0),
    ]

    /// Usability weight anchors: (nightConditionsScore, weight).
    static let usabilityWeightAnchors: [(score: Double, weight: Double)] = [
        (35, 0.00),
        (45, 0.25),
        (65, 0.75),
        (80, 1.00),
    ]

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
        let clampedNight = clampScore(nightConditionsScore)

        guard let brightness = modeledZenithSkyBrightness,
              let base = baseLightPollutionPenalty(modeledZenithSkyBrightness: brightness)
        else {
            return ObservingQualityAssessment(
                score: clampedNight,
                nightConditionsScore: clampedNight,
                lightPollution: nil
            )
        }

        let weight = usabilityWeight(nightConditionsScore: clampedNight)
        let applied = base * weight
        let raw = Double(clampedNight) - applied
        let overall = clampScore(Int(raw.rounded()))

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
        guard ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(
            modeledZenithSkyBrightness
        ) else {
            return nil
        }
        return piecewiseLinear(
            x: modeledZenithSkyBrightness,
            anchors: basePenaltyAnchors.map { ($0.brightness, $0.penalty) }
        )
    }

    /// Usability weight for an existing night-conditions score (0…1).
    static func usabilityWeight(nightConditionsScore: Int) -> Double {
        piecewiseLinear(
            x: Double(clampScore(nightConditionsScore)),
            anchors: usabilityWeightAnchors.map { ($0.score, $0.weight) }
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
        min(100, max(0, score))
    }
}
