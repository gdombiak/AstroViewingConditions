import Foundation

/// Whether modeled zenith brightness was used for observing quality.
public enum BrightnessAvailability: String, Sendable, Equatable, Hashable {
    case available
    case unavailable

    /// Custom decode: unknown future raw values → unavailable (never fail parent payload).
    public init(rawValueOrUnknown raw: String?) {
        guard let raw else {
            self = .unavailable
            return
        }
        self = BrightnessAvailability(rawValue: raw) ?? .unavailable
    }
}

/// Versioned cross-surface observing-quality result (widget / future watch).
///
/// Custom Codable — do not rely on synthesized migration behavior.
public struct CrossSurfaceObservingQualitySnapshot: Codable, Sendable, Equatable, Hashable {
    public static let currentPayloadVersion = 1

    public var payloadVersion: Int
    public var nightConditionsScore: Int
    public var observingQualityScore: Int
    public var brightnessAvailability: BrightnessAvailability
    public var modeledZenithBrightness: Double?
    public var brightnessDataset: LightPollutionDatasetIdentity?
    public var brightnessLookupLatitude: Double?
    public var brightnessLookupLongitude: Double?
    public var brightnessSavedLocationID: UUID?
    public var assessedAt: Date

    public init(
        payloadVersion: Int = currentPayloadVersion,
        nightConditionsScore: Int,
        observingQualityScore: Int,
        brightnessAvailability: BrightnessAvailability,
        modeledZenithBrightness: Double? = nil,
        brightnessDataset: LightPollutionDatasetIdentity? = nil,
        brightnessLookupLatitude: Double? = nil,
        brightnessLookupLongitude: Double? = nil,
        brightnessSavedLocationID: UUID? = nil,
        assessedAt: Date = Date()
    ) {
        self.payloadVersion = payloadVersion
        self.nightConditionsScore = nightConditionsScore
        self.observingQualityScore = observingQualityScore
        self.brightnessAvailability = brightnessAvailability
        self.modeledZenithBrightness = modeledZenithBrightness
        self.brightnessDataset = brightnessDataset
        self.brightnessLookupLatitude = brightnessLookupLatitude
        self.brightnessLookupLongitude = brightnessLookupLongitude
        self.brightnessSavedLocationID = brightnessSavedLocationID
        self.assessedAt = assessedAt
    }

