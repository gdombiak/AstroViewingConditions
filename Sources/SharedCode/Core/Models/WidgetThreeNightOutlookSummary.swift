import Foundation

public enum WidgetThreeNightOutlookStatus: String, Codable, Sendable, Hashable {
    case available
    case unavailable
}

public enum WidgetThreeNightOutlookNightStatus: String, Codable, Sendable, Hashable {
    case available
    case noAstronomicalNight
    case unavailable
}

public struct WidgetThreeNightOutlookNight: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let displayLabel: String
    public let observingDate: Date
    public let score: Int?
    public let verdict: String
    public let scoreTone: WidgetTargetScoreTone?
    public let astronomicalNightStart: Date?
    public let astronomicalNightEnd: Date?
    public let bestWindow: NightQualityAssessment.TimeWindow?
    public let statusText: String
    public let status: WidgetThreeNightOutlookNightStatus
    public let isBestNight: Bool

    public init(
        id: String,
        displayLabel: String,
        observingDate: Date,
        score: Int?,
        verdict: String,
        scoreTone: WidgetTargetScoreTone?,
        astronomicalNightStart: Date?,
        astronomicalNightEnd: Date?,
        bestWindow: NightQualityAssessment.TimeWindow?,
        statusText: String,
        status: WidgetThreeNightOutlookNightStatus,
        isBestNight: Bool
    ) {
        self.id = id
        self.displayLabel = displayLabel
        self.observingDate = observingDate
        self.score = score
        self.verdict = verdict
        self.scoreTone = scoreTone
        self.astronomicalNightStart = astronomicalNightStart
        self.astronomicalNightEnd = astronomicalNightEnd
        self.bestWindow = bestWindow
        self.statusText = statusText
        self.status = status
        self.isBestNight = isBestNight
    }
}

/// Display-ready, app-resolved cache for the Three-Night Outlook widget.
public struct WidgetThreeNightOutlookSummary: Codable, Sendable, Hashable {
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
    public let status: WidgetThreeNightOutlookStatus
    public let nights: [WidgetThreeNightOutlookNight]

    public init(
        generatedAt: Date,
        locationName: String,
        latitude: Double,
        longitude: Double,
        savedLocationID: UUID? = nil,
        timeZoneIdentifier: String?,
        status: WidgetThreeNightOutlookStatus,
        nights: [WidgetThreeNightOutlookNight]
    ) {
        self.generatedAt = generatedAt
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.savedLocationID = savedLocationID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.status = status
        self.nights = nights
    }

    public func isWithinMaximumAge(_ maximumAge: TimeInterval, relativeTo date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince(generatedAt)
        return age >= 0 && age <= maximumAge
    }

    public var isDataBearing: Bool {
        status == .available && nights.contains {
            $0.status == .available && $0.score != nil
        }
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

    public func hasCorrectlyOrderedNights() -> Bool {
        guard nights.count == 3,
              nights.map(\.displayLabel) == ["Tonight", "Tomorrow", "Day After"] else { return false }
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        return zip(nights, nights.dropFirst()).allSatisfy {
            calendar.dateComponents([.day], from: $0.observingDate, to: $1.observingDate).day == 1
        }
    }

    public func matchesCurrentObservingNight(relativeTo date: Date = Date()) -> Bool {
        guard let first = nights.first else { return false }
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        if calendar.isDate(first.observingDate, inSameDayAs: date) { return true }
        guard let start = first.astronomicalNightStart,
              let end = first.astronomicalNightEnd else { return false }
        return date >= start && date <= end
    }
}
