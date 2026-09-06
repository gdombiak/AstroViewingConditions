@testable import SharedCode
import XCTest

private final class RecordingBrightnessProvider: LightPollutionProviding, @unchecked Sendable {
    let value: Double?
    let label: String
    private(set) var callCount = 0

    init(value: Double?, label: String = "default") {
        self.value = value
        self.label = label
    }

    func modeledZenithSkyBrightness(latitude: Double, longitude: Double) -> Double? {
        callCount += 1
        return value
    }
}

final class SavedLocationModeledBrightnessCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: SavedLocationModeledBrightnessStore!
    private var coordinator: SavedLocationModeledBrightnessCoordinator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-companion-coord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = SavedLocationModeledBrightnessStore(baseURL: tempDirectory)
        coordinator = SavedLocationModeledBrightnessCoordinator(store: store)
        SavedLocationBrightnessPublicationOrder.resetForTesting()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        store = nil
        coordinator = nil
        try super.tearDownWithError()
    }

    private func anchor(
        id: UUID = UUID(),
        lat: Double = 45.45,
        lon: Double = -122.75
    ) -> SavedLocationBrightnessAnchor {
        SavedLocationBrightnessAnchor(id: id, latitude: lat, longitude: lon)
    }

    private func latitudeDegrees(offsetMeters: Double) -> Double {
        (offsetMeters / 6_371_000.0) * (180.0 / .pi)
    }

    private func publication(
        _ revision: UInt64,
        _ locations: [SavedLocationBrightnessAnchor]
    ) -> SavedLocationBrightnessPublication {
        .makeForTesting(revision: revision, locations: locations)
    }

    // MARK: - Lifecycle snapshot

    func testSynchronizeCreateRenameCoordMoveAndDelete() async {
        let idA = UUID()
        let idB = UUID()
        let provider = RecordingBrightnessProvider(value: 18.5)

        await coordinator.synchronizeForTesting(
            locations: [anchor(id: idA), anchor(id: idB, lat: 46, lon: -123)],
            provider: provider
        )
        let countAfterCreate = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(countAfterCreate, 2)
        let sampleA0 = await coordinator.validSample(for: anchor(id: idA))
        XCTAssertNotNil(sampleA0)
        let callsAfterCreate = provider.callCount
        XCTAssertEqual(callsAfterCreate, 2)

        await coordinator.synchronizeForTesting(
            locations: [anchor(id: idA), anchor(id: idB, lat: 46, lon: -123)],
            provider: provider
        )
        XCTAssertEqual(provider.callCount, callsAfterCreate)
        let countAfterRename = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(countAfterRename, 2)

        let movedA = anchor(id: idA, lat: 45.45 + latitudeDegrees(offsetMeters: 5_000), lon: -122.75)
        await coordinator.synchronizeForTesting(
            locations: [movedA, anchor(id: idB, lat: 46, lon: -123)],
            provider: provider
        )
        XCTAssertEqual(provider.callCount, callsAfterCreate + 1)
        let sampleA = await coordinator.validSample(for: movedA)
        XCTAssertEqual(sampleA?.latitude ?? 0, movedA.latitude, accuracy: 1e-9)

        await coordinator.synchronizeForTesting(locations: [movedA], provider: provider)
        let countAfterDelete = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(countAfterDelete, 1)
        let sampleB = await coordinator.validSample(for: anchor(id: idB, lat: 46, lon: -123))
        XCTAssertNil(sampleB)
    }

    func testValidCacheDoesNotCallProvider() async {
        let id = UUID()
        let provider = RecordingBrightnessProvider(value: 19.0)
        let a = anchor(id: id)
        await coordinator.synchronizeForTesting(locations: [a], provider: provider)
        let calls = provider.callCount
        await coordinator.synchronizeForTesting(locations: [a], provider: provider)
        XCTAssertEqual(provider.callCount, calls)
        let sample = await coordinator.validSample(for: a)
        XCTAssertNotNil(sample)
    }

    func testProviderNilDoesNotInventSamplesAndDropsInvalid() async {
        let id = UUID()
        let a = anchor(id: id)
        await coordinator.synchronizeForTesting(
            locations: [a],
            provider: RecordingBrightnessProvider(value: 18.0)
        )
        let seeded = await coordinator.validSample(for: a)
        XCTAssertNotNil(seeded)

        let moved = anchor(id: id, lat: 10, lon: 10)
        await coordinator.synchronizeForTesting(locations: [moved], provider: nil)
        let afterMove = await coordinator.validSample(for: moved)
        XCTAssertNil(afterMove)
        let count = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(count, 0)

        let id2 = UUID()
        await coordinator.synchronizeForTesting(locations: [anchor(id: id2)], provider: nil)
        let missing = await coordinator.validSample(for: anchor(id: id2))
        XCTAssertNil(missing)
    }

    func testCoordinateWithinOneKilometerRetainsSample() async {
        let id = UUID()
        let provider = RecordingBrightnessProvider(value: 18.2)
        let base = anchor(id: id, lat: 0, lon: 0)
        await coordinator.synchronizeForTesting(locations: [base], provider: provider)
        let calls = provider.callCount
        let near = anchor(id: id, lat: latitudeDegrees(offsetMeters: 500), lon: 0)
        await coordinator.synchronizeForTesting(locations: [near], provider: provider)
        XCTAssertEqual(provider.callCount, calls)
        let sample = await coordinator.validSample(for: near)
        XCTAssertNotNil(sample)
    }

    func testDatasetRevisionMismatchResamples() async {
        let id = UUID()
        var document = SavedLocationModeledBrightnessDocument.empty()
        document.samplesBySavedLocationID[id.uuidString] = ModeledZenithBrightnessSample(
            latitude: 45.45,
            longitude: -122.75,
            modeledZenithSkyBrightness: 18.0,
            dataset: LightPollutionDatasetIdentity(
                datasetID: "lpatlas1",
                datasetRevision: 0,
                formatVersion: 1
            ),
            savedLocationID: id
        )
        XCTAssertTrue(store.write(document))

        let provider = RecordingBrightnessProvider(value: 20.0)
        let a = anchor(id: id)
        await coordinator.synchronizeForTesting(locations: [a], provider: provider)
        XCTAssertEqual(provider.callCount, 1)
        let sample = await coordinator.validSample(for: a)
        XCTAssertEqual(sample?.modeledZenithSkyBrightness ?? -1, 20.0, accuracy: 1e-9)
    }

    func testValidSampleUsesMemoryWithoutRereadingDisk() async {
        let id = UUID()
        let a = anchor(id: id)
        await coordinator.synchronizeForTesting(
            locations: [a],
            provider: RecordingBrightnessProvider(value: 18.5)
        )
        let first = await coordinator.validSample(for: a)
        XCTAssertNotNil(first)

        let fileURL = tempDirectory.appendingPathComponent(SavedLocationModeledBrightnessStore.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        let second = await coordinator.validSample(for: a)
        XCTAssertNotNil(second)
    }

    func testStickyUnsupportedSchemaDoesNotWrite() async throws {
        let payload: [String: Any] = [
            "schemaVersion": 999,
            "samplesBySavedLocationID": [:] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let fileURL = tempDirectory.appendingPathComponent(SavedLocationModeledBrightnessStore.fileName)
        try data.write(to: fileURL)
        let original = try Data(contentsOf: fileURL)

        let id = UUID()
        let provider = RecordingBrightnessProvider(value: 18.5)
        await coordinator.synchronizeForTesting(locations: [anchor(id: id)], provider: provider)
        let state = await coordinator.memoryStateDescriptionForTesting()
        XCTAssertEqual(state, "unsupported(999)")
        let sample = await coordinator.validSample(for: anchor(id: id))
        XCTAssertNil(sample)

        let afterFirst = try Data(contentsOf: fileURL)
        XCTAssertEqual(afterFirst, original)

        await coordinator.synchronizeForTesting(locations: [anchor(id: id)], provider: provider)
        let afterSecond = try Data(contentsOf: fileURL)
        XCTAssertEqual(afterSecond, original)
        XCTAssertEqual(provider.callCount, 0)
    }

    func testConcurrentUpsertsForDifferentIDsPreserveBoth() async {
        let id1 = UUID()
        let id2 = UUID()
        let provider = RecordingBrightnessProvider(value: 18.5)
        let both = [anchor(id: id1), anchor(id: id2)]
        let coord = coordinator!

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await coord.synchronizeForTesting(locations: both, provider: provider)
            }
            group.addTask {
                await coord.synchronizeForTesting(locations: both, provider: provider)
            }
        }

        let count = await coord.readySampleCountForTesting()
        XCTAssertEqual(count, 2)
        let sA = await coord.validSample(for: anchor(id: id1))
        let sB = await coord.validSample(for: anchor(id: id2))
        XCTAssertNotNil(sA)
        XCTAssertNotNil(sB)
    }

    func testDuplicateEnqueueDoesNotCorruptSurvivors() async {
        let ids = (0..<5).map { _ in UUID() }
        let provider = RecordingBrightnessProvider(value: 19.0)
        let anchors = ids.map { anchor(id: $0) }

        for _ in 0..<10 {
            let pub = SavedLocationBrightnessPublication.makeAuthoritative(locations: anchors)
            await coordinator.enqueueSynchronize(publication: pub, provider: provider)
        }
        await coordinator.synchronizeForTesting(locations: anchors, provider: provider)

        let count = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(count, 5)
        for a in anchors {
            let sample = await coordinator.validSample(for: a)
            XCTAssertNotNil(sample)
        }
        if case .ready(let doc) = store.load() {
            XCTAssertEqual(doc.samplesBySavedLocationID.count, 5)
        } else {
            XCTFail("Expected ready document on disk")
        }
    }

    func testExactAssociationRejectsNilSavedLocationIDCacheViaResolve() async {
        let id = UUID()
        let a = anchor(id: id)
        await coordinator.synchronizeForTesting(
            locations: [a],
            provider: RecordingBrightnessProvider(value: 18.0)
        )
        let sample = await coordinator.validSample(for: a)
        XCTAssertEqual(sample?.savedLocationID, id)
    }

    // MARK: - Publication revision ordering

    func testHigherRevisionSubmittedBeforeDelayedLowerLeavesHigherAsFinal() async {
        let id = UUID()
        let a = anchor(id: id)
        let provider = RecordingBrightnessProvider(value: 18.5)

        // Apply revision 2 first (create), then delayed revision 1 (empty).
        await coordinator.synchronize(
            publication: publication(2, [a]),
            provider: provider
        )
        await coordinator.synchronize(
            publication: publication(1, []),
            provider: provider
        )

        let count = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(count, 1)
        let sample = await coordinator.validSample(for: a)
        XCTAssertNotNil(sample)
        let accepted = await coordinator.highestAcceptedRevisionForTesting()
        XCTAssertEqual(accepted, 2)
    }

    func testStaleCreateCannotRestoreAfterNewerDelete() async {
        let id = UUID()
        let a = anchor(id: id)
        let provider = RecordingBrightnessProvider(value: 18.5)

        await coordinator.synchronize(
            publication: publication(1, [a]),
            provider: provider
        )
        await coordinator.synchronize(
            publication: publication(2, []),
            provider: provider
        )
        // Delayed stale create (rev 1) must not restore metadata.
        await coordinator.synchronize(
            publication: publication(1, [a]),
            provider: provider
        )

        let count = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(count, 0)
        let sample = await coordinator.validSample(for: a)
        XCTAssertNil(sample)
        let accepted = await coordinator.highestAcceptedRevisionForTesting()
        XCTAssertEqual(accepted, 2)
    }

    func testStaleDeleteCannotPruneAfterNewerCreate() async {
        let id = UUID()
        let a = anchor(id: id)
        let provider = RecordingBrightnessProvider(value: 18.5)

        await coordinator.synchronize(
            publication: publication(1, []),
            provider: provider
        )
        await coordinator.synchronize(
            publication: publication(2, [a]),
            provider: provider
        )
        // Delayed stale delete (rev 1) must not prune the newer create.
        await coordinator.synchronize(
            publication: publication(1, []),
            provider: provider
        )

        let count = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(count, 1)
        let sample = await coordinator.validSample(for: a)
        XCTAssertNotNil(sample)
    }

    func testPendingCoalescingRetainsHighestRevisionInReverseArrivalOrder() async {
        let idKeep = UUID()
        let idDrop = UUID()
        let provider = RecordingBrightnessProvider(value: 18.5)
        let keep = anchor(id: idKeep)
        let drop = anchor(id: idDrop)

        // Seed so file/memory ready.
        await coordinator.synchronize(
            publication: publication(1, [keep, drop]),
            provider: provider
        )

        // Simulate reverse-order enqueue while a drain might be active:
        // first enqueue lower revision (would drop both if applied last incorrectly),
        // then higher revision that keeps only `keep`.
        await coordinator.enqueueSynchronize(
            publication: publication(2, []),
            provider: provider
        )
        await coordinator.enqueueSynchronize(
            publication: publication(3, [keep]),
            provider: provider
        )
        // Also reverse: try to enqueue 2 again after 3 is pending — must not replace.
        await coordinator.enqueueSynchronize(
            publication: publication(2, [drop]),
            provider: provider
        )

        // Barrier: process any remaining pending via a no-op higher sync wait.
        // Drain may still be running; wait by applying an equal-or-higher accepted path.
        // Direct synchronize with rev 4 empty pending drain of 3 first.
        await coordinator.synchronize(
            publication: publication(4, [keep]),
            provider: provider
        )

        let keepSample = await coordinator.validSample(for: keep)
        let dropSample = await coordinator.validSample(for: drop)
        let count = await coordinator.readySampleCountForTesting()
        XCTAssertNotNil(keepSample)
        XCTAssertNil(dropSample)
        XCTAssertEqual(count, 1)
        let accepted = await coordinator.highestAcceptedRevisionForTesting()
        XCTAssertEqual(accepted, 4)
    }

    func testBackfillCannotOverwriteNewerLifecyclePublication() async {
        let id = UUID()
        let a = anchor(id: id)
        let provider = RecordingBrightnessProvider(value: 18.5)

        // Composition-root backfill stamps revision 1 with empty list (pre-CRUD fetch).
        let backfill = publication(1, [])
        // CRUD publish stamps revision 2 with the new location (after backfill stamp).
        let crud = publication(2, [a])

        // CRUD applies first (Task completed sooner), then delayed backfill.
        await coordinator.synchronize(publication: crud, provider: provider)
        await coordinator.synchronize(publication: backfill, provider: provider)

        let sample = await coordinator.validSample(for: a)
        XCTAssertNotNil(sample)
        let count = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(count, 1)
    }

    func testStaleRequestProviderDoesNotReplaceNewerPendingProvider() async {
        let id = UUID()
        let a = anchor(id: id)
        let staleProvider = RecordingBrightnessProvider(value: 17.0, label: "stale")
        let freshProvider = RecordingBrightnessProvider(value: 21.0, label: "fresh")

        // Hold the actor on a long first sync by processing rev 1 first, then enqueue
        // higher then lower while... simpler approach:
        // Enqueue rev 3 with fresh provider while idle starts drain immediately.
        // Better: enqueue rev 3 (fresh) then attempt enqueue rev 2 (stale) before drain
        // finishes — both happen on actor serially so:
        await coordinator.enqueueSynchronize(
            publication: publication(3, [a]),
            provider: freshProvider
        )
        await coordinator.enqueueSynchronize(
            publication: publication(2, [a]),
            provider: staleProvider
        )

        // Wait for drain by synchronizing a higher no-op wait with same locations.
        await coordinator.synchronize(
            publication: publication(4, [a]),
            provider: freshProvider
        )

        let sample = await coordinator.validSample(for: a)
        // Initial enrich from rev 3 must use freshProvider (21.0). Rev 4 cache hit
        // should not need provider; brightness remains 21.0 not 17.0.
        XCTAssertEqual(sample?.modeledZenithSkyBrightness ?? -1, 21.0, accuracy: 1e-9)
        XCTAssertEqual(staleProvider.callCount, 0)
        XCTAssertGreaterThan(freshProvider.callCount, 0)
    }

    func testEnqueueIgnoresRevisionAtOrBelowHighestAccepted() async {
        let id = UUID()
        let a = anchor(id: id)
        let provider = RecordingBrightnessProvider(value: 18.5)

        await coordinator.synchronize(publication: publication(5, [a]), provider: provider)
        await coordinator.enqueueSynchronize(publication: publication(5, []), provider: provider)
        await coordinator.enqueueSynchronize(publication: publication(4, []), provider: provider)

        // Force drain opportunity
        await coordinator.synchronize(publication: publication(6, [a]), provider: provider)

        let count = await coordinator.readySampleCountForTesting()
        XCTAssertEqual(count, 1)
        let sample = await coordinator.validSample(for: a)
        XCTAssertNotNil(sample)
    }
}