    /// Night-only fallback snapshot (no brightness enhancement).
    public static func nightOnly(
        nightConditionsScore: Int,
        assessedAt: Date = Date(),
        payloadVersion: Int = 0
    ) -> CrossSurfaceObservingQualitySnapshot {
        CrossSurfaceObservingQualitySnapshot(
            payloadVersion: payloadVersion,
            nightConditionsScore: nightConditionsScore,
            observingQualityScore: nightConditionsScore,
            brightnessAvailability: .unavailable,
            assessedAt: assessedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case payloadVersion
        case nightConditionsScore
        case observingQualityScore
        case brightnessAvailability
        case modeledZenithBrightness
        case brightnessDataset
        case brightnessLookupLatitude
        case brightnessLookupLongitude
        case brightnessSavedLocationID
        case assessedAt
        case score // legacy alias used when embedded without dual fields
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Optional fields — zero is a valid score (never use `!= 0` as a presence sentinel).
        let legacyScore = try c.decodeIfPresent(Int.self, forKey: .score)
        let version = try c.decodeIfPresent(Int.self, forKey: .payloadVersion) ?? 0
        payloadVersion = version

        let decodedNight = try c.decodeIfPresent(Int.self, forKey: .nightConditionsScore)
        let decodedOQ = try c.decodeIfPresent(Int.self, forKey: .observingQualityScore)

        // Version 0 legacy priority: score → nightConditionsScore → observingQualityScore
        let legacyRecovered = legacyScore ?? decodedNight ?? decodedOQ
        // Night base for v1/future: nightConditionsScore → score → observingQualityScore
        let nightRecovered = decodedNight ?? legacyScore ?? decodedOQ

        if version == 0 {
            guard let recovered = legacyRecovered else {
                throw DecodingError.dataCorruptedError(
                    forKey: .nightConditionsScore,
                    in: c,
                    debugDescription: "No score fields present"
                )
            }
            nightConditionsScore = recovered
            observingQualityScore = recovered
            brightnessAvailability = .unavailable
            modeledZenithBrightness = nil
            brightnessDataset = nil
            brightnessLookupLatitude = nil
            brightnessLookupLongitude = nil
            brightnessSavedLocationID = nil
            assessedAt = try c.decodeIfPresent(Date.self, forKey: .assessedAt) ?? Date.distantPast
            return
        }

        guard let night = nightRecovered else {
            throw DecodingError.dataCorruptedError(
                forKey: .nightConditionsScore,
                in: c,
                debugDescription: "No recoverable night score"
            )
        }
        nightConditionsScore = night

        if version > Self.currentPayloadVersion {
            // Unknown future: enhancement unavailable; all canonical scores = night.
            observingQualityScore = night
            brightnessAvailability = .unavailable
            modeledZenithBrightness = nil
            brightnessDataset = nil
            brightnessLookupLatitude = nil
            brightnessLookupLongitude = nil
            brightnessSavedLocationID = nil
            assessedAt = try c.decodeIfPresent(Date.self, forKey: .assessedAt) ?? Date()
            return
        }

        let availabilityRaw = try c.decodeIfPresent(String.self, forKey: .brightnessAvailability)
        var availability = BrightnessAvailability(rawValueOrUnknown: availabilityRaw)

        let brightness = try c.decodeIfPresent(Double.self, forKey: .modeledZenithBrightness)
        let dataset = try c.decodeIfPresent(LightPollutionDatasetIdentity.self, forKey: .brightnessDataset)
        let lat = try c.decodeIfPresent(Double.self, forKey: .brightnessLookupLatitude)
        let lon = try c.decodeIfPresent(Double.self, forKey: .brightnessLookupLongitude)
        let savedID = try c.decodeIfPresent(UUID.self, forKey: .brightnessSavedLocationID)

        if availability == .available {
            let structurallyValid = CrossSurfaceAvailableBrightnessMetadata.isStructurallyValid(
                brightness: brightness,
                dataset: dataset,
                lookupLatitude: lat,
                lookupLongitude: lon,
                brightnessSavedLocationID: savedID,
                summarySavedLocationID: nil,
                enforceSummaryAssociation: false
            )
            if !structurallyValid {
                availability = .unavailable
            }
        }

        brightnessAvailability = availability
        if availability == .available {
            modeledZenithBrightness = brightness
            brightnessDataset = dataset
            brightnessLookupLatitude = lat
            brightnessLookupLongitude = lon
            brightnessSavedLocationID = savedID
            // Do not trust encoded OQ after structural failure (already forced unavailable above).
            observingQualityScore = decodedOQ ?? night
        } else {
            modeledZenithBrightness = nil
            brightnessDataset = nil
            brightnessLookupLatitude = nil
            brightnessLookupLongitude = nil
            brightnessSavedLocationID = nil
            observingQualityScore = night
        }

        assessedAt = try c.decodeIfPresent(Date.self, forKey: .assessedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(payloadVersion, forKey: .payloadVersion)
        try c.encode(nightConditionsScore, forKey: .nightConditionsScore)
        try c.encode(observingQualityScore, forKey: .observingQualityScore)
        try c.encode(brightnessAvailability.rawValue, forKey: .brightnessAvailability)
        try c.encodeIfPresent(modeledZenithBrightness, forKey: .modeledZenithBrightness)
        try c.encodeIfPresent(brightnessDataset, forKey: .brightnessDataset)
        try c.encodeIfPresent(brightnessLookupLatitude, forKey: .brightnessLookupLatitude)
        try c.encodeIfPresent(brightnessLookupLongitude, forKey: .brightnessLookupLongitude)
        try c.encodeIfPresent(brightnessSavedLocationID, forKey: .brightnessSavedLocationID)
        try c.encode(assessedAt, forKey: .assessedAt)
        // Legacy headline alias
        try c.encode(observingQualityScore, forKey: .score)
    }
}
