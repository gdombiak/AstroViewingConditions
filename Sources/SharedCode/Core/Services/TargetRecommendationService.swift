import Foundation

public struct TargetRecommendationContext: Sendable {
    public let location: CachedLocation
    public let astronomicalNightStart: Date
    public let astronomicalNightEnd: Date
    public let nightQuality: NightQualityAssessment
    public let moonInfo: MoonInfo

    public init(
        location: CachedLocation,
        astronomicalNightStart: Date,
        astronomicalNightEnd: Date,
        nightQuality: NightQualityAssessment,
        moonInfo: MoonInfo
    ) {
        self.location = location
        self.astronomicalNightStart = astronomicalNightStart
        self.astronomicalNightEnd = astronomicalNightEnd
        self.nightQuality = nightQuality
        self.moonInfo = moonInfo
    }
}

extension TargetRecommendationContext {
    var hasPoorTargetRecommendationConditions: Bool {
        BestSpotSearcher.calculateScore(nightQuality, elevation: location.elevation) < 30
            || nightQuality.details.cloudCoverScore >= 80
    }

    func hasPoorTargetRecommendationConditions(in window: TargetVisibilityWindow) -> Bool {
        guard !hasPoorTargetRecommendationConditions else { return true }

        let overlappingRatings = nightQuality.hourlyRatings.filter { rating in
            let ratingEnd = rating.time.addingTimeInterval(3600)
            return ratingEnd > window.start && rating.time < window.end
        }

        guard !overlappingRatings.isEmpty else { return false }

        let averageCloudCover = overlappingRatings
            .map(\.cloudCover)
            .reduce(0, +) / overlappingRatings.count
        return averageCloudCover >= 80
    }
}

enum TargetRecommendationDebugLogger {
    static func logRecommendation(
        _ recommendation: TargetRecommendation,
        context: TargetRecommendationContext,
        sampledTimeRange: String?,
        samplesSummary: String,
        bestAltitude: Double?,
        bestAzimuth: Double?,
        scoreBreakdown: [String]
    ) {
#if DEBUG
        /*
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current

        let coordinate = String(
            format: "%.4f, %.4f",
            context.location.latitude,
            context.location.longitude
        )
        let bestAltitudeText = bestAltitude.map { String(format: "%.1f°", $0) } ?? "n/a"
        let bestAzimuthText = bestAzimuth.map { String(format: "%.1f°", $0) } ?? "n/a"
        let reasons = recommendation.reasons.map(\.message).joined(separator: " | ")

        debugPrint(
            """
            [BestTargetsValidation]
            selectedDate: \(formatter.string(from: context.nightQuality.nightStart))
            observer: \(coordinate)
            timezone: \(TimeZone.current.identifier)
            astronomicalNight: \(formatter.string(from: context.astronomicalNightStart)) - \(formatter.string(from: context.astronomicalNightEnd))
            target: \(recommendation.target.name) (\(recommendation.target.type.rawValue))
            sampledTimeRange: \(sampledTimeRange ?? "n/a")
            samples: \(samplesSummary)
            selectedBestTime: \(formatter.string(from: recommendation.visibilityWindow.bestTime))
            bestAltAz: \(bestAltitudeText), \(bestAzimuthText)
            compassDirection: \(recommendation.visibilityWindow.direction ?? "n/a")
            visibilityWindow: \(formatter.string(from: recommendation.visibilityWindow.start)) - \(formatter.string(from: recommendation.visibilityWindow.end))
            scoreBreakdown: \(scoreBreakdown.joined(separator: "; "))
            finalScore: \(recommendation.score)
            reasons: \(reasons)
            """
        )
        */
#endif
    }

