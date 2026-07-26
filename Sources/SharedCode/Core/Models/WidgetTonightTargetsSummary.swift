import Foundation

public enum WidgetTargetScoreTone: String, Codable, Sendable, Hashable {
    case positive
    case informational
    case caution
    case negative
}

public enum WidgetTonightTargetsStatus: String, Codable, Sendable, Hashable {
    case available
    case noTargets
    case unavailable
}

public struct WidgetTonightTargetSummary: Identifiable, Codable, Sendable, Hashable {
    public let targetID: String
    public let displayName: String
    public let categoryLabel: String
    public let score: Int
    public let scoreTone: WidgetTargetScoreTone
    public let bestTime: Date?
    public let positionLabel: String?

    public var id: String { targetID }

    public init(
        targetID: String,
        displayName: String,
        categoryLabel: String,
        score: Int,
        scoreTone: WidgetTargetScoreTone,
        bestTime: Date?,
        positionLabel: String?
    ) {
        self.targetID = targetID
        self.displayName = displayName
        self.categoryLabel = categoryLabel
        self.score = score
        self.scoreTone = scoreTone
        self.bestTime = bestTime
        self.positionLabel = positionLabel
    }
}

/// Compact, display-ready cache for the Tonight's Targets Home Screen widget.
/// All astronomy, ranking, scoring, status, and position conclusions are
/// resolved before this payload reaches the widget extension.
public struct WidgetTonightTargetsSummary: Codable, Sendable, Hashable {
    public static let maximumAge: TimeInterval = 3 * 3600

    public let generatedAt: Date
    public let locationName: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String?
    public let observingDate: Date
    public let astronomicalNightStart: Date?
    public let astronomicalNightEnd: Date?
    public let status: WidgetTonightTargetsStatus
    public let targets: [WidgetTonightTargetSummary]

    public init(
        generatedAt: Date,
        locationName: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String?,
        observingDate: Date,
        astronomicalNightStart: Date?,
        astronomicalNightEnd: Date?,
        status: WidgetTonightTargetsStatus,
        targets: [WidgetTonightTargetSummary]
    ) {
        self.generatedAt = generatedAt
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.observingDate = observingDate
        self.astronomicalNightStart = astronomicalNightStart
        self.astronomicalNightEnd = astronomicalNightEnd
        self.status = status
        self.targets = targets
    }

    public func isWithinMaximumAge(
        _ maximumAge: TimeInterval,
        relativeTo referenceDate: Date = Date()
    ) -> Bool {
        let age = referenceDate.timeIntervalSince(generatedAt)
        return age >= 0 && age <= maximumAge
    }

    public func locationMatches(
        latitude: Double,
        longitude: Double,
        tolerance: Double = 0.01
    ) -> Bool {
        abs(self.latitude - latitude) <= tolerance
            && abs(self.longitude - longitude) <= tolerance
    }

    public func matchesCurrentObservingNight(relativeTo referenceDate: Date = Date()) -> Bool {
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)

        if calendar.isDate(observingDate, inSameDayAs: referenceDate) {
            return true
        }

        guard let astronomicalNightStart, let astronomicalNightEnd else {
            return false
        }
        return referenceDate >= astronomicalNightStart && referenceDate <= astronomicalNightEnd
    }
}
