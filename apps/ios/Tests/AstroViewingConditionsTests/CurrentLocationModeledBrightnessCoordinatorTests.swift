@testable import SharedCode
@testable import AstroViewingConditions
import CoreLocation
import XCTest

private final class RecordingBrightnessProvider: LightPollutionProviding, @unchecked Sendable {
    let value: Double?
    private(set) var callCount = 0

    init(value: Double?) {
        self.value = value
    }

    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        callCount += 1
        return value
    }
}

final class CurrentLocationModeledBrightnessCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: CurrentLocationModeledBrightnessStore!
    private var coordinator: CurrentLocationModeledBrightnessCoordinator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cl-companion-coord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = CurrentLocationModeledBrightnessStore(baseURL: tempDirectory)
        coordinator = CurrentLocationModeledBrightnessCoordinator(store: store)
        CurrentLocationBrightnessPublicationOrder.resetForTesting()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        store = nil
        coordinator = nil
        try super.tearDownWithError()
    }

    private func anchor(lat: Double = 45.45, lon: Double = -122.75) -> CurrentLocationBrightnessAnchor {
        CurrentLocationBrightnessAnchor(latitude: lat, longitude: lon)
    }

    private func publication(
        _ revision: UInt64,
        lat: Double = 45.45,
        lon: Double = -122.75
    ) -> CurrentLocationBrightnessPublication {
        .makeForTesting(revision: revision, anchor: anchor(lat: lat, lon: lon))
    }

    private func latitudeDegrees(offsetMeters: Double) -> Double {
        (offsetMeters / 6_371_000.0) * (180.0 / .pi)
    }

    func testValidSampleWithinExactlyOneThousandMetersRetainedWithoutProvider() async {
        let provider = RecordingBrightnessProvider(value: 18.5)
        let base = anchor(lat: 0, lon: 0)
        await coordinator.synchronizeForTesting(anchor: base, provider: provider)
        let calls = provider.callCount
        let near = anchor(lat: latitudeDegrees(offsetMeters: 1_000), lon: 0)
        await coordinator.synchronizeForTesting(anchor: near, provider: provider)
        XCTAssertEqual(provider.callCount, calls)
        let sample = await coordinator.validSample(for: near)
        XCTAssertNotNil(sample)
    }

    func testMovementJustBeyondOneThousandMetersResamples() async {
        let provider = RecordingBrightnessProvider(value: 18.5)
        let base = anchor(lat: 0, lon: 0)
        await coordinator.synchronizeForTesting(anchor: base, provider: provider)
        let calls = provider.callCount
        let far = anchor(lat: latitudeDegrees(offsetMeters: 1_000.5), lon: 0)
        await coordinator.synchronizeForTesting(anchor: far, provider: provider)
        XCTAssertEqual(provider.callCount, calls + 1)
    }

    func testBeyondToleranceNoProviderClearsSample() async {
        let provider = RecordingBrightnessProvider(value: 18.0)
        let base = anchor()
        await coordinator.synchronizeForTesting(anchor: base, provider: provider)
        let _has = await coordinator.hasSampleForTesting()
        XCTAssertTrue(_has)

        let far = anchor(lat: 10, lon: 10)
        await coordinator.synchronizeForTesting(anchor: far, provider: nil)
        let _has2 = await coordinator.hasSampleForTesting()
        XCTAssertFalse(_has2)
        let sample = await coordinator.validSample(for: far)
        XCTAssertNil(sample)
    }

    func testDatasetRevisionMismatchRefreshes() async {
        var document = CurrentLocationModeledBrightnessDocument.empty()
        document.sample = ModeledZenithBrightnessSample(
            latitude: 45.45,
            longitude: -122.75,
            modeledZenithSkyBrightness: 18.0,
            dataset: LightPollutionDatasetIdentity(
                datasetID: "lpatlas1",
                datasetRevision: 0,
                formatVersion: 1
            ),
            savedLocationID: nil
        )
        XCTAssertTrue(store.write(document))

        let provider = RecordingBrightnessProvider(value: 20.0)
        await coordinator.synchronizeForTesting(anchor: anchor(), provider: provider)
        XCTAssertEqual(provider.callCount, 1)
        let sample = await coordinator.validSample(for: anchor())
        XCTAssertEqual(sample?.modeledZenithSkyBrightness ?? -1, 20.0, accuracy: 1e-9)
    }

    func testInvalidGeographicCoordinatesNeverCallProvider() async {
        let provider = RecordingBrightnessProvider(value: 18.5)
        await coordinator.synchronize(
            publication: publication(1, lat: 95, lon: 0),
            provider: provider
        )
        XCTAssertEqual(provider.callCount, 0)
        let _has2 = await coordinator.hasSampleForTesting()
        XCTAssertFalse(_has2)
        let accepted = await coordinator.highestAcceptedRevisionForTesting()
        XCTAssertEqual(accepted, 1)
    }

    func testNewerInvalidClearsAndOlderValidCannotRestore() async {
        let provider = RecordingBrightnessProvider(value: 18.5)
        await coordinator.synchronize(publication: publication(1), provider: provider)
        let _has = await coordinator.hasSampleForTesting()
        XCTAssertTrue(_has)

        await coordinator.synchronize(
            publication: publication(2, lat: .nan, lon: 0),
            provider: provider
        )
        XCTAssertEqual(provider.callCount, 1) // only first sync
        let _has2 = await coordinator.hasSampleForTesting()
        XCTAssertFalse(_has2)

        // Delayed older valid
        await coordinator.synchronize(publication: publication(1), provider: provider)
        let restored = await coordinator.hasSampleForTesting()
        XCTAssertFalse(restored)
        let accepted = await coordinator.highestAcceptedRevisionForTesting()
        XCTAssertEqual(accepted, 2)
    }

    func testNewerRevisionWinsWhenOlderArrivesLater() async {
        let provider = RecordingBrightnessProvider(value: 18.5)
        let a = anchor(lat: 45.45, lon: -122.75)
        let b = anchor(lat: 46, lon: -123)

        await coordinator.synchronize(
            publication: .makeForTesting(revision: 2, anchor: b),
            provider: provider
        )
        await coordinator.synchronize(
            publication: .makeForTesting(revision: 1, anchor: a),
            provider: provider
        )

        let sampleB = await coordinator.validSample(for: b)
        let sampleA = await coordinator.validSample(for: a)
        XCTAssertNotNil(sampleB)
        XCTAssertNil(sampleA)
    }

    func testStaleProviderDoesNotReplaceNewer() async {
        let stale = RecordingBrightnessProvider(value: 17.0)
        let fresh = RecordingBrightnessProvider(value: 21.0)
        let a = anchor()

        await coordinator.enqueueSynchronize(
            publication: publication(3),
            provider: fresh
        )
        await coordinator.enqueueSynchronize(
            publication: publication(2),
            provider: stale
        )
        await coordinator.synchronize(publication: publication(4), provider: fresh)

        let sample = await coordinator.validSample(for: a)
        XCTAssertEqual(sample?.modeledZenithSkyBrightness ?? -1, 21.0, accuracy: 1e-9)
        XCTAssertEqual(stale.callCount, 0)
    }

    func testReverseOrderEnqueueKeepsHighestRevision() async {
        let provider = RecordingBrightnessProvider(value: 18.5)
        let keep = anchor(lat: 45.45, lon: -122.75)
        let drop = anchor(lat: 10, lon: 10)

        await coordinator.synchronize(
            publication: .makeForTesting(revision: 1, anchor: keep),
            provider: provider
        )
        await coordinator.enqueueSynchronize(
            publication: .makeForTesting(revision: 2, anchor: drop),
            provider: provider
        )
        await coordinator.enqueueSynchronize(
            publication: .makeForTesting(revision: 3, anchor: keep),
            provider: provider
        )
        await coordinator.synchronize(
            publication: .makeForTesting(revision: 4, anchor: keep),
            provider: provider
        )

        let sample = await coordinator.validSample(for: keep)
        XCTAssertNotNil(sample)
    }

    func testActorMemoryAvoidsReread() async {
        let provider = RecordingBrightnessProvider(value: 18.5)
        let a = anchor()
        await coordinator.synchronizeForTesting(anchor: a, provider: provider)
        let fileURL = tempDirectory.appendingPathComponent(CurrentLocationModeledBrightnessStore.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        let sample = await coordinator.validSample(for: a)
        XCTAssertNotNil(sample)
    }

    func testStickyUnsupportedDoesNotWrite() async throws {
        let payload: [String: Any] = ["schemaVersion": 999]
        try JSONSerialization.data(withJSONObject: payload).write(
            to: tempDirectory.appendingPathComponent(CurrentLocationModeledBrightnessStore.fileName)
        )
        let original = try Data(
            contentsOf: tempDirectory.appendingPathComponent(CurrentLocationModeledBrightnessStore.fileName)
        )
        let provider = RecordingBrightnessProvider(value: 18.5)
        await coordinator.synchronizeForTesting(anchor: anchor(), provider: provider)
        let state = await coordinator.memoryStateDescriptionForTesting()
        XCTAssertEqual(state, "unsupported(999)")
        let after = try Data(
            contentsOf: tempDirectory.appendingPathComponent(CurrentLocationModeledBrightnessStore.fileName)
        )
        XCTAssertEqual(after, original)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testReaderLoadsValidSample() {
        var document = CurrentLocationModeledBrightnessDocument.empty()
        document.sample = ModeledZenithBrightnessSample(
            latitude: 45.45,
            longitude: -122.75,
            modeledZenithSkyBrightness: 18.5,
            savedLocationID: nil
        )
        XCTAssertTrue(store.write(document))
        let sample = CurrentLocationModeledBrightnessReading.loadValidSample(
            for: anchor(),
            baseURL: tempDirectory
        )
        XCTAssertEqual(sample?.modeledZenithSkyBrightness ?? -1, 18.5, accuracy: 1e-9)
    }

    func testReaderNilForMissing() {
        XCTAssertNil(
            CurrentLocationModeledBrightnessReading.loadValidSample(
                for: anchor(),
                baseURL: tempDirectory
            )
        )
    }
}

// MARK: - Publisher gates

private final class EnqueueCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var lastRevision: UInt64?

    func record(_ revision: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        lastRevision = revision
    }
}

