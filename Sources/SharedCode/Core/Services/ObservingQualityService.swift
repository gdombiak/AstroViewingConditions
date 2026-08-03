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
        let provider = lightPollutionProviderSnapshot()
        let brightness = provider?.modeledZenithSkyBrightness(
            latitude: latitude,
            longitude: longitude
        )
        return ObservingQualityCalculator.assess(
            nightConditionsScore: nightConditionsScore,
            modeledZenithSkyBrightness: brightness
        )
    }
}
