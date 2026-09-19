import Foundation
import AstroEngine

public protocol MoonAstronomyProviding: Sendable {
    func moonObservation(for context: TargetRecommendationContext) -> MoonObservationData
}

public protocol MoonTargetRecommendationProviding: Sendable {
    func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation?
}

public struct SunCalcMoonAstronomyProvider: MoonAstronomyProviding {
    private let sampler: SunCalcMoonObservationSampler

    public init(sampleInterval: TimeInterval = SunCalcMoonObservationSampler.defaultSampleInterval) {
        self.sampler = SunCalcMoonObservationSampler(sampleInterval: sampleInterval)
    }

    public func moonObservation(for context: TargetRecommendationContext) -> MoonObservationData {
        sampler.observation(
            latitude: context.location.latitude,
            longitude: context.location.longitude,
            nightStart: context.astronomicalNightStart,
            nightEnd: context.astronomicalNightEnd,
            fallback: context.moonInfo
        )
    }
}

/// Host adapter over the shared lunar recommendation.
///
/// Useful-window selection, visibility, scoring and reason semantics live in
/// `AstroEngine.MoonRecommendation`; see contracts/procedures/moon-recommendation.md.
/// What stays here is host-owned: the target-type guard, the presentation summary
/// and the validation logging.
public struct DefaultMoonTargetRecommendationProvider: MoonTargetRecommendationProviding {
    private let moonAstronomyProvider: any MoonAstronomyProviding

    public init(moonAstronomyProvider: any MoonAstronomyProviding = SunCalcMoonAstronomyProvider()) {
        self.moonAstronomyProvider = moonAstronomyProvider
    }

    public func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation? {
        guard target.type == .moon else { return nil }

        let observation = moonAstronomyProvider.moonObservation(for: context)
        guard let evaluation = MoonRecommendation.evaluate(
            observation: observation,
            nightStart: context.astronomicalNightStart,
            nightEnd: context.astronomicalNightEnd,
            bestWindow: context.nightQuality.bestWindow.map { ($0.start, $0.end) },
            cloudCoverScore: context.nightQuality.details.cloudCoverScore,
            hourlyRatings: context.nightQuality.hourlyRatings.map {
                MoonRecommendation.HourlyRating(time: $0.time, score: $0.score)
            }
        ) else { return nil }

        let visibleWindow = TargetVisibilityWindow(
            start: evaluation.window.start,
            end: evaluation.window.end,
            bestTime: evaluation.window.bestTime,
            maxAltitude: evaluation.window.maxAltitude,
            direction: evaluation.window.direction,
            azimuth: evaluation.window.azimuth
        )
        let reasons = evaluation.reasons.compactMap {
            TargetRecommendationReason(rawValue: $0.rawValue)
        }
        let recommendation = TargetRecommendation(
            target: target,
            score: evaluation.score,
            visibilityWindow: visibleWindow,
            reasons: reasons,
            summary: summary(
                observation: observation,
                visibleWindow: visibleWindow,
                reasons: reasons,
                context: context
            )
        )
        TargetRecommendationDebugLogger.logRecommendation(
            recommendation,
            context: context,
            sampledTimeRange: TargetRecommendationDebugLogger.sampledTimeRange(
                start: observation.positionSamples.first?.time,
                end: observation.positionSamples.last?.time
            ),
            samplesSummary: Self.samplesSummary(
                allSamples: observation.positionSamples,
                visibleSamples: Self.usefulVisibleSamples(observation: observation, context: context)
            ),
            bestAltitude: evaluation.window.maxAltitude,
            bestAzimuth: evaluation.window.azimuth,
            scoreBreakdown: Self.scoreBreakdown(observation: observation, evaluation: evaluation)
        )
        return recommendation
    }

