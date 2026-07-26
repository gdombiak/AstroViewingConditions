import Foundation
import SharedCode

enum TonightTargetsWidgetPayloadBuilder {
    static let targetLimit = 3

    static func makeSummary(
        conditions: ViewingConditions,
        resolution: TargetRecommendationContextResolution,
        recommendations: [TargetRecommendation]
    ) -> WidgetTonightTargetsSummary {
        let targets = recommendations.prefix(targetLimit).map(makeTargetSummary)
        return WidgetTonightTargetsSummary(
            generatedAt: conditions.fetchedAt,
            locationName: conditions.location.name,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            savedLocationID: conditions.location.id,
            timeZoneIdentifier: resolution.timeZone.identifier,
            observingDate: resolution.observingDate,
            astronomicalNightStart: resolution.context.astronomicalNightStart,
            astronomicalNightEnd: resolution.context.astronomicalNightEnd,
            status: targets.isEmpty ? .noTargets : .available,
            targets: targets
        )
    }

    static func makeUnavailableSummary(
        generatedAt: Date,
        location: CachedLocation,
        timeZone: TimeZone,
        referenceDate: Date
    ) -> WidgetTonightTargetsSummary {
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        return WidgetTonightTargetsSummary(
            generatedAt: generatedAt,
            locationName: location.name,
            latitude: location.latitude,
            longitude: location.longitude,
            savedLocationID: location.id,
            timeZoneIdentifier: timeZone.identifier,
            observingDate: calendar.startOfDay(for: referenceDate),
            astronomicalNightStart: nil,
            astronomicalNightEnd: nil,
            status: .unavailable,
            targets: []
        )
    }

    static func positionLabel(direction: String?, altitude: Double?) -> String? {
        let resolvedDirection = direction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let directionText = resolvedDirection?.isEmpty == false ? resolvedDirection : nil
        let altitudeText = altitude.map { "\(Int(round($0)))°" }

        switch (directionText, altitudeText) {
        case let (direction?, altitude?):
            return "\(direction) · \(altitude)"
        case let (direction?, nil):
            return direction
        case let (nil, altitude?):
            return altitude
        case (nil, nil):
            return nil
        }
    }

    private static func makeTargetSummary(
        _ recommendation: TargetRecommendation
    ) -> WidgetTonightTargetSummary {
        let window = recommendation.visibilityWindow
        return WidgetTonightTargetSummary(
            targetID: recommendation.target.id,
            displayName: recommendation.target.name,
            categoryLabel: recommendation.target.displayTypeName,
            score: recommendation.score,
            scoreTone: scoreTone(for: recommendation.score),
            bestTime: window.bestTime,
            positionLabel: positionLabel(
                direction: window.direction,
                altitude: window.maxAltitude
            )
        )
    }

    private static func scoreTone(for score: Int) -> WidgetTargetScoreTone {
        switch TargetScoreColorProvider.category(for: score) {
        case .excellent:
            return .positive
        case .good:
            return .informational
        case .fair:
            return .caution
        case .poor:
            return .negative
        }
    }
}
