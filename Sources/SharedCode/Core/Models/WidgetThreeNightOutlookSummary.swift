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
    /// Public headline score (= observingQualityScore when set).
    public let score: Int?
    public let verdict: String
    public let scoreTone: WidgetTargetScoreTone?
    public let astronomicalNightStart: Date?
    public let astronomicalNightEnd: Date?
    public let bestWindow: NightQualityAssessment.TimeWindow?
    public let statusText: String
    public let status: WidgetThreeNightOutlookNightStatus
    public let isBestNight: Bool
    /// Phase 4A dual scores (nil when night unavailable).
    public let nightConditionsScore: Int?
    public let observingQualityScore: Int?

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
        isBestNight: Bool,
        nightConditionsScore: Int? = nil,
        observingQualityScore: Int? = nil
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
        self.nightConditionsScore = nightConditionsScore ?? score
        self.observingQualityScore = observingQualityScore ?? score
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayLabel, observingDate, score, verdict, scoreTone
        case astronomicalNightStart, astronomicalNightEnd, bestWindow
        case statusText, status, isBestNight
        case nightConditionsScore, observingQualityScore
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayLabel = try c.decode(String.self, forKey: .displayLabel)
        observingDate = try c.decode(Date.self, forKey: .observingDate)
        let legacyScore = try c.decodeIfPresent(Int.self, forKey: .score)
        score = legacyScore
        verdict = try c.decode(String.self, forKey: .verdict)
        scoreTone = try c.decodeIfPresent(WidgetTargetScoreTone.self, forKey: .scoreTone)
        astronomicalNightStart = try c.decodeIfPresent(Date.self, forKey: .astronomicalNightStart)
        astronomicalNightEnd = try c.decodeIfPresent(Date.self, forKey: .astronomicalNightEnd)
        bestWindow = try c.decodeIfPresent(NightQualityAssessment.TimeWindow.self, forKey: .bestWindow)
        statusText = try c.decode(String.self, forKey: .statusText)
        status = try c.decode(WidgetThreeNightOutlookNightStatus.self, forKey: .status)
        isBestNight = try c.decode(Bool.self, forKey: .isBestNight)
        nightConditionsScore = try c.decodeIfPresent(Int.self, forKey: .nightConditionsScore) ?? legacyScore
        observingQualityScore = try c.decodeIfPresent(Int.self, forKey: .observingQualityScore) ?? legacyScore
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayLabel, forKey: .displayLabel)
        try c.encode(observingDate, forKey: .observingDate)
        try c.encodeIfPresent(observingQualityScore ?? score, forKey: .score)
        try c.encode(verdict, forKey: .verdict)
        try c.encodeIfPresent(scoreTone, forKey: .scoreTone)
        try c.encodeIfPresent(astronomicalNightStart, forKey: .astronomicalNightStart)
        try c.encodeIfPresent(astronomicalNightEnd, forKey: .astronomicalNightEnd)
        try c.encodeIfPresent(bestWindow, forKey: .bestWindow)
        try c.encode(statusText, forKey: .statusText)
        try c.encode(status, forKey: .status)
        try c.encode(isBestNight, forKey: .isBestNight)
        try c.encodeIfPresent(nightConditionsScore, forKey: .nightConditionsScore)
        try c.encodeIfPresent(observingQualityScore, forKey: .observingQualityScore)
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
        return age >= 0 && age < maximumAge
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
