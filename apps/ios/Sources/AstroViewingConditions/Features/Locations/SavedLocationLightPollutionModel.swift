import Foundation
import SharedCode
import Observation

/// Resolves modeled light-pollution display state for saved locations.
///
/// Uses process-owned `LightPollutionProviderBootstrap` via an injectable loader
/// (no second atlas stack). Keys results by location id **and** coordinates so
/// renames reuse values but coordinate edits cannot keep a stale reading.
@MainActor
@Observable
final class SavedLocationLightPollutionModel {
    typealias ProviderLoader = @Sendable () async -> (any LightPollutionProviding)?

    struct LocationKey: Hashable, Sendable {
        let id: UUID
        let latitude: Double
        let longitude: Double

        init(id: UUID, latitude: Double, longitude: Double) {
            self.id = id
            self.latitude = latitude
            self.longitude = longitude
        }

        init(location: SavedLocation) {
            self.id = location.id
            self.latitude = location.latitude
            self.longitude = location.longitude
        }
    }

    private(set) var states: [LocationKey: LightPollutionRowDisplayState] = [:]
    private var refreshGeneration: UInt64 = 0
    private let providerLoader: ProviderLoader

    init(
        providerLoader: @escaping ProviderLoader = {
            await LightPollutionProviderBootstrap.shared.ensureLoaded(
                preferredBundles: [Bundle.main]
            )
        }
    ) {
        self.providerLoader = providerLoader
    }

    func state(for location: SavedLocation) -> LightPollutionRowDisplayState {
        states[LocationKey(location: location)] ?? .unresolved
    }

    func state(for key: LocationKey) -> LightPollutionRowDisplayState {
        states[key] ?? .unresolved
    }

    /// Resolve all listed locations. Superseded calls ignore their results.
    func refresh(locations: [SavedLocation]) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let keys = locations.map(LocationKey.init(location:))

        // Await loader after generation stamp so a slower earlier refresh can be discarded.
        let provider = await providerLoader()

        guard generation == refreshGeneration else { return }

        var next: [LocationKey: LightPollutionRowDisplayState] = [:]
        next.reserveCapacity(keys.count)
        for key in keys {
            next[key] = Self.resolve(key: key, provider: provider)
        }

        guard generation == refreshGeneration else { return }
        // Drop deleted keys by replacing the dictionary wholesale.
        states = next
    }

    /// Pure resolution (no actor hop) for tests and refresh loop.
    nonisolated static func resolve(
        key: LocationKey,
        provider: (any LightPollutionProviding)?
    ) -> LightPollutionRowDisplayState {
        guard ModeledZenithBrightnessValidity.isValidGeographicCoordinate(
            latitude: key.latitude,
            longitude: key.longitude
        ) else {
            return .unavailable
        }
        guard let provider else {
            return .unavailable
        }
        let raw = provider.modeledZenithSkyBrightness(
            latitude: key.latitude,
            longitude: key.longitude
        )
        return LightPollutionDisplayPresentation.resolve(rawBrightness: raw)
    }
}
