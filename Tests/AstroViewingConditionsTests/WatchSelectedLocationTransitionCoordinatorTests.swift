@testable import SharedCode
import XCTest

// MARK: - Fixtures

private enum TransitionFixtures {
    static func saved(
        id: UUID = UUID(),
        name: String = "Site",
        lat: Double = 45.5,
        lon: Double = -122.7
    ) -> SelectedLocation {
        SelectedLocation(source: .saved, id: id, name: name, latitude: lat, longitude: lon)
    }

    static func currentPlaceholder() -> SelectedLocation {
        SelectedLocation(source: .currentGPS, name: "Current Location", latitude: 0, longitude: 0)
    }

    static func current(lat: Double, lon: Double) -> SelectedLocation {
        SelectedLocation(source: .currentGPS, name: "Current Location", latitude: lat, longitude: lon)
    }
}

private final class ClaimCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var _tokens: [WatchConditionsLiveUpdateToken] = []
    private var nextSequence: UInt64 = 1

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    var tokens: [WatchConditionsLiveUpdateToken] {
        lock.lock(); defer { lock.unlock() }
        return _tokens
    }

    func claim() -> WatchConditionsLiveUpdateToken {
        lock.lock()
        defer { lock.unlock() }
        let token = WatchConditionsLiveUpdateToken(sequence: nextSequence)
        nextSequence &+= 1
        _count += 1
        _tokens.append(token)
        return token
    }
}

/// Thread-safe collector for concurrent `applyRemote` results (no captured `var` array).
private final class TransitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [WatchSelectedLocationTransition] = []

    func append(_ transition: WatchSelectedLocationTransition) {
        lock.lock()
        storage.append(transition)
        lock.unlock()
    }

    func snapshot() -> [WatchSelectedLocationTransition] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// MARK: - Core transition coordinator tests

final class WatchSelectedLocationTransitionCoordinatorTests: XCTestCase {

    func testStartupSeed_IdenticalRemoteIsNoOp() {
        let id = UUID()
        let b = TransitionFixtures.saved(id: id, name: "B")
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()
        let t = coord.applyRemote(b, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t.kind, .noOp)
        XCTAssertEqual(claims.count, 0)
        XCTAssertFalse(t.requiresPublication)
        XCTAssertFalse(t.requiresPersistence)
        XCTAssertNil(t.refreshToken)
    }

    func testStartupSeed_DifferentIsMaterial() {
        let b = TransitionFixtures.saved(name: "B")
        let c = TransitionFixtures.saved(name: "C", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()
        let t = coord.applyRemote(c, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t.kind, .material)
        XCTAssertEqual(claims.count, 1)
        XCTAssertNotNil(t.refreshToken)
        XCTAssertEqual(coord.currentAuthoritative, c)
    }

    func testDuplicateBBeforePublication_SecondIsNoOp() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()

        let t1 = coord.applyRemote(b, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t1.kind, .material)
        XCTAssertEqual(claims.count, 1)

        // Second B while UI still on A — authority already B.
        let t2 = coord.applyRemote(b, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t2.kind, .noOp)
        XCTAssertEqual(claims.count, 1, "second B must not claim")
        XCTAssertNil(t2.refreshToken)
    }

    func testBThenC_BothMaterial_OrderPreserved() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()

        let tB = coord.applyRemote(b, claimRefresh: {claims.claim() }, submit: { _ in })
        let tC = coord.applyRemote(c, claimRefresh: {claims.claim() }, submit: { _ in })

