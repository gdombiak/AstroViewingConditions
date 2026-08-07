import Foundation

/// Called on the MainActor after a still-current successful GPS resolution.
///
/// Implementations must stamp publication revision **synchronously** before any await.
@MainActor
public protocol CurrentLocationBrightnessPublishing: AnyObject {
    /// Accept resolved Current Location coordinates for brightness metadata.
    /// No-op when coordinates are not publishable (invalid geo or app placeholder `(0,0)`).
    func publishResolvedCurrentLocation(latitude: Double, longitude: Double)
}

/// Long-lived production publisher. Owns async provider lookup + coordinator enqueue.
/// Does **not** call `ensureLoaded` / start another atlas load.
@MainActor
public final class AppCurrentLocationBrightnessPublisher: CurrentLocationBrightnessPublishing {
    public static let shared = AppCurrentLocationBrightnessPublisher()

    typealias ProviderLookup = @Sendable () async -> (any LightPollutionProviding)?
    typealias EnqueueHandler = @Sendable (
        CurrentLocationBrightnessPublication,
        (any LightPollutionProviding)?
    ) async -> Void

    private let providerLookup: ProviderLookup
    private let enqueue: EnqueueHandler

    /// Production and test construction. Injectable seams are **internal** so unit tests
    /// (`@testable import SharedCode`) can verify gating without public test-only API.
    init(
        providerLookup: @escaping ProviderLookup = {
            LightPollutionProviderBootstrap.shared.currentProvider()
        },
        enqueue: @escaping EnqueueHandler = { publication, provider in
            CurrentLocationModeledBrightnessCoordinator.shared.enqueueSynchronize(
                publication: publication,
                provider: provider
            )
        }
    ) {
        self.providerLookup = providerLookup
        self.enqueue = enqueue
    }

    public func publishResolvedCurrentLocation(latitude: Double, longitude: Double) {
        // App-boundary gates only — do not change Phase 1 geo validity.
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: latitude,
            longitude: longitude
        ) else {
            return
        }
        // Unresolved selection placeholder used by DashboardLocationLoader.
        guard !(latitude == 0 && longitude == 0) else {
            return
        }

        // Synchronous revision stamp BEFORE any await / Task body.
        let publication = CurrentLocationBrightnessPublication.makeAuthoritative(
            anchor: CurrentLocationBrightnessAnchor(latitude: latitude, longitude: longitude)
        )

        let providerLookup = self.providerLookup
        let enqueue = self.enqueue
        Task {
            let provider = await providerLookup()
            await enqueue(publication, provider)
        }
    }
}
