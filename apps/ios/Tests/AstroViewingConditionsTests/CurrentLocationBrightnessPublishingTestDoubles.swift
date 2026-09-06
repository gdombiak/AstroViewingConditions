import SharedCode
import Foundation

/// Test-only no-op publisher so `DashboardLocationLoader` tests never touch App Group
/// brightness files or bootstrap globals.
@MainActor
final class NoOpCurrentLocationBrightnessPublisher: CurrentLocationBrightnessPublishing {
    init() {}

    func publishResolvedCurrentLocation(latitude: Double, longitude: Double) {}
}

/// Test-only recording publisher for verifying GPS-resolve publication events.
@MainActor
final class RecordingCurrentLocationBrightnessPublisher: CurrentLocationBrightnessPublishing {
    private(set) var events: [(latitude: Double, longitude: Double)] = []

    init() {}

    func publishResolvedCurrentLocation(latitude: Double, longitude: Double) {
        events.append((latitude, longitude))
    }
}
