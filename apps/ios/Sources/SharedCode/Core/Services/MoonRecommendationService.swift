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

    public init(sampleInterval: TimeInterval = 30 * 60) {
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
        let usefulWindow = context.nightQuality.bestWindow.map {
            NightQualityAssessment.TimeWindow(start: $0.start, end: $0.end)
        } ?? NightQualityAssessment.TimeWindow(
            start: context.astronomicalNightStart,
            end: context.astronomicalNightEnd
        )
        let usefulSamples = observation.positionSamples.filter {
            $0.time >= usefulWindow.start && $0.time <= usefulWindow.end
        }
        let visibleSamples = usefulSamples.filter { $0.altitude > 0 }
        guard !visibleSamples.isEmpty else { return nil }

        let bestSample = visibleSamples.max { $0.altitude < $1.altitude }

        let visibleWindow = visibilityWindow(
            usefulWindow: usefulWindow,
            visibleSamples: visibleSamples,
            bestSample: bestSample
        )
        let score = score(
            observation: observation,
            visibleFraction: visibleFraction(samples: usefulSamples),
            weatherQuality: weatherQuality(in: visibleWindow, context: context)
        )
        let reasons = reasons(
            observation: observation,
            usefulWindow: usefulWindow,
            visibleSamples: visibleSamples,
            visibleFraction: visibleFraction(samples: usefulSamples),
            weatherQuality: weatherQuality(in: visibleWindow, context: context)
        )

        let recommendation = TargetRecommendation(
            target: target,
            score: score,
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
                visibleSamples: visibleSamples
            ),
            bestAltitude: bestSample?.altitude,
            bestAzimuth: bestSample?.azimuth,
            scoreBreakdown: scoreBreakdown(
                observation: observation,
                visibleFraction: visibleFraction(samples: usefulSamples),
                weatherQuality: weatherQuality(in: visibleWindow, context: context)
            )
        )
        return recommendation
    }

    private func visibilityWindow(
        usefulWindow: NightQualityAssessment.TimeWindow,
        visibleSamples: [MoonPositionSample],
        bestSample: MoonPositionSample?
    ) -> TargetVisibilityWindow {
        let bestTime = bestSample?.time ?? usefulWindow.start.addingTimeInterval(usefulWindow.duration / 2)
        let start = visibleSamples.first?.time ?? usefulWindow.start
        let end = visibleSamples.last?.time.addingTimeInterval(30 * 60) ?? usefulWindow.end

        return TargetVisibilityWindow(
            start: max(start, usefulWindow.start),
            end: min(max(end, start.addingTimeInterval(30 * 60)), usefulWindow.end),
            bestTime: bestTime,
            maxAltitude: bestSample?.altitude,
            direction: bestSample?.azimuth.map(Self.compassDirection),
            azimuth: bestSample?.azimuth
        )
    }

    private func score(
        observation: MoonObservationData,
        visibleFraction: Double,
        weatherQuality: Double
    ) -> Int {
        let phaseQuality = phaseQuality(observation: observation)
        let rawScore = phaseQuality * 45 + visibleFraction * 30 + weatherQuality * 25
        let cappedScore = observation.illumination <= 8 ? min(rawScore, 35) : rawScore
        return Int(round(min(max(cappedScore, 0), 100)))
    }

    private func scoreBreakdown(
        observation: MoonObservationData,
        visibleFraction: Double,
        weatherQuality: Double
    ) -> [String] {
        let phaseComponent = phaseQuality(observation: observation) * 45
        let visibilityComponent = visibleFraction * 30
        let weatherComponent = weatherQuality * 25
        let rawScore = phaseComponent + visibilityComponent + weatherComponent
        let cappedScore = observation.illumination <= 8 ? min(rawScore, 35) : rawScore

        return [
            String(format: "phase %.1f", phaseComponent),
            String(format: "visibility %.1f", visibilityComponent),
            String(format: "weather %.1f", weatherComponent),
            String(format: "raw %.1f", rawScore),
            String(format: "capAdjusted %.1f", cappedScore)
        ]
    }

    private func phaseQuality(observation: MoonObservationData) -> Double {
        let phase = observation.phase
        let illumination = observation.illumination

        if illumination <= 8 || phase <= 0.04 || phase >= 0.96 {
            return 0.12
        }

        let quarterDistance = min(abs(phase - 0.25), abs(phase - 0.75))
        if quarterDistance <= 0.08 {
            return 1.0
        }

        if illumination <= 45 {
            return 0.82
        }

        if illumination >= 90 {
            return 0.70
        }

        return 0.68
    }

    private func reasons(
        observation: MoonObservationData,
        usefulWindow: NightQualityAssessment.TimeWindow,
        visibleSamples: [MoonPositionSample],
        visibleFraction: Double,
        weatherQuality: Double
    ) -> [TargetRecommendationReason] {
        var reasons: [TargetRecommendationReason] = []
        let phase = observation.phase

        if visibleSamples.isEmpty || visibleFraction < 0.25 || observation.alwaysDown {
            reasons.append(.moonBelowUsefulWindow)
        }

        if observation.illumination <= 8 || phase <= 0.04 || phase >= 0.96 {
            reasons.append(.newMoonDarkSky)
        } else if min(abs(phase - 0.25), abs(phase - 0.75)) <= 0.08 {
            reasons.append(.excellentMoonCraterDetail)
        } else if observation.illumination >= 90 {
            reasons.append(.brightFullMoonDeepSkyImpact)
        } else if visibleFraction >= 0.25 {
            reasons.append(.moonVisibleUsefulWindow)
        }

        if let set = observation.set,
           set > usefulWindow.start,
           set < usefulWindow.end.addingTimeInterval(-2 * 3600),
           observation.illumination >= 40 {
            reasons.append(.moonSetsEarlyDarkSkyLater)
        }

        if weatherQuality < 0.45 {
            reasons.append(.poorWeather)
        }

        return reasons.isEmpty ? [.moonVisibleUsefulWindow] : reasons
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

    private func visibleFraction(samples: [MoonPositionSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let visibleCount = samples.filter { $0.altitude > 0 }.count
        return Double(visibleCount) / Double(samples.count)
    }

    private func weatherQuality(
        in window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> Double {
        let overlappingRatings = context.nightQuality.hourlyRatings.filter { rating in
            let ratingEnd = rating.time.addingTimeInterval(3600)
            return ratingEnd > window.start && rating.time < window.end
        }

        guard !overlappingRatings.isEmpty else {
            return 1 - min(max(context.nightQuality.details.cloudCoverScore / 100, 0), 1)
        }

        let averageScore = overlappingRatings.map(\.score).reduce(0, +) / Double(overlappingRatings.count)
        return 1 - min(max(averageScore / 2, 0), 1)
    }

    private static func compassDirection(for azimuth: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        ]
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % directions.count
        return directions[index]
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
