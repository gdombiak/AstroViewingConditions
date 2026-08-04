import Foundation

/// Structural checks for encoded "available" brightness metadata (decode-time only).
///
/// Does not re-run full Phase 1 sample/request association for arbitrary request coords;
/// validates fields required for a trustworthy available payload.
enum CrossSurfaceAvailableBrightnessMetadata: Sendable {
    /// Returns true when available-state metadata is complete and structurally consistent.
    static func isStructurallyValid(
        brightness: Double?,
        dataset: LightPollutionDatasetIdentity?,
        lookupLatitude: Double?,
        lookupLongitude: Double?,
        brightnessSavedLocationID: UUID?,
        summarySavedLocationID: UUID?,
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
