import Foundation

/// Provides modeled zenith sky brightness (mag/arcsec²) for a geographic coordinate.
///
/// Returns `nil` when the location is outside coverage, NoData, or data is unavailable.
/// Missing data must **not** be treated as pristine darkness.
public protocol LightPollutionProviding: Sendable {
    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double?
}
