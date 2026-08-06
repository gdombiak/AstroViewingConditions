import Foundation

/// Shared production path: night-conditions score + coordinates → `ObservingQualityAssessment`.
///
/// Looks up modeled zenith sky brightness via `LightPollutionProviding`, then applies
/// `ObservingQualityCalculator`. Missing/unavailable light-pollution data preserves the
/// night-conditions score exactly (`lightPollution == nil`).
public protocol ObservingQualityAssessing: Sendable {
    func assess(
        nightConditionsScore: Int,
        latitude: Double,
        longitude: Double
    ) -> ObservingQualityAssessment
}

/// Default injectable implementation. Provider may be nil (fallback) or swapped after async load.
public final class ObservingQualityService: ObservingQualityAssessing, @unchecked Sendable {
    private let lock = NSLock()
    private var lightPollutionProvider: (any LightPollutionProviding)?

    public init(lightPollutionProvider: (any LightPollutionProviding)? = nil) {
        self.lightPollutionProvider = lightPollutionProvider
    }

    /// Replace the light-pollution provider (e.g. after async bootstrap). Thread-safe.
    public func setLightPollutionProvider(_ provider: (any LightPollutionProviding)?) {
        lock.lock()
        lightPollutionProvider = provider
        lock.unlock()
    }

    public func lightPollutionProviderSnapshot() -> (any LightPollutionProviding)? {
        lock.lock()
        defer { lock.unlock() }
        return lightPollutionProvider
    }

    public func assess(
        nightConditionsScore: Int,
        latitude: Double,
        longitude: Double
    ) -> ObservingQualityAssessment {
        // Invalid coordinates must not call the provider or invent brightness.
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: latitude,
            longitude: longitude
        ) else {
            return ObservingQualityCalculator.assess(
                nightConditionsScore: nightConditionsScore,
                modeledZenithSkyBrightness: nil
            )
        }

        let provider = lightPollutionProviderSnapshot()
        let rawBrightness = provider?.modeledZenithSkyBrightness(
            latitude: latitude,
            longitude: longitude
        )

        // Nil / non-finite / out-of-range brightness → exact night-score fallback
        // (same contract as sample validity: never treat invalid as pristine zero-penalty).
        let brightness: Double?
        if let rawBrightness,
           ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(rawBrightness) {
            brightness = rawBrightness
        } else {
            brightness = nil
        }

        return ObservingQualityCalculator.assess(
            nightConditionsScore: nightConditionsScore,
            modeledZenithSkyBrightness: brightness
        )
    }
}