@MainActor
final class AppCurrentLocationBrightnessPublisherTests: XCTestCase {
    func testInvalidCoordinatesDoNotEnqueue() async {
        let counter = EnqueueCounter()
        let publisher = AppCurrentLocationBrightnessPublisher(
            providerLookup: { nil },
            enqueue: { publication, _ in counter.record(publication.revision) }
        )
        publisher.publishResolvedCurrentLocation(latitude: 95, longitude: 0)
        publisher.publishResolvedCurrentLocation(latitude: .nan, longitude: 0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(counter.count, 0)
    }

    func testZeroZeroPlaceholderDoesNotEnqueue() async {
        let counter = EnqueueCounter()
        let publisher = AppCurrentLocationBrightnessPublisher(
            providerLookup: { nil },
            enqueue: { publication, _ in counter.record(publication.revision) }
        )
        publisher.publishResolvedCurrentLocation(latitude: 0, longitude: 0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(counter.count, 0)
    }

    func testValidCoordinatesEnqueueOnce() async {
        let counter = EnqueueCounter()
        let publisher = AppCurrentLocationBrightnessPublisher(
            providerLookup: { nil },
            enqueue: { publication, _ in counter.record(publication.revision) }
        )
        publisher.publishResolvedCurrentLocation(latitude: 45.45, longitude: -122.75)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(counter.count, 1)
        XCTAssertNotNil(counter.lastRevision)
    }
}

// MARK: - Loader publishing

@MainActor
final class DashboardLocationBrightnessPublicationTests: XCTestCase {
    private final class LocationProviderSpy: DashboardCurrentLocationProviding {
        var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
        var isAuthorized: Bool { authorizationStatus == .authorizedWhenInUse }
        var resolveCallCount = 0
        var resolvedLocation = CachedLocation(
            name: "Resolved",
            latitude: 45.51,
            longitude: -122.67
        )

        func requestAuthorization() {}
        func resolveCurrentLocation() async throws -> CachedLocation {
            resolveCallCount += 1
            return resolvedLocation
        }
    }

    func testRecordingPublisherReceivesExactlyOneEventAfterSuccessfulResolve() async {
        let provider = LocationProviderSpy()
        let recording = RecordingCurrentLocationBrightnessPublisher()
        let loader = DashboardLocationLoader(
            persistedSelection: nil,
            provider: provider,
            saveSelection: { _ in },
            brightnessPublisher: recording
        )
        loader.restoreSelection(using: [])
        _ = try? await loader.resolveCurrentLocationIfNeeded()

        XCTAssertEqual(recording.events.count, 1)
        XCTAssertEqual(recording.events[0].latitude, provider.resolvedLocation.latitude)
        XCTAssertEqual(recording.events[0].longitude, provider.resolvedLocation.longitude)
    }

    func testStaleResolutionDoesNotPublish() async {
        let provider = SuspendedSpy()
        let recording = RecordingCurrentLocationBrightnessPublisher()
        let fixed = CachedLocation(id: UUID(), name: "Fixed", latitude: 1, longitude: 2)
        let loader = DashboardLocationLoader(
            persistedSelection: SelectedLocation(
                source: .currentGPS,
                name: "My Current Location",
                latitude: 0,
                longitude: 0
            ),
            provider: provider,
            saveSelection: { _ in },
            brightnessPublisher: recording
        )

        let task = Task { try? await loader.resolveCurrentLocationIfNeeded() }
        await provider.waitForResolutionRequest()
        loader.select(
            SelectedLocation(
                source: .saved,
                id: fixed.id,
                name: fixed.name,
                latitude: fixed.latitude,
                longitude: fixed.longitude
            )
        )
        provider.complete()
        _ = await task.value

        XCTAssertEqual(recording.events.count, 0)
    }

    private final class SuspendedSpy: DashboardCurrentLocationProviding {
        var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
        var isAuthorized: Bool { true }
        private var continuation: CheckedContinuation<CachedLocation, Error>?
        private var waitContinuation: CheckedContinuation<Void, Never>?

        func requestAuthorization() {}

        func resolveCurrentLocation() async throws -> CachedLocation {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.waitContinuation?.resume()
                self.waitContinuation = nil
            }
        }

        func waitForResolutionRequest() async {
            await withCheckedContinuation { cont in
                if continuation != nil {
                    cont.resume()
                } else {
                    waitContinuation = cont
                }
            }
        }

        func complete() {
            continuation?.resume(
                returning: CachedLocation(name: "Late", latitude: 45, longitude: -122)
            )
            continuation = nil
        }
    }
}