    /// Samples above the horizon *inside the useful window*, which is the best
    /// conditions window when there is one and the astronomical night otherwise —
    /// the same total fallback the engine applies. Derived host-side so the
    /// validation summary keeps its pre-migration meaning without widening the
    /// shared recommendation result.
    static func usefulVisibleSamples(
        observation: MoonObservationData,
        context: TargetRecommendationContext
    ) -> [MoonPositionSample] {
        let usefulStart = context.nightQuality.bestWindow?.start ?? context.astronomicalNightStart
        let usefulEnd = context.nightQuality.bestWindow?.end ?? context.astronomicalNightEnd
        return observation.positionSamples.filter {
            $0.time >= usefulStart && $0.time <= usefulEnd && $0.altitude > 0
        }
    }

    private static func scoreBreakdown(
        observation: MoonObservationData,
        evaluation: MoonRecommendation.Result
    ) -> [String] {
        let breakdown = evaluation.breakdown
        let calibration = EngineCalibration.current.moonRecommendation
        let phaseComponent = breakdown.phaseQuality * calibration.weights.phase
        let visibilityComponent = breakdown.visibleFraction * calibration.weights.visibility
        let weatherComponent = breakdown.weatherQuality * calibration.weights.weather
        let rawScore = phaseComponent + visibilityComponent + weatherComponent
        let cappedScore = observation.illumination <= calibration.near_new_moon.illumination_at_or_below_percent
            ? min(rawScore, calibration.near_new_moon.score_cap) : rawScore

        return [
            String(format: "phase %.1f", phaseComponent),
            String(format: "visibility %.1f", visibilityComponent),
            String(format: "weather %.1f", weatherComponent),
            String(format: "raw %.1f", rawScore),
            String(format: "capAdjusted %.1f", cappedScore)
        ]
    }

    private func summary(
        observation: MoonObservationData,
        visibleWindow: TargetVisibilityWindow,
        reasons: [TargetRecommendationReason],
        context: TargetRecommendationContext
    ) -> String {
        if context.hasPoorTargetRecommendationConditions(in: visibleWindow) {
            if reasons.contains(.brightFullMoonDeepSkyImpact) {
                return "Bright full Moon; clouds may limit visibility."
            }

            if reasons.contains(.newMoonDarkSky) {
                return "New Moon is poor for lunar observing; clouds may limit visibility."
            }

            if reasons.contains(.moonBelowUsefulWindow) {
                return "Moon is only briefly visible, and clouds may limit visibility."
            }

            if reasons.contains(.excellentMoonCraterDetail) {
                let quarter = observation.phase < 0.5 ? "first quarter" : "last quarter"
                return "Good crater detail near \(quarter), but clouds may limit visibility."
            }

            return "Moon is visible, but clouds may limit visibility."
        }

        if reasons.contains(.moonBelowUsefulWindow) {
            return TargetRecommendationReason.moonBelowUsefulWindow.message
        }

        if reasons.contains(.newMoonDarkSky) {
            return TargetRecommendationReason.newMoonDarkSky.message
        }

        if reasons.contains(.brightFullMoonDeepSkyImpact) {
            return TargetRecommendationReason.brightFullMoonDeepSkyImpact.message
        }

        if reasons.contains(.excellentMoonCraterDetail) {
            let quarter = observation.phase < 0.5 ? "first quarter" : "last quarter"
            return "Excellent for crater detail near \(quarter)."
        }

        if reasons.contains(.poorWeather) {
            return TargetRecommendationReason.poorWeather.message
        }

        return reasons.first?.message ?? "Moon is visible tonight."
    }

    private static func samplesSummary(
        allSamples: [MoonPositionSample],
        visibleSamples: [MoonPositionSample]
    ) -> String {
        guard !allSamples.isEmpty else { return "0 samples" }

        let altitudeSummary = minMaxSummary(values: allSamples.map(\.altitude))
        let azimuthSummary = minMaxSummary(values: allSamples.compactMap(\.azimuth))
        let visibleAltitudeSummary = minMaxSummary(values: visibleSamples.map(\.altitude))

        return "\(allSamples.count) samples; visible \(visibleSamples.count) above horizon; altitude \(altitudeSummary); visible altitude \(visibleAltitudeSummary); azimuth \(azimuthSummary)"
    }

    private static func minMaxSummary(values: [Double]) -> String {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return "n/a"
        }

        return String(format: "%.1f°...%.1f°", minValue, maxValue)
    }
}
