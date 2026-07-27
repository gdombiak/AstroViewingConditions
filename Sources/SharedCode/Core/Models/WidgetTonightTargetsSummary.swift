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
#if os(watchOS)
    public static let maximumAge: TimeInterval = 3600
#else
    public static let maximumAge: TimeInterval = SharedConditionsRepository.maximumAge
#endif

    public let generatedAt: Date
    public let locationName: String
    public let latitude: Double
    public let longitude: Double
    public let savedLocationID: UUID?
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
        savedLocationID: UUID? = nil,
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
        self.savedLocationID = savedLocationID
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

    public func locationMatches(_ selectedLocation: SelectedLocation) -> Bool {
        WidgetLocationIdentity.matches(
            summarySavedLocationID: savedLocationID,
            selectedSavedLocationID: selectedLocation.source == .saved ? selectedLocation.id : nil,
            summaryLatitude: latitude,
            summaryLongitude: longitude,
            selectedLatitude: selectedLocation.latitude,
            selectedLongitude: selectedLocation.longitude
        )
    }

    public func locationMatches(_ location: CachedLocation) -> Bool {
        WidgetLocationIdentity.matches(
            summarySavedLocationID: savedLocationID,
            selectedSavedLocationID: location.id,
            summaryLatitude: latitude,
            summaryLongitude: longitude,
            selectedLatitude: location.latitude,
            selectedLongitude: location.longitude
        )
    }

    public func locationMatches(latitude: Double, longitude: Double) -> Bool {
        WidgetLocationIdentity.matches(
            summarySavedLocationID: savedLocationID,
            selectedSavedLocationID: nil,
            summaryLatitude: self.latitude,
            summaryLongitude: self.longitude,
            selectedLatitude: latitude,
            selectedLongitude: longitude
        )
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
