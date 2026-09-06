import Foundation
import AstroEngine

public struct PlanetPositionSample: Sendable, Hashable {
    public let time: Date
    public let altitude: Double
    public let azimuth: Double
    public let solarElongation: Double?

    public init(
        time: Date,
        altitude: Double,
        azimuth: Double,
        solarElongation: Double? = nil
    ) {
        self.time = time
        self.altitude = altitude
        self.azimuth = azimuth
        self.solarElongation = solarElongation
    }
}

public struct PlanetObservationData: Sendable, Hashable {
    public let targetID: String
    public let samples: [PlanetPositionSample]

    public init(targetID: String, samples: [PlanetPositionSample]) {
        self.targetID = targetID
        self.samples = samples
    }
}

public protocol PlanetAstronomyProviding: Sendable {
    func planetObservation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> PlanetObservationData?
}

public protocol PlanetTargetRecommendationProviding: Sendable {
    func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation?
}

/// Host adapter over the shared low-precision planet astronomy.
///
/// The orbital-element model, the Schlyter day number, the 900 s cadence and the
/// two-hour lead / one-hour trail around astronomical night live in
/// `AstroEngine.LowPrecisionPlanetObservationSampler`; see
/// contracts/procedures/planet-observation.md. What stays here is the host
/// target-identity mapping and the host DTO.
public struct LowPrecisionPlanetAstronomyProvider: PlanetAstronomyProviding {
    private let sampler: LowPrecisionPlanetObservationSampler

    public init(sampleInterval: TimeInterval = LowPrecisionPlanetObservationSampler.defaultSampleInterval) {
        self.sampler = LowPrecisionPlanetObservationSampler(sampleInterval: sampleInterval)
    }

    public func planetObservation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> PlanetObservationData? {
        guard let body = PlanetBody(rawValue: target.id.lowercased()) else {
            return nil
        }
        guard let samples = sampler.samples(
            body: body,
            latitude: context.location.latitude,
            longitude: context.location.longitude,
            nightStart: context.astronomicalNightStart,
            nightEnd: context.astronomicalNightEnd
        ) else {
            return nil
        }

        return PlanetObservationData(
            targetID: target.id,
            samples: samples.map {
                PlanetPositionSample(
                    time: $0.time,
                    altitude: $0.altitude,
                    azimuth: $0.azimuth,
                    solarElongation: $0.solarElongation
                )
            }
        )
    }
}

/// Host adapter over the shared planet recommendation.
///
/// Best-sample selection, the visibility window, scoring, Venus twilight
/// suitability and reason semantics live in `AstroEngine.PlanetRecommendation`;
/// see contracts/procedures/planet-recommendation.md. What stays here is
/// host-owned: the target-type guard, the presentation summary and the
/// validation logging.
public struct DefaultPlanetTargetRecommendationProvider: PlanetTargetRecommendationProviding {
    private let planetAstronomyProvider: any PlanetAstronomyProviding

    public init(planetAstronomyProvider: any PlanetAstronomyProviding = LowPrecisionPlanetAstronomyProvider()) {
        self.planetAstronomyProvider = planetAstronomyProvider
    }

    public func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation? {
        guard target.type == .planet,
              let observation = planetAstronomyProvider.planetObservation(for: target, context: context) else {
            return nil
        }

        let samples = observation.samples.map {
            PlanetRecommendation.Sample(
                time: $0.time,
                altitude: $0.altitude,
                azimuth: $0.azimuth,
                solarElongation: $0.solarElongation
            )
        }
        guard let evaluation = PlanetRecommendation.evaluate(
            targetID: target.id,
            samples: samples,
            nightStart: context.astronomicalNightStart,
            nightEnd: context.astronomicalNightEnd,
            cloudCoverScore: context.nightQuality.details.cloudCoverScore,
            hourlyRatings: context.nightQuality.hourlyRatings.map {
                PlanetRecommendation.HourlyRating(time: $0.time, score: $0.score)
            }
        ) else { return nil }

        let window = TargetVisibilityWindow(
            start: evaluation.window.start,
            end: evaluation.window.end,
            bestTime: evaluation.window.bestTime,
            maxAltitude: evaluation.window.maxAltitude,
            direction: Self.userFacingCompassDirection(for: evaluation.window.azimuth),
            azimuth: evaluation.window.azimuth
        )
        let reasons = evaluation.reasons.compactMap {
            TargetRecommendationReason(rawValue: $0.rawValue)
        }
        let recommendation = TargetRecommendation(
            target: target,
            score: evaluation.score,
            visibilityWindow: window,
            reasons: reasons,
            summary: summary(
                window: window,
                context: context
            )
        )
        TargetRecommendationDebugLogger.logRecommendation(
            recommendation,
            context: context,
            sampledTimeRange: TargetRecommendationDebugLogger.sampledTimeRange(
                start: observation.samples.first?.time,
                end: observation.samples.last?.time
            ),
            samplesSummary: Self.samplesSummary(
                allSamples: observation.samples,
                visibleSamples: Self.visibleSamples(observation.samples)
            ),
            bestAltitude: evaluation.window.maxAltitude,
            bestAzimuth: evaluation.window.azimuth,
            scoreBreakdown: Self.scoreBreakdown(evaluation: evaluation)
        )
        return recommendation
    }