        XCTAssertEqual(tB.kind, .material)
        XCTAssertEqual(tC.kind, .material)
        XCTAssertEqual(claims.count, 2)
        XCTAssertLessThan(tB.order, tC.order)
        XCTAssertEqual(tB.refreshToken?.sequence, 1)
        XCTAssertEqual(tC.refreshToken?.sequence, 2)
        XCTAssertEqual(coord.currentAuthoritative, c)
    }

    func testCThenB_FinalAuthoritativeIsB() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()

        let tC = coord.applyRemote(c, claimRefresh: {claims.claim() }, submit: { _ in })
        let tB = coord.applyRemote(b, claimRefresh: {claims.claim() }, submit: { _ in })

        XCTAssertEqual(tC.kind, .material)
        XCTAssertEqual(tB.kind, .material)
        XCTAssertLessThan(tC.order, tB.order)
        XCTAssertEqual(coord.currentAuthoritative, b)
    }

    func testRenameOnly_NoClaim_SecondRenameNoOp() {
        let id = UUID()
        let b = TransitionFixtures.saved(id: id, name: "B")
        let b2 = TransitionFixtures.saved(id: id, name: "B Renamed")
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()

        let t1 = coord.applyRemote(b2, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t1.kind, .displayOnly)
        XCTAssertEqual(claims.count, 0)
        XCTAssertNil(t1.refreshToken)
        XCTAssertTrue(t1.requiresPersistence)
        XCTAssertTrue(t1.requiresPublication)

        let t2 = coord.applyRemote(b2, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t2.kind, .noOp)
        XCTAssertEqual(claims.count, 0)
    }

    func testMaterialAfterRenameUsesRenamedAuthority() {
        let id = UUID()
        let b = TransitionFixtures.saved(id: id, name: "B", lat: 45.5, lon: -122.7)
        let b2 = TransitionFixtures.saved(id: id, name: "B Renamed", lat: 45.5, lon: -122.7)
        let b3 = TransitionFixtures.saved(id: id, name: "B Renamed", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()

        let tRename = coord.applyRemote(b2, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(tRename.kind, .displayOnly)
        XCTAssertEqual(claims.count, 0)

        let tMaterial = coord.applyRemote(b3, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(tMaterial.kind, .material)
        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(coord.currentAuthoritative, b3)
    }

    func testCurrentLocationPlaceholderEchoStorm() {
        let cl = TransitionFixtures.currentPlaceholder()
        let coord = WatchSelectedLocationTransitionCoordinator(seed: cl)
        let claims = ClaimCounter()
        for _ in 0..<20 {
            let t = coord.applyRemote(cl, claimRefresh: {claims.claim() }, submit: { _ in })
            XCTAssertEqual(t.kind, .noOp)
        }
        XCTAssertEqual(claims.count, 0)
    }

    func testPlaceholderToRealCoordinatesIsMaterial() {
        let coord = WatchSelectedLocationTransitionCoordinator(seed: TransitionFixtures.currentPlaceholder())
        let claims = ClaimCounter()
        let real = TransitionFixtures.current(lat: 45.5, lon: -122.7)
        let t = coord.applyRemote(real, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t.kind, .material)
        XCTAssertEqual(claims.count, 1)
    }

    func testRealCoordinatesMaterialChange() {
        let coord = WatchSelectedLocationTransitionCoordinator(
            seed: TransitionFixtures.current(lat: 45.5, lon: -122.7)
        )
        let claims = ClaimCounter()
        let next = TransitionFixtures.current(lat: 47.6, lon: -122.3)
        let t = coord.applyRemote(next, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t.kind, .material)
        XCTAssertEqual(claims.count, 1)
    }

    func testTinyCoordinateDifferenceWithinToleranceIsNoOp() {
        let base = 45.5
        let eps = WatchSelectedLocationMaterialIdentity.coordinateTolerance * 0.5
        let seed = TransitionFixtures.current(lat: base, lon: -122.7)
        let near = TransitionFixtures.current(lat: base + eps, lon: -122.7)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: seed)
        let claims = ClaimCounter()
        // Name equal, coords within tolerance — full SelectedLocation equality may still differ.
        // Material identity uses tolerance; if != for persistence, displayOnly possible.
        let t = coord.applyRemote(near, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(claims.count, 0, "within tolerance must not claim")
        XCTAssertNotEqual(t.kind, .material)
    }

    func testUserForceRefreshClaimsEvenIfIdentical() {
        let b = TransitionFixtures.saved(name: "B")
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()
        let t = coord.applyUser(b, sendToPhone: true, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(t.kind, .material)
        XCTAssertEqual(claims.count, 1)
        XCTAssertNotNil(t.refreshToken)
    }

    func testDirectUserThenPhoneEcho_OnlyOneClaim() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()

        let user = coord.applyUser(b, sendToPhone: true, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(user.kind, .material)
        XCTAssertEqual(claims.count, 1)

        let echo = coord.applyRemote(b, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(echo.kind, .noOp)
        XCTAssertEqual(claims.count, 1, "phone echo must not claim again")
    }

    func testDirectUserBThenRemoteC_CComparesAgainstB() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()

        _ = coord.applyUser(b, sendToPhone: true, claimRefresh: {claims.claim() }, submit: { _ in })
        let tC = coord.applyRemote(c, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(tC.kind, .material)
        XCTAssertEqual(claims.count, 2)
        XCTAssertEqual(coord.currentAuthoritative, c)
    }

    func testRemoteBThenDirectUserC_CWins() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()

        _ = coord.applyRemote(b, claimRefresh: {claims.claim() }, submit: { _ in })
        let tC = coord.applyUser(c, sendToPhone: true, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertEqual(tC.kind, .material)
        XCTAssertEqual(coord.currentAuthoritative, c)
        XCTAssertEqual(claims.count, 2)
    }

    func testRenameDoesNotInvalidateMatchingRefreshTokenAbsence() {
        let id = UUID()
        let b = TransitionFixtures.saved(id: id, name: "B")
        let b2 = TransitionFixtures.saved(id: id, name: "B2")
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()
        // Simulate active B refresh already claimed externally — rename must not claim.
        let t = coord.applyRemote(b2, claimRefresh: {claims.claim() }, submit: { _ in })
        XCTAssertNil(t.refreshToken)
        XCTAssertEqual(claims.count, 0)
    }

    func testMaterialRemoteClaimsImmediatelyUnderLock() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        var claimedDuringApply = false
        let t = coord.applyRemote(
            b,
            claimRefresh: {
                claimedDuringApply = true
                // Claim runs under coordinator lock before authority advance completes.
                return WatchConditionsLiveUpdateToken(sequence: 1)
            },
            submit: { _ in }
        )
        XCTAssertTrue(claimedDuringApply)
        XCTAssertNotNil(t.refreshToken)
        XCTAssertEqual(coord.currentAuthoritative, b)
    }

    func testConcurrentApplyIsSerialized() {
        let a = TransitionFixtures.saved(name: "A")
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let group = DispatchGroup()
        let recorder = TransitionRecorder()

        for i in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                let loc = TransitionFixtures.saved(
                    id: UUID(),
                    name: "S\(i)",
                    lat: 40 + Double(i),
                    lon: -70 - Double(i)
                )
                let t = coord.applyRemote(loc, claimRefresh: { claims.claim() }, submit: { _ in })
                recorder.append(t)
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        // All 10 material from A (or sequential material).
        let transitions = recorder.snapshot()
        XCTAssertEqual(claims.count, 10)
        XCTAssertEqual(transitions.count, 10)
        XCTAssertEqual(Set(transitions.map(\.order)).count, 10, "orders must be unique")
    }
}

// MARK: - Production FIFO applier harness

/// Drives the real ``WatchSelectedLocationTransitionApplier`` with recorded side effects.
///
/// Use ``submit`` with coordinator `applyRemote`/`applyUser` so classification and
/// applier submission stay atomic under the coordinator lock (production contract).
private final class ProductionApplierHarness: @unchecked Sendable {
    let applier = WatchSelectedLocationTransitionApplier(
        label: "test.selection.transition.apply.\(UUID().uuidString)"
    )
    private let lock = NSLock()
    private var _published: [SelectedLocation] = []
    private var _persisted: [SelectedLocation] = []
    private var _sent: [SelectedLocation] = []
    private var _refreshes: [(SelectedLocation, UInt64)] = []
    private var _startRefreshPublishedSnapshot: [SelectedLocation] = []
    private var _startRefreshPersistedSnapshot: [SelectedLocation] = []
    private var _uiSelected: SelectedLocation?
    private var _submittedOrders: [UInt64] = []
    private var _submittedNames: [String] = []
    private var _applicationBegan: Int = 0

    private var holdBeforePublication = false
    private let holdEntered = DispatchSemaphore(value: 0)
    private let holdRelease = DispatchSemaphore(value: 0)

    var published: [SelectedLocation] {
        lock.lock(); defer { lock.unlock() }
        return _published
    }
    var persisted: [SelectedLocation] {
        lock.lock(); defer { lock.unlock() }
        return _persisted
    }
    var sent: [SelectedLocation] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }
    var refreshes: [(SelectedLocation, UInt64)] {
        lock.lock(); defer { lock.unlock() }
        return _refreshes
    }
    var startRefreshPublishedSnapshot: [SelectedLocation] {
        lock.lock(); defer { lock.unlock() }
        return _startRefreshPublishedSnapshot
    }
    var startRefreshPersistedSnapshot: [SelectedLocation] {
        lock.lock(); defer { lock.unlock() }
        return _startRefreshPersistedSnapshot
    }
    var uiSelected: SelectedLocation? {
        lock.lock(); defer { lock.unlock() }
        return _uiSelected
    }
    var submittedOrders: [UInt64] {
        lock.lock(); defer { lock.unlock() }
        return _submittedOrders
    }
    var submittedNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return _submittedNames
    }
    var applicationBeganCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _applicationBegan
    }

    init() {
        applier.beforePublication = { [weak self] _ in
            guard let self else { return }
            if self.holdBeforePublication {
                self.holdBeforePublication = false
                self.holdEntered.signal()
                self.holdRelease.wait()
            }
        }
        applier.onBeginApplication = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self._applicationBegan += 1
            self.lock.unlock()
        }
    }

    func setHoldNextPublication(_ value: Bool) {
        holdBeforePublication = value
    }

    func waitUntilHeld() {
        _ = holdEntered.wait(timeout: .now() + 5)
    }

    func releaseHold() {
        holdRelease.signal()
    }

    /// Production-shaped nonblocking submit — only `applier.enqueue` (queue.async).
    func submit(_ transition: WatchSelectedLocationTransition) {
        lock.lock()
        _submittedOrders.append(transition.order)
        _submittedNames.append(transition.incoming.name)
        lock.unlock()

        applier.enqueue(
            transition,
            publish: { [weak self] location in
                self?.lock.lock()
                self?._published.append(location)
                self?._uiSelected = location
                self?.lock.unlock()
            },
            persist: { [weak self] location in
                self?.lock.lock()
                self?._persisted.append(location)
                self?.lock.unlock()
            },
            sendToPhone: { [weak self] location in
                self?.lock.lock()
                self?._sent.append(location)
                self?.lock.unlock()
            },
            startRefresh: { [weak self] location, token in
                guard let self else { return }
                self.lock.lock()
                self._startRefreshPublishedSnapshot.append(self._uiSelected ?? location)
                self._startRefreshPersistedSnapshot.append(self._persisted.last ?? location)
                self._refreshes.append((location, token.sequence))
                self.lock.unlock()
            }
        )
    }

    func waitUntilPublished(count: Int) {
        for _ in 0..<10_000 {
            if published.count >= count { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func waitUntilRefreshes(count: Int) {
        for _ in 0..<10_000 {
            if refreshes.count >= count { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func waitUntilDrained(expectedPublished: Int) {
        waitUntilPublished(count: expectedPublished)
        for _ in 0..<200 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func assertFinalAgreement(
        _ coord: WatchSelectedLocationTransitionCoordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(uiSelected, coord.currentAuthoritative, "UI must match authority", file: file, line: line)
        XCTAssertEqual(persisted.last, coord.currentAuthoritative, "persist must match authority", file: file, line: line)
        XCTAssertEqual(uiSelected, persisted.last, "UI must match persist", file: file, line: line)
    }
}

// MARK: - Production FIFO application order (atomic submit)

final class WatchSelectedLocationTransitionApplicationOrderTests: XCTestCase {
    func testBThenC_PublicationAndRefreshOrder() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilRefreshes(count: 2)

        XCTAssertEqual(app.published.map(\.name), ["B", "C"])
        XCTAssertEqual(app.refreshes.map(\.1), [1, 2])
        XCTAssertEqual(app.startRefreshPublishedSnapshot.map(\.name), ["B", "C"])
        app.assertFinalAgreement(coord)
    }

    func testRefreshStartsAfterPublication_SnapshotMatchesIncoming() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilRefreshes(count: 1)
        XCTAssertEqual(app.startRefreshPublishedSnapshot.first, b)
        XCTAssertEqual(app.published.first, b)
    }

    func testPersistenceBeforeRefresh_SnapshotMatchesIncoming() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilRefreshes(count: 1)
        XCTAssertEqual(app.startRefreshPersistedSnapshot.first, b)
        XCTAssertEqual(app.persisted.first, b)
    }

    func testHoldFirstTransition_SecondStillClassifiesAgainstAdvancedAuthority() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilHeld()

        let t2 = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(t2.kind, .noOp)
        XCTAssertEqual(claims.count, 1)

        app.releaseHold()
        app.waitUntilRefreshes(count: 1)
        XCTAssertEqual(app.refreshes.count, 1)
        XCTAssertEqual(app.published.count, 1)
    }

    func testPersistenceOrder_BThenC_FinalIsC() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilRefreshes(count: 2)

        XCTAssertEqual(app.persisted.map(\.name), ["B", "C"])
        XCTAssertEqual(app.persisted.last?.name, "C")
        app.assertFinalAgreement(coord)
    }

    func testNoOpDoesNotProduceRefreshOrPublication() {
        let b = TransitionFixtures.saved(name: "B")
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        for _ in 0..<50 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        XCTAssertTrue(app.published.isEmpty)
        XCTAssertTrue(app.refreshes.isEmpty)
        XCTAssertTrue(app.submittedOrders.isEmpty)
        XCTAssertEqual(claims.count, 0)
    }

    // MARK: Mixed remote / user FIFO (atomic submit)

    func testRemoteBQueuedThenUserC_PublicationOrderBThenC_FinalIsC() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        let tB = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(tB.kind, .material)
        app.waitUntilHeld()

        let tC = coord.applyUser(c, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(tC.kind, .material)
        XCTAssertEqual(coord.currentAuthoritative, c)
        XCTAssertEqual(claims.count, 2)

        app.releaseHold()
        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)

        XCTAssertEqual(app.published.map(\.name), ["B", "C"])
        XCTAssertEqual(app.persisted.map(\.name), ["B", "C"])
        XCTAssertEqual(app.refreshes.map(\.1), [1, 2])
        XCTAssertEqual(app.startRefreshPublishedSnapshot.map(\.name), ["B", "C"])
        XCTAssertEqual(app.startRefreshPersistedSnapshot.map(\.name), ["B", "C"])
        XCTAssertEqual(app.sent.map(\.name), ["C"])
        app.assertFinalAgreement(coord)
    }

    func testUserBThenRemoteC_BeforeBPublishes() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilHeld()

        let tC = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(tC.kind, .material)

        app.releaseHold()
        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)

        XCTAssertEqual(app.published.map(\.name), ["B", "C"])
        XCTAssertEqual(app.persisted.last, c)
        app.assertFinalAgreement(coord)
    }

    func testRemoteB_UserC_RemoteD_FinalIsD() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let d = TransitionFixtures.saved(id: UUID(), name: "D", lat: 34.0, lon: -118.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilHeld()
        _ = coord.applyUser(c, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        _ = coord.applyRemote(d, claimRefresh: { claims.claim() }, submit: app.submit)

        XCTAssertEqual(claims.count, 3)
        XCTAssertEqual(coord.currentAuthoritative, d)

        app.releaseHold()
        app.waitUntilRefreshes(count: 3)
        app.waitUntilDrained(expectedPublished: 3)

        XCTAssertEqual(app.published.map(\.name), ["B", "C", "D"])
        XCTAssertEqual(app.refreshes.map(\.1), [1, 2, 3])
        app.assertFinalAgreement(coord)
    }

    func testUserB_RemoteC_UserD_FinalIsD() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let d = TransitionFixtures.saved(id: UUID(), name: "D", lat: 34.0, lon: -118.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilHeld()
        _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
        _ = coord.applyUser(d, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)

        app.releaseHold()
        app.waitUntilRefreshes(count: 3)
        app.waitUntilDrained(expectedPublished: 3)

        XCTAssertEqual(app.published.map(\.name), ["B", "C", "D"])
        XCTAssertEqual(app.sent.map(\.name), ["B", "D"])
        app.assertFinalAgreement(coord)
    }

    func testUserEchoSuppression_OnePublicationAndRefresh() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        let user = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(user.kind, .material)
        app.waitUntilHeld()

        let echo = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(echo.kind, .noOp)

        app.releaseHold()
        app.waitUntilRefreshes(count: 1)
        for _ in 0..<50 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }

        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(app.published.count, 1)
        XCTAssertEqual(app.persisted.count, 1)
        XCTAssertEqual(app.refreshes.count, 1)
        XCTAssertEqual(app.sent.count, 1)
        XCTAssertEqual(app.submittedNames, ["B"])
    }

    func testRenameOnlyFIFO_AfterStableSeed() {
        let id = UUID()
        let b = TransitionFixtures.saved(id: id, name: "B")
        let b2 = TransitionFixtures.saved(id: id, name: "B Renamed")
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let t = coord.applyRemote(b2, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(t.kind, .displayOnly)
        XCTAssertNil(t.refreshToken)
        app.waitUntilPublished(count: 1)
        for _ in 0..<50 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }

        XCTAssertEqual(claims.count, 0)
        XCTAssertEqual(app.published.map(\.name), ["B Renamed"])
        XCTAssertEqual(app.persisted.map(\.name), ["B Renamed"])
        XCTAssertTrue(app.refreshes.isEmpty)
        app.assertFinalAgreement(coord)
    }

    func testRapidUserABC_FinalIsC() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let d = TransitionFixtures.saved(id: UUID(), name: "D", lat: 34.0, lon: -118.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        _ = coord.applyUser(c, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        _ = coord.applyUser(d, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilRefreshes(count: 3)
        app.waitUntilDrained(expectedPublished: 3)

        XCTAssertEqual(app.published.map(\.name), ["B", "C", "D"])
        XCTAssertEqual(claims.count, 3)
        app.assertFinalAgreement(coord)
    }

    func testOlderRemoteCannotOverwriteNewerUserPermanently() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilHeld()
        _ = coord.applyUser(c, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        app.releaseHold()
        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)

        XCTAssertEqual(app.uiSelected?.name, "C")
        XCTAssertNotEqual(app.uiSelected?.name, "B")
        app.assertFinalAgreement(coord)
    }

    func testUserSelectionReturnsWithoutWaitingOnApplyQueue() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilHeld()

        let start = Date()
        let tC = coord.applyUser(c, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.05, "user apply-and-submit must not wait on applyQueue")
        XCTAssertEqual(tC.kind, .material)
        XCTAssertEqual(coord.currentAuthoritative, c)

        app.releaseHold()
        app.waitUntilRefreshes(count: 2)
    }

    // MARK: Atomic submission vs reverse caller-return scheduling

    /// Old defect: B classifies first, deschedules before enqueue; C enqueues first.
    /// Corrected design: B is already submitted when apply returns, so a post-return
    /// pause cannot reorder submission.
    func testBSubmittedBeforeCallerPostReturnPause_ThenC_ApplicationIsBThenC() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let bCallerReleased = DispatchSemaphore(value: 0)
        let bApplyReturned = DispatchSemaphore(value: 0)
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            // B apply-and-submit — submission is atomic under lock.
            _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
            // Old gap would have been *before* enqueue; B is already submitted here.
            bApplyReturned.signal()
            // Adversarial: hold the B *caller* before it returns to its invoker.
            _ = bCallerReleased.wait(timeout: .now() + 5)
            group.leave()
        }

        XCTAssertEqual(bApplyReturned.wait(timeout: .now() + 5), .success)
        // At this point B must already be submitted even though B caller is paused.
        XCTAssertEqual(app.submittedNames, ["B"], "B submitted before post-return pause is visible")

        // C classifies/submits while B caller still paused.
        _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(app.submittedNames, ["B", "C"])

        bCallerReleased.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)

        XCTAssertEqual(app.published.map(\.name), ["B", "C"])
        XCTAssertEqual(app.persisted.map(\.name), ["B", "C"])
        XCTAssertEqual(app.refreshes.map(\.1), [1, 2])
        app.assertFinalAgreement(coord)
    }

    func testReverseCallerReturnOrder_SubmissionStillBThenC() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let bStarted = DispatchSemaphore(value: 0)
        let allowBFinish = DispatchSemaphore(value: 0)
        let cReturned = DispatchSemaphore(value: 0)
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            bStarted.signal()
            _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
            // Delay B caller return after atomic submit.
            _ = allowBFinish.wait(timeout: .now() + 5)
            group.leave()
        }

        XCTAssertEqual(bStarted.wait(timeout: .now() + 5), .success)
        // Give B time to enter coordinator first.
        Thread.sleep(forTimeInterval: 0.02)

        group.enter()
        DispatchQueue.global().async {
            _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
            cReturned.signal()
            group.leave()
        }

        XCTAssertEqual(cReturned.wait(timeout: .now() + 5), .success)
        // C's apply returned first among concurrent callers after B held lock first.
        allowBFinish.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)

        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)

        XCTAssertEqual(app.submittedNames, ["B", "C"])
        XCTAssertEqual(app.published.map(\.name), ["B", "C"])
        app.assertFinalAgreement(coord)
    }

    func testThreeTransitions_CoordinatorOrderBCD_CallerReturnOrderDCB() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let d = TransitionFixtures.saved(id: UUID(), name: "D", lat: 34.0, lon: -118.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        // Force coordinator order B→C→D; hold each *caller* after atomic submit.
        let bHold = DispatchSemaphore(value: 0)
        let cHold = DispatchSemaphore(value: 0)
        let dHold = DispatchSemaphore(value: 0)
        let bDone = DispatchSemaphore(value: 0)
        let cDone = DispatchSemaphore(value: 0)
        let dDone = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
            bDone.signal()
            _ = bHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(bDone.wait(timeout: .now() + 5), .success)

        DispatchQueue.global().async {
            _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
            cDone.signal()
            _ = cHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(cDone.wait(timeout: .now() + 5), .success)

        DispatchQueue.global().async {
            _ = coord.applyRemote(d, claimRefresh: { claims.claim() }, submit: app.submit)
            dDone.signal()
            _ = dHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(dDone.wait(timeout: .now() + 5), .success)

        // Reverse caller-return release order D, C, B (must not affect submission).
        dHold.signal()
        cHold.signal()
        bHold.signal()

        app.waitUntilRefreshes(count: 3)
        app.waitUntilDrained(expectedPublished: 3)

        XCTAssertEqual(app.submittedNames, ["B", "C", "D"])
        XCTAssertEqual(app.published.map(\.name), ["B", "C", "D"])
        XCTAssertEqual(app.persisted.map(\.name), ["B", "C", "D"])
        XCTAssertEqual(app.refreshes.map(\.1), [1, 2, 3])
        app.assertFinalAgreement(coord)
        XCTAssertEqual(coord.currentAuthoritative, d)
    }

    func testMixedRemoteUserConcurrent_AdversarialCallerReturn() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let d = TransitionFixtures.saved(id: UUID(), name: "D", lat: 34.0, lon: -118.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let bDone = DispatchSemaphore(value: 0)
        let cDone = DispatchSemaphore(value: 0)
        let dDone = DispatchSemaphore(value: 0)
        let bHold = DispatchSemaphore(value: 0)
        let cHold = DispatchSemaphore(value: 0)
        let dHold = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
            bDone.signal()
            _ = bHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(bDone.wait(timeout: .now() + 5), .success)

        DispatchQueue.global().async {
            _ = coord.applyUser(c, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
            cDone.signal()
            _ = cHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(cDone.wait(timeout: .now() + 5), .success)

        DispatchQueue.global().async {
            _ = coord.applyRemote(d, claimRefresh: { claims.claim() }, submit: app.submit)
            dDone.signal()
            _ = dHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(dDone.wait(timeout: .now() + 5), .success)

        // Adversarial return order D then B then C.
        dHold.signal()
        bHold.signal()
        cHold.signal()

        app.waitUntilRefreshes(count: 3)
        app.waitUntilDrained(expectedPublished: 3)

        XCTAssertEqual(app.submittedNames, ["B", "C", "D"])
        XCTAssertEqual(app.published.map(\.name), ["B", "C", "D"])
        XCTAssertEqual(app.refreshes.map(\.1), [1, 2, 3])
        app.assertFinalAgreement(coord)
    }

    func testUserRemoteUser_ReverseCallerReturn() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let d = TransitionFixtures.saved(id: UUID(), name: "D", lat: 34.0, lon: -118.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let bDone = DispatchSemaphore(value: 0)
        let cDone = DispatchSemaphore(value: 0)
        let dDone = DispatchSemaphore(value: 0)
        let holds = (DispatchSemaphore(value: 0), DispatchSemaphore(value: 0), DispatchSemaphore(value: 0))

        DispatchQueue.global().async {
            _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
            bDone.signal()
            _ = holds.0.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(bDone.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
            cDone.signal()
            _ = holds.1.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(cDone.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            _ = coord.applyUser(d, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
            dDone.signal()
            _ = holds.2.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(dDone.wait(timeout: .now() + 5), .success)

        holds.2.signal()
        holds.1.signal()
        holds.0.signal()

        app.waitUntilRefreshes(count: 3)
        app.waitUntilDrained(expectedPublished: 3)

        XCTAssertEqual(app.published.map(\.name), ["B", "C", "D"])
        XCTAssertEqual(app.sent.map(\.name), ["B", "D"])
        app.assertFinalAgreement(coord)
    }

    func testDuplicateEchoDuringDelayedCallerReturn_OneSubmission() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let bHold = DispatchSemaphore(value: 0)
        let bDone = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
            bDone.signal()
            _ = bHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(bDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(app.submittedNames, ["B"])

        let echo = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(echo.kind, .noOp)
        XCTAssertEqual(app.submittedNames, ["B"])
        XCTAssertEqual(claims.count, 1)

        bHold.signal()
        app.waitUntilRefreshes(count: 1)
        for _ in 0..<50 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        XCTAssertEqual(app.published.count, 1)
        XCTAssertEqual(app.persisted.count, 1)
        XCTAssertEqual(app.refreshes.count, 1)
        XCTAssertEqual(app.sent.count, 1)
    }

    func testRenameThenMaterial_ReverseCallerReturn() {
        let id = UUID()
        let b = TransitionFixtures.saved(id: id, name: "B", lat: 45.5, lon: -122.7)
        let b2 = TransitionFixtures.saved(id: id, name: "B Renamed", lat: 45.5, lon: -122.7)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: b)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let rDone = DispatchSemaphore(value: 0)
        let mDone = DispatchSemaphore(value: 0)
        let rHold = DispatchSemaphore(value: 0)
        let mHold = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = coord.applyRemote(b2, claimRefresh: { claims.claim() }, submit: app.submit)
            rDone.signal()
            _ = rHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(rDone.wait(timeout: .now() + 5), .success)

        DispatchQueue.global().async {
            _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
            mDone.signal()
            _ = mHold.wait(timeout: .now() + 5)
        }
        XCTAssertEqual(mDone.wait(timeout: .now() + 5), .success)

        // Reverse return: material caller first.
        mHold.signal()
        rHold.signal()

        app.waitUntilRefreshes(count: 1)
        app.waitUntilPublished(count: 2)
        for _ in 0..<100 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }

        XCTAssertEqual(app.submittedNames, ["B Renamed", "C"])
        XCTAssertEqual(app.published.map(\.name), ["B Renamed", "C"])
        XCTAssertEqual(app.refreshes.count, 1)
        XCTAssertEqual(app.refreshes.first?.0.name, "C")
        XCTAssertEqual(claims.count, 1)
        app.assertFinalAgreement(coord)
    }

    func testNoOpOrderGap_DoesNotStallApplier() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let t1 = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        let t2 = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        let t3 = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)

        XCTAssertEqual(t1.order, 1)
        XCTAssertEqual(t2.kind, .noOp)
        XCTAssertEqual(t2.order, 2)
        XCTAssertEqual(t3.order, 3)
        XCTAssertEqual(app.submittedOrders, [1, 3], "no-op order 2 not submitted")

        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)

        XCTAssertEqual(app.published.map(\.name), ["B", "C"])
        XCTAssertEqual(app.refreshes.map(\.1), [1, 2])
        app.assertFinalAgreement(coord)
    }

    func testSubmissionIsNonblocking_BlockedApplierDoesNotBlockCoordinator() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let c = TransitionFixtures.saved(name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()
        app.setHoldNextPublication(true)

        // First transition blocks on apply queue execution.
        _ = coord.applyRemote(b, claimRefresh: { claims.claim() }, submit: app.submit)
        app.waitUntilHeld()

        // Second apply-and-submit must return without waiting for B publication.
        let start = Date()
        let tC = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.1, "submit is only queue.async; must not wait for publication")
        XCTAssertEqual(tC.kind, .material)
        XCTAssertEqual(app.submittedNames, ["B", "C"])
        // Application of C has not completed (B still held).
        XCTAssertEqual(app.published.count, 0)

        app.releaseHold()
        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)
        XCTAssertEqual(app.published.map(\.name), ["B", "C"])
    }

    func testSubmitDoesNotRunSideEffectsInline_BeforeApplyReturns() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        // Hold so application cannot complete before we check post-return snapshots.
        app.setHoldNextPublication(true)

        var sideEffectsDuringSubmit = false
        let t = coord.applyRemote(
            b,
            claimRefresh: { claims.claim() },
            submit: { transition in
                // Inside coordinator lock: only nonblocking enqueue.
                app.submit(transition)
                // Publication / persistence / refresh must not run *inline* on this thread.
                // (Apply queue may have begun async work, but publish is held.)
                if !app.published.isEmpty || !app.persisted.isEmpty || !app.refreshes.isEmpty {
                    sideEffectsDuringSubmit = true
                }
            }
        )
        XCTAssertFalse(sideEffectsDuringSubmit, "publish/persist/refresh must not run inline in submit")
        XCTAssertEqual(t.kind, .material)
        app.waitUntilHeld()
        XCTAssertTrue(app.published.isEmpty)
        app.releaseHold()
        app.waitUntilRefreshes(count: 1)
    }

    func testProductionCallSitesDoNotSplitApplyAndEnqueue() {
        // Source-level audit of WatchLocationManager production paths.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/...
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let managerPath = root
            .appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift")
        let source = try! String(contentsOf: managerPath, encoding: .utf8)

        // Strong capture for synchronous submit under coordinator lock (guaranteed enqueue).
        XCTAssertTrue(
            source.contains("submit: { [self] transition in"),
            "production must pass strong-self submit into applyRemote/applyUser"
        )
        XCTAssertTrue(source.contains("submitToApplier"), "production uses submitToApplier under submit")
        // Forbidden split: capture transition then schedule later outside submit.
        XCTAssertFalse(
            source.contains("scheduleApplication(of: transition)"),
            "split scheduleApplication after apply must be gone"
        )
        XCTAssertFalse(source.contains("publicationAlreadyDone"))
        // Transition apply only inside already-inside-ingress helpers.
        XCTAssertTrue(source.contains("transitionCoordinator.applyRemote("))
        XCTAssertTrue(source.contains("transitionCoordinator.applyUser("))
        XCTAssertTrue(source.contains("applyRemoteSelectionAlreadyInsideIngress"))
        XCTAssertTrue(source.contains("applyUserSelectionAlreadyInsideIngress"))
        // Shared ingress for all selected-location entry.
        XCTAssertTrue(source.contains("WatchSelectedLocationIngressCoordinator"))
        XCTAssertTrue(source.contains("selectedLocationIngress.perform"))
        // Selection reserved at list acceptance, not delayed list application.
        XCTAssertTrue(source.contains("prepareSelectionForAcceptedListResult"))
    }
}


