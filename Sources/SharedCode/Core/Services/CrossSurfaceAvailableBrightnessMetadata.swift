import Foundation

/// Structural checks for encoded "available" brightness metadata (decode-time only).
///
/// Validates fields required for a trustworthy available payload. Widget summaries also
/// enforce lookup-coordinate association with the summary location.
enum CrossSurfaceAvailableBrightnessMetadata: Sendable {
    /// Returns true when available-state metadata is complete and structurally consistent.
    static func isStructurallyValid(
        brightness: Double?,
        dataset: LightPollutionDatasetIdentity?,
        lookupLatitude: Double?,
        lookupLongitude: Double?,
        brightnessSavedLocationID: UUID?,
        summarySavedLocationID: UUID?,
        summaryLatitude: Double? = nil,
        summaryLongitude: Double? = nil,
        enforceSummaryAssociation: Bool
    ) -> Bool {
        guard let brightness,
              ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(brightness) else {
            return false
        }
        guard let dataset,
              LightPollutionDatasetIdentity.current.isCompatible(with: dataset) else {
            return false
        }
        guard let lat = lookupLatitude, let lon = lookupLongitude,
              ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
                latitude: lat,
                longitude: lon
              ) else {
            return false
        }
        if enforceSummaryAssociation {
            guard let summaryLatitude, let summaryLongitude,
                  ModeledZenithBrightnessValidity.coordinatesMatch(
                    sampleLatitude: lat,
                    sampleLongitude: lon,
                    requestLatitude: summaryLatitude,
                    requestLongitude: summaryLongitude
                  ) else {
                return false
            }
            // Saved summary requires matching brightness ID; coordinate-only summary requires nil.
            switch (summarySavedLocationID, brightnessSavedLocationID) {
            case let (summaryID?, brightnessID?):
                guard summaryID == brightnessID else { return false }
            case (nil, nil):
                break
            case (nil, _?), (_?, nil):
                return false
            }
        }
        return true
    }
}
