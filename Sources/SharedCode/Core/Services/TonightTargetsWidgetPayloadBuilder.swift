import Foundation

public enum TonightTargetsWidgetPublicationDecision {
    case publish(TargetRecommendationContextResolution)
    case preserveExisting
    case unavailable
}

/// Selects the observing night that widget publication should represent.
public enum TonightTargetsWidgetContextResolver {
    public static func publicationDecision(
        conditions: ViewingConditions,
        existingSummary: WidgetTonightTargetsSummary?,
        referenceDate: Date,
        timeZone: TimeZone?
    ) -> TonightTargetsWidgetPublicationDecision {
        let activeResolution = ActiveObservingNightResolver.resolve(
            conditions: conditions, referenceDate: referenceDate, timeZone: timeZone
        )
        if case let .resolved(resolution) = activeResolution { return .publish(resolution) }
        guard case let .requiresActivePreviousPayload(resolvedTimeZone) = activeResolution else {
            return .unavailable
        }
        if let existingSummary,
           isValidActivePreviousNightPayload(
            existingSummary, conditions: conditions, referenceDate: referenceDate, timeZone: resolvedTimeZone
           ) { return .preserveExisting }
        return .unavailable
    }

    private static func isValidActivePreviousNightPayload(
        _ summary: WidgetTonightTargetsSummary,
        conditions: ViewingConditions,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> Bool {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        guard !calendar.isDate(summary.observingDate, inSameDayAs: referenceDate),
              summary.locationMatches(conditions.location),
              summary.isWithinMaximumAge(WidgetTonightTargetsSummary.maximumAge, relativeTo: referenceDate),
              let nightStart = summary.astronomicalNightStart,
              let nightEnd = summary.astronomicalNightEnd,
              referenceDate >= nightStart, referenceDate <= nightEnd else { return false }
        switch summary.status {
        case .available: return !summary.targets.isEmpty
        case .noTargets: return true
        case .unavailable: return false
        }
    }
}

public enum TonightTargetsWidgetPayloadBuilder {
    public static let targetLimit = 3

    public static func makeSummary(
        conditions: ViewingConditions,
        resolution: TargetRecommendationContextResolution,
        recommendations: [TargetRecommendation]
    ) -> WidgetTonightTargetsSummary {
        let targets = recommendations.prefix(targetLimit).map(makeTargetSummary)
        return WidgetTonightTargetsSummary(
            generatedAt: conditions.fetchedAt, locationName: conditions.location.name,
            latitude: conditions.location.latitude, longitude: conditions.location.longitude,
            savedLocationID: conditions.location.id, timeZoneIdentifier: resolution.timeZone.identifier,
            observingDate: resolution.observingDate,
            astronomicalNightStart: resolution.context.astronomicalNightStart,
            astronomicalNightEnd: resolution.context.astronomicalNightEnd,
            status: targets.isEmpty ? .noTargets : .available, targets: targets
        )
    }

    public static func makeUnavailableSummary(
        generatedAt: Date, location: CachedLocation, timeZone: TimeZone, referenceDate: Date
    ) -> WidgetTonightTargetsSummary {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        return WidgetTonightTargetsSummary(
            generatedAt: generatedAt, locationName: location.name, latitude: location.latitude,
            longitude: location.longitude, savedLocationID: location.id,
            timeZoneIdentifier: timeZone.identifier, observingDate: calendar.startOfDay(for: referenceDate),
            astronomicalNightStart: nil, astronomicalNightEnd: nil, status: .unavailable, targets: []
        )
    }

    public static func positionLabel(direction: String?, altitude: Double?) -> String? {
        let directionText = direction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDirection = directionText?.isEmpty == false ? directionText : nil
        let altitudeText = altitude.map { "\(Int(round($0)))°" }
        switch (resolvedDirection, altitudeText) {
        case let (direction?, altitude?): return "\(direction) · \(altitude)"
        case let (direction?, nil): return direction
        case let (nil, altitude?): return altitude
        case (nil, nil): return nil
        }
    }

    private static func makeTargetSummary(_ recommendation: TargetRecommendation) -> WidgetTonightTargetSummary {
        let window = recommendation.visibilityWindow
        return WidgetTonightTargetSummary(
            targetID: recommendation.target.id, displayName: recommendation.target.name,
            categoryLabel: recommendation.target.displayTypeName, score: recommendation.score,
            scoreTone: scoreTone(for: recommendation.score), bestTime: window.bestTime,
            positionLabel: positionLabel(direction: window.direction, altitude: window.maxAltitude)
        )
    }

    private static func scoreTone(for score: Int) -> WidgetTargetScoreTone {
        switch TargetScoreCategory.resolve(score) {
        case .excellent: .positive
        case .good: .informational
        case .fair: .caution
        case .poor: .negative
        }
    }
}

/// Keeps recommendation execution in SharedCode so the extension invokes the
/// same established recommendation pipeline without carrying scoring logic.
public enum TonightTargetsWidgetRefreshPipeline {
    public static func makeSummary(
        conditions: ViewingConditions,
        resolution: TargetRecommendationContextResolution
    ) -> WidgetTonightTargetsSummary {
        let recommendations = DefaultTargetRecommendationService().recommendations(
            for: resolution.context,
            limit: 100
        )
        return TonightTargetsWidgetPayloadBuilder.makeSummary(
            conditions: conditions,
            resolution: resolution,
            recommendations: recommendations
        )
    }
}