    static func sampledTimeRange(start: Date?, end: Date?) -> String? {
        guard let start, let end else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    static func logFinalSortedRecommendations(
        _ recommendations: [TargetRecommendation],
        context: TargetRecommendationContext,
        limit: Int
    ) {
#if DEBUG
        /*
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current

        let rows = recommendations.enumerated().map { index, recommendation in
            let window = recommendation.visibilityWindow
            let windowText = "\(formatter.string(from: window.start)) - \(formatter.string(from: window.end))"
            return "\(index + 1). \(recommendation.target.name) [\(recommendation.target.type.rawValue)] score=\(recommendation.score) best=\(formatter.string(from: window.bestTime)) window=\(windowText)"
        }

        debugPrint(
            """
            [BestTargetsFinalSorted]
            selectedDate: \(formatter.string(from: context.nightQuality.nightStart))
            limit: \(limit)
            count: \(recommendations.count)
            order:
            \(rows.joined(separator: "\n"))
            """
        )
        */
#endif
    }
}

public protocol TargetCatalogProvider: Sendable {
    func targets(for context: TargetRecommendationContext) -> [ObservableTarget]
}

public protocol TargetPositionProvider: Sendable {
    func visibilityWindows(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> [TargetVisibilityWindow]
}

public protocol TargetRecommendationScoring: Sendable {
    func recommendation(
        for target: ObservableTarget,
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> TargetRecommendation
}

public protocol TargetRecommendationProviding: Sendable {
    func recommendations(
        for context: TargetRecommendationContext,
        limit: Int
    ) -> [TargetRecommendation]
}

public final class DefaultTargetRecommendationService: TargetRecommendationProviding {
    private let catalogProvider: any TargetCatalogProvider
    private let positionProvider: any TargetPositionProvider
    private let scorer: any TargetRecommendationScoring
    private let moonRecommendationProvider: any MoonTargetRecommendationProviding
    private let planetRecommendationProvider: any PlanetTargetRecommendationProviding

    public init(
        catalogProvider: any TargetCatalogProvider = DefaultTargetCatalogProvider(),
        positionProvider: any TargetPositionProvider = DeepSkyTargetPositionProvider(),
        scorer: any TargetRecommendationScoring = DefaultTargetRecommendationScorer(),
        moonRecommendationProvider: any MoonTargetRecommendationProviding = DefaultMoonTargetRecommendationProvider(),
        planetRecommendationProvider: any PlanetTargetRecommendationProviding = DefaultPlanetTargetRecommendationProvider()
    ) {
        self.catalogProvider = catalogProvider
        self.positionProvider = positionProvider
        self.scorer = scorer
        self.moonRecommendationProvider = moonRecommendationProvider
        self.planetRecommendationProvider = planetRecommendationProvider
    }

    public func recommendations(
        for context: TargetRecommendationContext,
        limit: Int = 5
    ) -> [TargetRecommendation] {
        let recommendations = catalogProvider.targets(for: context)
            .flatMap { target in
                if target.type == .moon,
                   let moonRecommendation = moonRecommendationProvider.recommendation(
                    for: target,
                    context: context
                   ) {
                    return [moonRecommendation]
                }

                if target.type == .planet,
                   let planetRecommendation = planetRecommendationProvider.recommendation(
                    for: target,
                    context: context
                   ) {
                    return [planetRecommendation]
                }

                return positionProvider
                    .visibilityWindows(for: target, context: context)
                    .map { scorer.recommendation(for: target, window: $0, context: context) }
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.visibilityWindow.bestTime < rhs.visibilityWindow.bestTime
            }
            .prefix(limit)
            .map { $0 }
        TargetRecommendationDebugLogger.logFinalSortedRecommendations(
            recommendations,
            context: context,
            limit: limit
        )
        return recommendations
    }
}

public struct DefaultTargetRecommendationScorer: TargetRecommendationScoring {
    public init() {}

