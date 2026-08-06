import Foundation

/// Process-level readiness of light-pollution lookup for observing-quality scoring.
///
/// Distinct from night-conditions loading: weather may be ready while LPATLAS1 is still validating.
public enum LightPollutionReadiness: Sendable, Equatable {
    /// Bootstrap has not finished; do not present a finalized observing-quality headline yet.
    case loading
    /// Provider available for coordinate lookup.
    case ready
    /// Load failed or resource missing; scores fall back exactly to night conditions.
    case unavailable
}

/// Main-actor environment for UI/composition: readiness + assess, without feature views loading LPATLAS1.
@MainActor
public protocol ObservingQualityEnvironment: AnyObject {
    var lightPollutionReadiness: LightPollutionReadiness { get }

    func assess(
        nightConditionsScore: Int,
        latitude: Double,
        longitude: Double
    ) -> ObservingQualityAssessment
}

/// Immutable fallback environment: readiness is always `.unavailable`.
///
/// Assessments preserve the night-conditions score exactly (`lightPollution == nil`).
/// Use this as the safe default when no process-owned session has been injected—
/// never default to an unbootstrapped `.loading` session that would hang pending forever.
@MainActor
public final class UnavailableObservingQualityEnvironment: ObservingQualityEnvironment {
    public static let shared = UnavailableObservingQualityEnvironment()

    public var lightPollutionReadiness: LightPollutionReadiness { .unavailable }

    public init() {}

    public func assess(
        nightConditionsScore: Int,
        latitude: Double,
        longitude: Double
    ) -> ObservingQualityAssessment {
        ObservingQualityCalculator.assess(
            nightConditionsScore: nightConditionsScore,
            modeledZenithSkyBrightness: nil
        )
    }
}

/// Main-app (and test) composition for observing quality: one service + readiness.
///
/// Bootstrap is started from the process composition root (not from SwiftUI feature views).
/// Each process that needs local LPATLAS1 lookup needs its own session/bootstrap.
@MainActor
public final class ObservingQualitySession: ObservingQualityEnvironment {
    private let service: ObservingQualityService
    public private(set) var lightPollutionReadiness: LightPollutionReadiness

    public init(
        service: ObservingQualityService = ObservingQualityService(),
        initialReadiness: LightPollutionReadiness = .loading
    ) {
        self.service = service
        self.lightPollutionReadiness = initialReadiness
    }

    public func assess(
        nightConditionsScore: Int,
        latitude: Double,
        longitude: Double
    ) -> ObservingQualityAssessment {
        service.assess(
            nightConditionsScore: nightConditionsScore,
            latitude: latitude,
            longitude: longitude
        )
    }

    /// Process composition: load bundled LPATLAS1 once, then mark ready/unavailable.
    public func bootstrap(preferredBundles: [Bundle] = [Bundle.main]) async {
        lightPollutionReadiness = .loading
        let provider = await LightPollutionProviderBootstrap.shared.ensureLoaded(
            preferredBundles: preferredBundles
        )
        service.setLightPollutionProvider(provider)
        lightPollutionReadiness = provider == nil ? .unavailable : .ready
    }

    /// Test/support: install a provider and readiness without touching the bundle.
    public func installForTesting(
        provider: (any LightPollutionProviding)?,
        readiness: LightPollutionReadiness
    ) {
        service.setLightPollutionProvider(provider)
        lightPollutionReadiness = readiness
    }

    /// Snapshot a **Sendable** assessor for background Best Nearby search.
    ///
    /// Call after bootstrap when possible. Uses the process-owned provider snapshot;
    /// does not load the atlas from SharedCode Best Spot code.
    public func makeSendableAssessor() -> ObservingQualityService {
        ObservingQualityService(
            lightPollutionProvider: service.lightPollutionProviderSnapshot()
        )
    }

    /// Ensure bootstrap has completed, then return a Sendable assessor for one search.
    public func prepareSendableAssessorForSearch(
        preferredBundles: [Bundle] = [Bundle.main]
    ) async -> ObservingQualityService {
        if lightPollutionReadiness == .loading {
            await bootstrap(preferredBundles: preferredBundles)
        }
        return makeSendableAssessor()
    }
}
