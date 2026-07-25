import Foundation

public struct NightQualityDisplayFactor: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case clouds
        case seeing
        case transparency
    }

    public enum Tone: String, Codable, Sendable, Hashable {
        case favorable
        case neutral
        case limiting
    }

    public let kind: Kind
    public let label: String
    public let value: String
    public let tone: Tone

    public init(kind: Kind, label: String, value: String, tone: Tone) {
        self.kind = kind
        self.label = label
        self.value = value
        self.tone = tone
    }
}

/// The compact, fully resolved payload used by the iOS Home Screen widget.
/// The extension only formats dates and chooses how much of this already-ranked
/// presentation fits in the selected widget family.
public struct WidgetNightSummary: Codable, Sendable, Hashable {
    public let generatedAt: Date
    public let locationName: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String?
    public let score: Int
    public let verdict: String
    public let earlyQuality: String
    public let lateQuality: String
    public let trend: NightQualityAssessment.Trend
    public let bestWindow: NightQualityAssessment.TimeWindow?
    public let primaryMessage: String
    public let factors: [NightQualityDisplayFactor]
    public let hasAstronomicalNight: Bool

    public init(
        generatedAt: Date,
        locationName: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String?,
        score: Int,
        verdict: String,
        earlyQuality: String,
        lateQuality: String,
        trend: NightQualityAssessment.Trend,
        bestWindow: NightQualityAssessment.TimeWindow?,
        primaryMessage: String,
        factors: [NightQualityDisplayFactor],
        hasAstronomicalNight: Bool
    ) {
        self.generatedAt = generatedAt
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.score = score
        self.verdict = verdict
        self.earlyQuality = earlyQuality
        self.lateQuality = lateQuality
        self.trend = trend
        self.bestWindow = bestWindow
        self.primaryMessage = primaryMessage
        self.factors = factors
        self.hasAstronomicalNight = hasAstronomicalNight
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, locationName, latitude, longitude, timeZoneIdentifier
        case score, verdict, earlyQuality, lateQuality, trend, bestWindow
        case primaryMessage, factors, hasAstronomicalNight
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        locationName = try values.decode(String.self, forKey: .locationName)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        timeZoneIdentifier = try values.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        score = try values.decodeIfPresent(Int.self, forKey: .score) ?? 0
        verdict = try values.decodeIfPresent(String.self, forKey: .verdict) ?? "Unavailable"
        earlyQuality = try values.decodeIfPresent(String.self, forKey: .earlyQuality) ?? verdict
        lateQuality = try values.decodeIfPresent(String.self, forKey: .lateQuality) ?? verdict
        trend = try values.decodeIfPresent(NightQualityAssessment.Trend.self, forKey: .trend) ?? .stable
        bestWindow = try values.decodeIfPresent(NightQualityAssessment.TimeWindow.self, forKey: .bestWindow)

        // Phase 1 payloads did not contain resolved conclusions. Keep their
        // score and timing, but avoid fabricating factors until the app refreshes.
        primaryMessage = try values.decodeIfPresent(String.self, forKey: .primaryMessage)
            ?? "Open Astro Conditions to update"
        factors = try values.decodeIfPresent([NightQualityDisplayFactor].self, forKey: .factors) ?? []
        hasAstronomicalNight = try values.decodeIfPresent(Bool.self, forKey: .hasAstronomicalNight) ?? true
    }

    public static func make(from conditions: ViewingConditions) -> WidgetNightSummary? {
        guard let assessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return nil
        }

        let presentation = NightQualityPresentation(assessment: assessment)
        let firstHalf = assessment.firstHalfScore.map(NightQualityAssessment.Rating.from)
        let secondHalf = assessment.secondHalfScore.map(NightQualityAssessment.Rating.from)

        return WidgetNightSummary(
            generatedAt: conditions.fetchedAt,
            locationName: conditions.location.name,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            timeZoneIdentifier: conditions.timeZoneIdentifier,
            score: assessment.calculatedScore,
            verdict: assessment.rating.shortLabel,
            earlyQuality: (firstHalf ?? assessment.rating).shortLabel,
            lateQuality: (secondHalf ?? assessment.rating).shortLabel,
            trend: assessment.trend,
            bestWindow: assessment.bestWindow,
            primaryMessage: presentation.primaryMessage,
            factors: presentation.factors,
            hasAstronomicalNight: !assessment.hourlyRatings.isEmpty
        )
    }

    /// Decodes both the compact Phase 1 cache and the full cache used by older
    /// installed widgets. The latter is resolved through shared analysis only.
    public static func decodeCachedPayload(_ data: Data) -> WidgetNightSummary? {
        if let summary = try? JSONDecoder().decode(WidgetNightSummary.self, from: data) {
            return summary
        }
        guard let legacyConditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) else {
            return nil
        }
        return make(from: legacyConditions)
    }

    public func isFreshForLocalDay(within maxAge: TimeInterval, relativeTo referenceDate: Date = Date()) -> Bool {
        guard referenceDate.timeIntervalSince(generatedAt) <= maxAge else { return false }
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: longitude)
        return LocationTimeZoneResolver.calendar(for: timeZone).isDate(generatedAt, inSameDayAs: referenceDate)
    }

    public func locationMatches(latitude: Double, longitude: Double, tolerance: Double = 0.01) -> Bool {
        abs(self.latitude - latitude) <= tolerance && abs(self.longitude - longitude) <= tolerance
    }
}