    public func recommendation(
        for target: ObservableTarget,
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> TargetRecommendation {
        let altitude = min(max((window.maxAltitude ?? 0) / 80, 0), 1)
        let darknessOverlap = Self.overlapFraction(
            windowStart: window.start,
            windowEnd: window.end,
            darknessStart: context.astronomicalNightStart,
            darknessEnd: context.astronomicalNightEnd
        )
        let weatherQuality = Self.weatherQuality(in: window, context: context)
        let moonPenalty = Self.moonPenalty(for: target, context: context)
        let equipmentPenalty = target.difficulty * 8

        let altitudeComponent = altitude * 30
        let darknessComponent = Self.darknessComponent(
            for: target.type,
            overlap: darknessOverlap
        )
        let weatherComponent = weatherQuality * 35

        let rawScore = altitudeComponent + darknessComponent + weatherComponent - moonPenalty - equipmentPenalty
        let score = Int(round(min(max(rawScore, 0), 100)))
        let reasons = Self.reasons(
            for: target,
            altitude: window.maxAltitude,
            darknessOverlap: darknessOverlap,
            weatherQuality: weatherQuality,
            moonPenalty: moonPenalty
        )

        let recommendation = TargetRecommendation(
            target: target,
            score: score,
            visibilityWindow: window,
            reasons: reasons,
            summary: Self.summary(
                for: target,
                window: window,
                reasons: reasons,
                moonPenalty: moonPenalty,
                context: context
            )
        )
        TargetRecommendationDebugLogger.logRecommendation(
            recommendation,
            context: context,
            sampledTimeRange: TargetRecommendationDebugLogger.sampledTimeRange(
                start: window.start,
                end: window.end
            ),
            samplesSummary: "visibility window only; altitude=\(Self.formattedDegrees(window.maxAltitude)), direction=\(window.direction ?? "n/a")",
            bestAltitude: window.maxAltitude,
            bestAzimuth: nil,
            scoreBreakdown: [
                "objectType \(target.deepSkyObjectType?.displayName ?? target.type.displayName)",
                String(format: "moonSensitivity %.2f", target.moonInterferenceSensitivity ?? 1),
                String(format: "altitude %.1f", altitudeComponent),
                String(format: "darkness %.1f", darknessComponent),
                String(format: "weather %.1f", weatherComponent),
                String(format: "moonPenalty -%.1f", moonPenalty),
                String(format: "equipmentPenalty -%.1f", equipmentPenalty),
                String(format: "raw %.1f", rawScore)
            ]
        )
        return recommendation
    }

    private static func darknessComponent(
        for type: ObservableTargetType,
        overlap: Double
    ) -> Double {
        switch type {
        case .deepSky, .meteorShower:
            return overlap * 35
        case .satellite:
            return 12 + overlap * 8
        case .moon, .planet:
            return 18 + overlap * 10
        }
    }

    private static func moonPenalty(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> Double {
        guard context.moonInfo.altitude > 0 else { return 0 }
        let illumination = Double(min(max(context.moonInfo.illumination, 0), 100)) / 100
        let altitudeFactor = min(max(context.moonInfo.altitude / 90, 0), 1)
        let interference = illumination * (0.5 + altitudeFactor * 0.5)

        switch target.type {
        case .deepSky:
            return interference
                * deepSkyMoonPenaltyCeiling(for: target.deepSkyObjectType)
                * (target.moonInterferenceSensitivity ?? 1)
        case .meteorShower:
            return interference * 28
        case .planet:
            return interference * 6
        case .satellite:
            return interference * 4
        case .moon:
            return 0
        }
    }

    private static func deepSkyMoonPenaltyCeiling(for objectType: DeepSkyObjectType?) -> Double {
        switch objectType {
        case .galaxy, .diffuseNebula:
            return 55
        case .globularCluster, .openCluster:
            return 28
        case .doubleStar:
            return 5
        case .planetaryNebula:
            return 22
        case nil:
            return 28
        }
    }

    private static func weatherQuality(
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

    private static func overlapFraction(
        windowStart: Date,
        windowEnd: Date,
        darknessStart: Date,
        darknessEnd: Date
    ) -> Double {
        guard windowEnd > windowStart else { return 0 }

        let overlapStart = max(windowStart, darknessStart)
        let overlapEnd = min(windowEnd, darknessEnd)
        guard overlapEnd > overlapStart else { return 0 }

        return overlapEnd.timeIntervalSince(overlapStart) / windowEnd.timeIntervalSince(windowStart)
    }

    private static func reasons(
        for target: ObservableTarget,
        altitude: Double?,
        darknessOverlap: Double,
        weatherQuality: Double,
        moonPenalty: Double
    ) -> [TargetRecommendationReason] {
        var reasons: [TargetRecommendationReason] = []

        if let altitude, altitude >= 45 {
            reasons.append(.highAltitude)
        } else if let altitude, altitude < 25 {
            reasons.append(.lowAltitude)
        }

        if darknessOverlap >= 0.7 {
            reasons.append(.astronomicalDarkness)
        } else if target.type == .deepSky || target.type == .meteorShower {
            reasons.append(.outsideAstronomicalDarkness)
        }

        if weatherQuality >= 0.7 {
            reasons.append(.goodNightQuality)
        } else if weatherQuality < 0.45 {
            reasons.append(.poorWeather)
        }

        if moonPenalty >= 10 {
            reasons.append(.moonInterference)
        }

        if target.difficulty >= 0.7 {
            reasons.append(.difficultTarget)
        }

        return reasons.isEmpty ? [.goodNightQuality] : reasons
    }

    private static func summary(
        for target: ObservableTarget,
        window: TargetVisibilityWindow,
        reasons: [TargetRecommendationReason],
        moonPenalty: Double,
        context: TargetRecommendationContext
    ) -> String {
        if context.hasPoorTargetRecommendationConditions(in: window) {
            switch target.type {
            case .deepSky, .meteorShower:
                if let altitude = window.maxAltitude, altitude >= 45 {
                    return "High in the sky, but clouds may block the view."
                }
                return "Clouds may block the view."
            case .planet:
                return "Well placed, but clouds may block the view."
            case .moon:
                return "Clouds may limit Moon visibility."
            case .satellite:
                return "Clouds may block the pass."
            }
        }

        if let moonSummary = deepSkyMoonSummary(
            for: target,
            altitude: window.maxAltitude,
            moonPenalty: moonPenalty
        ) {
            return moonSummary
        }

        return reasons.first?.message ?? "Visible tonight."
    }

    private static func deepSkyMoonSummary(
        for target: ObservableTarget,
        altitude: Double?,
        moonPenalty: Double
    ) -> String? {
        guard target.type == .deepSky else { return nil }
        let isHigh = (altitude ?? 0) >= 45

        switch target.deepSkyObjectType {
        case .galaxy where moonPenalty >= 20:
            return isHigh
                ? "High in the sky, but bright Moon will wash out galaxy detail."
                : "Well placed, but bright Moon will wash out galaxy detail."
        case .diffuseNebula where moonPenalty >= 20:
            return "Well placed, but bright Moon reduces nebula contrast."
        case .globularCluster where moonPenalty >= 10:
            return isHigh
                ? "High in the sky; bright Moon has a moderate impact."
                : "Visible, though bright Moon has a moderate impact."
        case .openCluster where moonPenalty >= 10:
            return "Visible despite bright Moon."
        case .doubleStar where moonPenalty >= 2:
            return "Good target even under bright Moon."
        case .planetaryNebula where moonPenalty >= 6:
            if (target.moonInterferenceSensitivity ?? 1) <= 0.7 {
                return "Small bright nebula; well placed despite bright Moon."
            }
            return isHigh
                ? "High in the sky; bright Moon may reduce contrast."
                : "Well placed, though bright Moon may reduce contrast."
        default:
            return nil
        }
    }

    private static func formattedDegrees(_ value: Double?) -> String {
        value.map { String(format: "%.1f°", $0) } ?? "n/a"
    }
}
