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

/// Shared location-identity rules for Home Screen widget cache payloads.
/// Saved-location IDs are authoritative; older and coordinate-only payloads
/// use a deliberately narrow fallback for the same physical location.
public enum WidgetLocationIdentity {
    public static let coordinateTolerance = 0.00001

    public static func matches(
        summarySavedLocationID: UUID?,
        selectedSavedLocationID: UUID?,
        summaryLatitude: Double,
        summaryLongitude: Double,
        selectedLatitude: Double,
        selectedLongitude: Double
    ) -> Bool {
        switch (summarySavedLocationID, selectedSavedLocationID) {
        case let (summaryID?, selectedID?):
            return summaryID == selectedID
        case (nil, nil):
            return abs(summaryLatitude - selectedLatitude) <= coordinateTolerance
                && abs(summaryLongitude - selectedLongitude) <= coordinateTolerance
        case (nil, _?), (_?, nil):
            return false
        }
    }
}

/// The compact, fully resolved payload used by the iOS Home Screen widget.
/// The extension only formats dates and chooses how much of this already-ranked
/// presentation fits in the selected widget family.
///
/// Phase 4A: `score` is the public headline (= observingQualityScore). Explicit dual
/// night/OQ fields enable migration without score ambiguity.
public struct WidgetNightSummary: Codable, Sendable, Hashable {
    public let generatedAt: Date
    public let locationName: String
    public let latitude: Double
    public let longitude: Double
    public let savedLocationID: UUID?
    public let timeZoneIdentifier: String?
    /// Public headline score (= observingQualityScore when v1).
    public let score: Int
    public let verdict: String
    public let earlyQuality: String
    public let lateQuality: String
    public let trend: NightQualityAssessment.Trend
    public let bestWindow: NightQualityAssessment.TimeWindow?
    public let primaryMessage: String
    public let factors: [NightQualityDisplayFactor]
    public let hasAstronomicalNight: Bool

    // MARK: - Observing quality (Phase 4A)

    public let payloadVersion: Int
    public let nightConditionsScore: Int
    public let observingQualityScore: Int
    public let brightnessAvailability: BrightnessAvailability
    public let modeledZenithBrightness: Double?
    public let brightnessDataset: LightPollutionDatasetIdentity?
    public let brightnessLookupLatitude: Double?
    public let brightnessLookupLongitude: Double?
    public let brightnessSavedLocationID: UUID?

    public init(
        generatedAt: Date,
        locationName: String,
        latitude: Double,
        longitude: Double,
        savedLocationID: UUID? = nil,
        timeZoneIdentifier: String?,
        score: Int,
        verdict: String,
        earlyQuality: String,
        lateQuality: String,
        trend: NightQualityAssessment.Trend,
        bestWindow: NightQualityAssessment.TimeWindow?,
        primaryMessage: String,
        factors: [NightQualityDisplayFactor],
        hasAstronomicalNight: Bool,
        payloadVersion: Int = 0,
        nightConditionsScore: Int? = nil,
        observingQualityScore: Int? = nil,
        brightnessAvailability: BrightnessAvailability = .unavailable,
        modeledZenithBrightness: Double? = nil,
        brightnessDataset: LightPollutionDatasetIdentity? = nil,
        brightnessLookupLatitude: Double? = nil,
        brightnessLookupLongitude: Double? = nil,
        brightnessSavedLocationID: UUID? = nil
    ) {
        self.generatedAt = generatedAt
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.savedLocationID = savedLocationID
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
        self.payloadVersion = payloadVersion
        self.nightConditionsScore = nightConditionsScore ?? score
        self.observingQualityScore = observingQualityScore ?? score
        self.brightnessAvailability = brightnessAvailability
        self.modeledZenithBrightness = modeledZenithBrightness
        self.brightnessDataset = brightnessDataset
        self.brightnessLookupLatitude = brightnessLookupLatitude
        self.brightnessLookupLongitude = brightnessLookupLongitude
        self.brightnessSavedLocationID = brightnessSavedLocationID
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, locationName, latitude, longitude, savedLocationID, timeZoneIdentifier
        case score, verdict, earlyQuality, lateQuality, trend, bestWindow
        case primaryMessage, factors, hasAstronomicalNight
        case payloadVersion, nightConditionsScore, observingQualityScore
        case brightnessAvailability, modeledZenithBrightness, brightnessDataset
        case brightnessLookupLatitude, brightnessLookupLongitude, brightnessSavedLocationID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        locationName = try values.decode(String.self, forKey: .locationName)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        savedLocationID = try values.decodeIfPresent(UUID.self, forKey: .savedLocationID)
        timeZoneIdentifier = try values.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)