// MARK: - Reader facade

final class SavedLocationModeledBrightnessReadingTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp-companion-read-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testReaderLoadsValidSample() {
        let id = UUID()
        let store = SavedLocationModeledBrightnessStore(baseURL: tempDirectory)
        var document = SavedLocationModeledBrightnessDocument.empty()
        document.samplesBySavedLocationID[id.uuidString] = ModeledZenithBrightnessSample(
            latitude: 45.45,
            longitude: -122.75,
            modeledZenithSkyBrightness: 18.5,
            savedLocationID: id
        )
        XCTAssertTrue(store.write(document))

        let sample = SavedLocationModeledBrightnessReading.loadValidSample(
            for: SavedLocationBrightnessAnchor(id: id, latitude: 45.45, longitude: -122.75),
            baseURL: tempDirectory
        )
        XCTAssertEqual(sample?.modeledZenithSkyBrightness ?? -1, 18.5, accuracy: 1e-9)
    }

    func testReaderReturnsNilForMissingAndUnsupported() throws {
        let id = UUID()
        let anchor = SavedLocationBrightnessAnchor(id: id, latitude: 0, longitude: 0)
        XCTAssertNil(
            SavedLocationModeledBrightnessReading.loadValidSample(for: anchor, baseURL: tempDirectory)
        )

        let payload: [String: Any] = [
            "schemaVersion": 42,
            "samplesBySavedLocationID": [:] as [String: Any]
        ]
        try JSONSerialization.data(withJSONObject: payload).write(
            to: tempDirectory.appendingPathComponent(SavedLocationModeledBrightnessStore.fileName)
        )
        XCTAssertNil(
            SavedLocationModeledBrightnessReading.loadValidSample(for: anchor, baseURL: tempDirectory)
        )
    }
}