    /// Samples at or above the shared visible-altitude threshold. Derived
    /// host-side so the validation summary keeps its pre-migration meaning
    /// without widening the shared recommendation result.
    static func visibleSamples(_ samples: [PlanetPositionSample]) -> [PlanetPositionSample] {
        samples.filter { $0.altitude >= Self.minimumVisibleAltitude }
    }

    private static var minimumVisibleAltitude: Double {
        EngineCalibration.current.planetRecommendation.visibility.minimum_altitude_degrees
    }

    private static func scoreBreakdown(evaluation: PlanetRecommendation.Result) -> [String] {
        let breakdown = evaluation.breakdown
        let weights = EngineCalibration.current.planetRecommendation.weights
        let altitudeComponent = breakdown.altitudeQuality * weights.altitude
        let weatherComponent = breakdown.weatherQuality * weights.weather
        let visibilityComponent = breakdown.visibilityQuality * weights.visibility
        let convenienceComponent = breakdown.convenience * weights.convenience
        let rawScore = altitudeComponent
            + weatherComponent
            + visibilityComponent
            + convenienceComponent
            - breakdown.lowAltitudePenalty

        return [
            String(format: "altitude %.1f", altitudeComponent),
            String(format: "weather %.1f", weatherComponent),
            String(format: "visibility %.1f", visibilityComponent),
            String(format: "convenience %.1f", convenienceComponent),
            String(format: "lowAltitudePenalty -%.1f", breakdown.lowAltitudePenalty),
            String(format: "raw %.1f", rawScore)
        ]
    }

    private func summary(
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> String {
        let direction = window.direction ?? ""
        let bestAltitude = window.maxAltitude ?? 0
        let altitude = Int(round(bestAltitude))

        if context.hasPoorTargetRecommendationConditions(in: window) {
            if window.bestTime < context.astronomicalNightStart {
                return "Well placed after sunset, but clouds may block the view."
            }

            if window.bestTime > context.astronomicalNightEnd.addingTimeInterval(-2 * 3600) {
                return "Well placed before dawn, but clouds may block the view."
            }

            return "Well placed tonight, but clouds may block the view."
        }

        if window.bestTime < context.astronomicalNightStart {
            if bestAltitude < 20 {
                return "Low in the \(direction) shortly after sunset; horizon obstructions may matter."
            }
            return "Look \(direction), about \(altitude)° high shortly after sunset."
        }

        if window.bestTime > context.astronomicalNightEnd.addingTimeInterval(-2 * 3600) {
            if bestAltitude < 20 {
                return "Visible before dawn, but low altitude limits the view."
            }
            if bestAltitude < 35 {
                return "Best before dawn; only moderately high."
            }
            return "Visible before dawn in the \(direction), about \(altitude)° high."
        }

        return "Highest around \(Self.timeFormatter.string(from: window.bestTime)), facing \(direction)."
    }

    public static func compassDirection(for azimuth: Double) -> String {
        PlanetRecommendation.compassDirection(forAzimuth: azimuth)
    }

    private static func userFacingCompassDirection(for azimuth: Double) -> String {
        compassDirection(for: azimuth).uppercased()
    }

    private static func samplesSummary(
        allSamples: [PlanetPositionSample],
        visibleSamples: [PlanetPositionSample]
    ) -> String {
        guard !allSamples.isEmpty else { return "0 samples" }

        let altitudeValues = allSamples.map(\.altitude)
        let azimuthValues = allSamples.map(\.azimuth)
        let solarElongationValues = allSamples.compactMap(\.solarElongation)
        let visibleAltitudeValues = visibleSamples.map(\.altitude)

        let altitudeSummary = minMaxSummary(values: altitudeValues)
        let azimuthSummary = minMaxSummary(values: azimuthValues)
        let solarElongationSummary = minMaxSummary(values: solarElongationValues)
        let visibleAltitudeSummary = minMaxSummary(values: visibleAltitudeValues)

        return "\(allSamples.count) samples; visible \(visibleSamples.count) >= \(Int(minimumVisibleAltitude))°; altitude \(altitudeSummary); visible altitude \(visibleAltitudeSummary); azimuth \(azimuthSummary); solar elongation \(solarElongationSummary)"
    }

    private static func minMaxSummary(values: [Double]) -> String {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return "n/a"
        }

        return String(format: "%.1f°...%.1f°", minValue, maxValue)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