        // Optional fields — zero is a valid score and must not be treated as missing.
        let legacyScore = try values.decodeIfPresent(Int.self, forKey: .score)
        let decodedNight = try values.decodeIfPresent(Int.self, forKey: .nightConditionsScore)
        let decodedOQ = try values.decodeIfPresent(Int.self, forKey: .observingQualityScore)
        let version = try values.decodeIfPresent(Int.self, forKey: .payloadVersion) ?? 0

        // Version 0 legacy priority: score → nightConditionsScore → observingQualityScore
        let legacyRecovered = legacyScore ?? decodedNight ?? decodedOQ
        // Night base for v1/future: prefer explicit night, then legacy score, then OQ
        let nightRecovered = decodedNight ?? legacyScore ?? decodedOQ

        let decodedVerdict = try values.decodeIfPresent(String.self, forKey: .verdict)
        earlyQuality = try values.decodeIfPresent(String.self, forKey: .earlyQuality)
            ?? decodedVerdict ?? "Unavailable"
        lateQuality = try values.decodeIfPresent(String.self, forKey: .lateQuality)
            ?? decodedVerdict ?? "Unavailable"
        trend = try values.decodeIfPresent(NightQualityAssessment.Trend.self, forKey: .trend) ?? .stable
        bestWindow = try values.decodeIfPresent(NightQualityAssessment.TimeWindow.self, forKey: .bestWindow)
        primaryMessage = try values.decodeIfPresent(String.self, forKey: .primaryMessage)
            ?? "Open Astro Conditions to update"
        factors = try values.decodeIfPresent([NightQualityDisplayFactor].self, forKey: .factors) ?? []
        hasAstronomicalNight = try values.decodeIfPresent(Bool.self, forKey: .hasAstronomicalNight) ?? true

        payloadVersion = version

        if version == 0 {
            guard let recovered = legacyRecovered else {
                throw DecodingError.dataCorruptedError(
                    forKey: .score,
                    in: values,
                    debugDescription: "No score fields present"
                )
            }
            nightConditionsScore = recovered
            observingQualityScore = recovered
            score = recovered
            // Prefer stored verdict; if missing, derive from recovered score band.
            verdict = decodedVerdict
                ?? CrossSurfaceHeadlineScorePresentation.verdict(for: recovered)
            brightnessAvailability = .unavailable
            modeledZenithBrightness = nil
            brightnessDataset = nil
            brightnessLookupLatitude = nil
            brightnessLookupLongitude = nil
            brightnessSavedLocationID = nil
            return
        }

        if version > CrossSurfaceObservingQualitySnapshot.currentPayloadVersion {
            // Unknown future OQ: disable enhancement; display exact recovered night.
            guard let recoveredNight = nightRecovered else {
                throw DecodingError.dataCorruptedError(
                    forKey: .nightConditionsScore,
                    in: values,
                    debugDescription: "No recoverable night score"
                )
            }
            nightConditionsScore = recoveredNight
            observingQualityScore = recoveredNight
            score = recoveredNight
            verdict = CrossSurfaceHeadlineScorePresentation.verdict(for: recoveredNight)
            brightnessAvailability = .unavailable
            modeledZenithBrightness = nil
            brightnessDataset = nil
            brightnessLookupLatitude = nil
            brightnessLookupLongitude = nil
            brightnessSavedLocationID = nil
            return
        }

        let availabilityRaw = try values.decodeIfPresent(String.self, forKey: .brightnessAvailability)
        var availability = BrightnessAvailability(rawValueOrUnknown: availabilityRaw)
        let brightness = try values.decodeIfPresent(Double.self, forKey: .modeledZenithBrightness)
        let dataset = try values.decodeIfPresent(LightPollutionDatasetIdentity.self, forKey: .brightnessDataset)
        let lat = try values.decodeIfPresent(Double.self, forKey: .brightnessLookupLatitude)
        let lon = try values.decodeIfPresent(Double.self, forKey: .brightnessLookupLongitude)
        let savedID = try values.decodeIfPresent(UUID.self, forKey: .brightnessSavedLocationID)

        if availability == .available {
            let structurallyValid = CrossSurfaceAvailableBrightnessMetadata.isStructurallyValid(
                brightness: brightness,
                dataset: dataset,
                lookupLatitude: lat,
                lookupLongitude: lon,
                brightnessSavedLocationID: savedID,
                summarySavedLocationID: savedLocationID,
                summaryLatitude: latitude,
                summaryLongitude: longitude,
                enforceSummaryAssociation: true
            )
            if !structurallyValid {
                availability = .unavailable
            }
        }