// MARK: - Runtime cached restore (failed locations request)

final class WatchSelectedLocationRuntimeRestoreTests: XCTestCase {

    func testRestoreIfUninitialized_WhenNil_RestoresWithClaimAndSubmit() {
        let a = TransitionFixtures.saved(name: "A", lat: 45.5, lon: -122.7)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: nil)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let t = coord.restoreIfUninitialized(
            a,
            claimRefresh: { claims.claim() },
            submit: app.submit
        )
        XCTAssertNotNil(t)
        XCTAssertEqual(t?.kind, .material)
        XCTAssertEqual(claims.count, 1)
        XCTAssertNotNil(t?.refreshToken)
        XCTAssertFalse(t?.sendToPhone ?? true)
        XCTAssertEqual(coord.currentAuthoritative, a)

        app.waitUntilRefreshes(count: 1)
        app.waitUntilDrained(expectedPublished: 1)
        XCTAssertEqual(app.published, [a])
        XCTAssertEqual(app.sent.count, 0, "runtime restore must not phone-echo")
        app.assertFinalAgreement(coord)
    }

    func testRestoreIfUninitialized_WhenAuthorityExists_IsSuppressed() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let t = coord.restoreIfUninitialized(
            b,
            claimRefresh: { claims.claim() },
            submit: app.submit
        )
        XCTAssertNil(t)
        XCTAssertEqual(claims.count, 0)
        XCTAssertTrue(app.submittedNames.isEmpty)
        XCTAssertEqual(coord.currentAuthoritative, a)

        for _ in 0..<30 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        XCTAssertTrue(app.published.isEmpty)
        XCTAssertTrue(app.refreshes.isEmpty)
    }

    func testUserSelectionDuringFailedRequest_AuthorityRemainsB() {
        // Seed A, user selects B (atomic submit), then failed-request restore tries A.
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let user = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(user.kind, .material)
        XCTAssertEqual(claims.count, 1)
        let bToken = user.refreshToken?.sequence

        // Old request fails with cached A — restore must not roll back.
        let restored = coord.restoreIfUninitialized(
            a,
            claimRefresh: { claims.claim() },
            submit: app.submit
        )
        XCTAssertNil(restored, "restore suppressed when authority is B")
        XCTAssertEqual(claims.count, 1, "no fallback claim")
        XCTAssertEqual(coord.currentAuthoritative, b)

        app.waitUntilRefreshes(count: 1)
        app.waitUntilDrained(expectedPublished: 1)
        XCTAssertEqual(app.published.map(\.name), ["B"])
        XCTAssertEqual(app.refreshes.map(\.1), [bToken!])
        app.assertFinalAgreement(coord)
    }

    func testRemoteSelectionDuringFailedRequest_AuthorityRemainsC() {
        let a = TransitionFixtures.saved(name: "A")
        let c = TransitionFixtures.saved(id: UUID(), name: "C", lat: 40.7, lon: -74.0)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        _ = coord.applyRemote(c, claimRefresh: { claims.claim() }, submit: app.submit)
        let restored = coord.restoreIfUninitialized(
            a,
            claimRefresh: { claims.claim() },
            submit: app.submit
        )
        XCTAssertNil(restored)
        XCTAssertEqual(coord.currentAuthoritative, c)
        XCTAssertEqual(claims.count, 1)

        app.waitUntilRefreshes(count: 1)
        app.waitUntilDrained(expectedPublished: 1)
        XCTAssertEqual(app.published.map(\.name), ["C"])
        app.assertFinalAgreement(coord)
    }

    func testRestoreThenUserB_FinalIsB() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: nil)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let r = coord.restoreIfUninitialized(a, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(r?.kind, .material)
        let u = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(u.kind, .material)
        XCTAssertEqual(claims.count, 2)

        app.waitUntilRefreshes(count: 2)
        app.waitUntilDrained(expectedPublished: 2)
        XCTAssertEqual(app.published.map(\.name), ["A", "B"])
        app.assertFinalAgreement(coord)
        XCTAssertEqual(coord.currentAuthoritative, b)
    }

    func testUserBThenRestoreAttempt_RestoreSuppressedFinalB() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: nil)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        let r = coord.restoreIfUninitialized(a, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertNil(r)
        XCTAssertEqual(claims.count, 1)
        XCTAssertEqual(coord.currentAuthoritative, b)

        app.waitUntilRefreshes(count: 1)
        app.waitUntilDrained(expectedPublished: 1)
        XCTAssertEqual(app.published.map(\.name), ["B"])
        app.assertFinalAgreement(coord)
    }

    func testConcurrentRestoreVsUser_EitherLockOrderAgrees() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(id: UUID(), name: "B", lat: 47.6, lon: -122.3)
        let claims = ClaimCounter()

        // Ordering 1: restore first under lock, then user.
        do {
            let coord = WatchSelectedLocationTransitionCoordinator(seed: nil)
            let app = ProductionApplierHarness()
            let restoreDone = DispatchSemaphore(value: 0)
            let userDone = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                _ = coord.restoreIfUninitialized(a, claimRefresh: { claims.claim() }, submit: app.submit)
                restoreDone.signal()
            }
            XCTAssertEqual(restoreDone.wait(timeout: .now() + 5), .success)

            DispatchQueue.global().async {
                _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
                userDone.signal()
            }
            XCTAssertEqual(userDone.wait(timeout: .now() + 5), .success)

            app.waitUntilRefreshes(count: 2)
            app.waitUntilDrained(expectedPublished: 2)
            XCTAssertEqual(app.published.map(\.name), ["A", "B"])
            app.assertFinalAgreement(coord)
        }

        // Ordering 2: user first, then restore suppressed.
        do {
            let coord = WatchSelectedLocationTransitionCoordinator(seed: nil)
            let app = ProductionApplierHarness()
            let localClaims = ClaimCounter()
            _ = coord.applyUser(b, sendToPhone: true, claimRefresh: { localClaims.claim() }, submit: app.submit)
            let r = coord.restoreIfUninitialized(a, claimRefresh: { localClaims.claim() }, submit: app.submit)
            XCTAssertNil(r)
            app.waitUntilRefreshes(count: 1)
            app.waitUntilDrained(expectedPublished: 1)
            XCTAssertEqual(app.published.map(\.name), ["B"])
            app.assertFinalAgreement(coord)
        }
    }

    func testFailedRequestDoesNotClaimWhenAuthorityExists() {
        let a = TransitionFixtures.saved(name: "A")
        let b = TransitionFixtures.saved(name: "B", lat: 47.6, lon: -122.3)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let tB = coord.applyUser(b, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertNotNil(tB.refreshToken)

        let before = claims.count
        _ = coord.restoreIfUninitialized(a, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertEqual(claims.count, before, "fallback must not claim")
        // B refresh remains the only one submitted.
        app.waitUntilRefreshes(count: 1)
        XCTAssertEqual(app.refreshes.count, 1)
    }

    func testCurrentLocationDuringFailedRequest_RemainsSelected() {
        let a = TransitionFixtures.saved(name: "A")
        let cl = TransitionFixtures.currentPlaceholder()
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        _ = coord.applyUser(cl, sendToPhone: true, claimRefresh: { claims.claim() }, submit: app.submit)
        let r = coord.restoreIfUninitialized(a, claimRefresh: { claims.claim() }, submit: app.submit)
        XCTAssertNil(r)
        XCTAssertEqual(coord.currentAuthoritative?.source, .currentGPS)
        app.waitUntilRefreshes(count: 1)
        app.waitUntilDrained(expectedPublished: 1)
        XCTAssertEqual(app.uiSelected?.source, .currentGPS)
        app.assertFinalAgreement(coord)
    }

    func testNilAuthorityCachedCurrentLocationPlaceholder() {
        let cl = TransitionFixtures.currentPlaceholder()
        let coord = WatchSelectedLocationTransitionCoordinator(seed: nil)
        let claims = ClaimCounter()
        let app = ProductionApplierHarness()

        let t = coord.restoreIfUninitialized(cl, claimRefresh: { claims.claim() }, submit: app.submit)
        // From nil → CL placeholder is material (needs refresh).
        XCTAssertEqual(t?.kind, .material)
        XCTAssertEqual(claims.count, 1)
        XCTAssertFalse(t?.sendToPhone ?? true)

        app.waitUntilRefreshes(count: 1)
        app.waitUntilDrained(expectedPublished: 1)
        XCTAssertEqual(app.sent.count, 0)
        XCTAssertEqual(app.uiSelected?.source, .currentGPS)
        app.assertFinalAgreement(coord)
    }

    func testRuntimeSeedSourceAudit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let managerPath = root.appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift")
        let source = try String(contentsOf: managerPath, encoding: .utf8)

        XCTAssertFalse(
            source.contains("transitionCoordinator.seed("),
            "runtime must not call seed — only init(seed:) bootstrap"
        )
        XCTAssertTrue(
            source.contains("WatchSelectedLocationTransitionCoordinator(seed:"),
            "startup still seeds via initializer"
        )
        XCTAssertTrue(source.contains("restoreIfUninitialized"))
        XCTAssertTrue(source.contains("applyRestoreAlreadyInsideIngress"))
        XCTAssertTrue(source.contains("selectedLocationIngress"))
    }

    func testDirectSelectedLocationWriteAudit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let managerPath = root.appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift")
        let source = try String(contentsOf: managerPath, encoding: .utf8)

        // Collect assignment lines to selectedLocation
        let lines = source.components(separatedBy: "\n")
        let assigns = lines.filter { $0.contains("selectedLocation =") }
        XCTAssertFalse(assigns.isEmpty)

        for line in assigns {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let allowed =
                trimmed.contains("self.selectedLocation = storedSelected")
                || trimmed.contains("self?.selectedLocation = location")
            XCTAssertTrue(
                allowed,
                "unexpected selectedLocation assignment: \(trimmed)"
            )
        }
        // Catch path must not assign cached selection.
        XCTAssertFalse(source.contains("self.selectedLocation = cachedSelected"))
    }
}