        guard let recoveredNight = nightRecovered else {
            throw DecodingError.dataCorruptedError(
                forKey: .nightConditionsScore,
                in: values,
                debugDescription: "No recoverable night score"
            )
        }
        nightConditionsScore = recoveredNight
        if availability == .available {
            brightnessAvailability = .available
            modeledZenithBrightness = brightness
            brightnessDataset = dataset
            brightnessLookupLatitude = lat
            brightnessLookupLongitude = lon
            brightnessSavedLocationID = savedID
            // Recompute with the canonical calculator rather than trusting a transported score.
            let oq = ObservingQualityCalculator.assess(
                nightConditionsScore: recoveredNight,
                modeledZenithSkyBrightness: brightness
            ).score
            observingQualityScore = oq
            score = oq
            // Headline verdict must match OQ category when enhancement is available.
            verdict = CrossSurfaceHeadlineScorePresentation.verdict(for: oq)
        } else {
            brightnessAvailability = .unavailable
            modeledZenithBrightness = nil
            brightnessDataset = nil
            brightnessLookupLatitude = nil
            brightnessLookupLongitude = nil
            brightnessSavedLocationID = nil
            observingQualityScore = recoveredNight
            score = recoveredNight
            verdict = CrossSurfaceHeadlineScorePresentation.verdict(for: recoveredNight)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(generatedAt, forKey: .generatedAt)
        try values.encode(locationName, forKey: .locationName)
        try values.encode(latitude, forKey: .latitude)
        try values.encode(longitude, forKey: .longitude)
        try values.encodeIfPresent(savedLocationID, forKey: .savedLocationID)
        try values.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try values.encode(observingQualityScore, forKey: .score)
        try values.encode(verdict, forKey: .verdict)
        try values.encode(earlyQuality, forKey: .earlyQuality)
        try values.encode(lateQuality, forKey: .lateQuality)
        try values.encode(trend, forKey: .trend)
        try values.encodeIfPresent(bestWindow, forKey: .bestWindow)
        try values.encode(primaryMessage, forKey: .primaryMessage)
        try values.encode(factors, forKey: .factors)
        try values.encode(hasAstronomicalNight, forKey: .hasAstronomicalNight)
        try values.encode(payloadVersion, forKey: .payloadVersion)
        try values.encode(nightConditionsScore, forKey: .nightConditionsScore)
        try values.encode(observingQualityScore, forKey: .observingQualityScore)
        try values.encode(brightnessAvailability.rawValue, forKey: .brightnessAvailability)
        try values.encodeIfPresent(modeledZenithBrightness, forKey: .modeledZenithBrightness)
        try values.encodeIfPresent(brightnessDataset, forKey: .brightnessDataset)
        try values.encodeIfPresent(brightnessLookupLatitude, forKey: .brightnessLookupLatitude)
        try values.encodeIfPresent(brightnessLookupLongitude, forKey: .brightnessLookupLongitude)
        try values.encodeIfPresent(brightnessSavedLocationID, forKey: .brightnessSavedLocationID)
    }

    /// Night-only base builder (no OQ enrichment). Prefer `WidgetNightSummaryPublisher.makeEnriched`
    /// for production App Group publication.
    public static func make(from conditions: ViewingConditions) -> WidgetNightSummary? {
        guard let base = WidgetNightSummaryPublisher.makeNightBase(from: conditions) else {
            return nil
        }
        return WidgetNightSummary(
            generatedAt: base.generatedAt,
            locationName: base.locationName,
            latitude: base.latitude,
            longitude: base.longitude,
            savedLocationID: base.savedLocationID,
            timeZoneIdentifier: base.timeZoneIdentifier,
            score: base.nightScore,
            verdict: base.verdict,
            earlyQuality: base.earlyQuality,
            lateQuality: base.lateQuality,
            trend: base.trend,
            bestWindow: base.bestWindow,
            primaryMessage: base.primaryMessage,
            factors: base.factors,
            hasAstronomicalNight: base.hasAstronomicalNight,
            payloadVersion: 0,
            nightConditionsScore: base.nightScore,
            observingQualityScore: base.nightScore,
            brightnessAvailability: .unavailable
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
        let age = referenceDate.timeIntervalSince(generatedAt)
        guard age >= 0 && age < maxAge else { return false }
        let timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: longitude)
        return LocationTimeZoneResolver.calendar(for: timeZone).isDate(generatedAt, inSameDayAs: referenceDate)
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
}
