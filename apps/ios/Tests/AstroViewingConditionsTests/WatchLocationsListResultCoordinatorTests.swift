@testable import SharedCode
import XCTest

// MARK: - Fixtures

private enum ListFixtures {
    static func cached(_ name: String, lat: Double = 45.0, lon: Double = -122.0) -> CachedLocation {
        CachedLocation(id: UUID(), name: name, latitude: lat, longitude: lon)
    }

    static func selected(
        id: UUID = UUID(),
        name: String,
        lat: Double = 45.0,
        lon: Double = -122.0
    ) -> SelectedLocation {
        SelectedLocation(source: .saved, id: id, name: name, latitude: lat, longitude: lon)
    }

    static func currentPlaceholder() -> SelectedLocation {
        SelectedLocation(source: .currentGPS, name: "Current Location", latitude: 0, longitude: 0)
    }
}

private final class ClaimCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var next: UInt64 = 1
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func claim() -> WatchConditionsLiveUpdateToken {
        lock.lock()
        defer { lock.unlock() }
        let t = WatchConditionsLiveUpdateToken(sequence: next)
        next &+= 1
        _count += 1
        return t
    }
}

// MARK: - List-only harness (production list coordinator + applier)

private final class ListResultHarness: @unchecked Sendable {
    let coordinator = WatchLocationsListResultCoordinator()
    let applier = WatchLocationsListResultApplier(
        label: "test.locations.list.apply.\(UUID().uuidString)"
    )

    private let lock = NSLock()
    private var _persisted: [[CachedLocation]] = []
    private var _published: [[CachedLocation]] = []
    private var _loadingClears = 0
    private var _prepareCalls: [WatchLocationsListResultKind] = []
    private var _accepted: [WatchLocationsListAcceptedResult] = []
    private var _applications = 0
    private var _isLoading = false

    private var holdBeforeApplication = false
    private let holdEntered = DispatchSemaphore(value: 0)
    private let holdRelease = DispatchSemaphore(value: 0)

    var persisted: [[CachedLocation]] {
        lock.lock(); defer { lock.unlock() }
        return _persisted
    }
    var published: [[CachedLocation]] {
        lock.lock(); defer { lock.unlock() }
        return _published
    }
    var loadingClears: Int {
        lock.lock(); defer { lock.unlock() }
        return _loadingClears
    }
    var prepareCalls: [WatchLocationsListResultKind] {
        lock.lock(); defer { lock.unlock() }
        return _prepareCalls
    }
    var accepted: [WatchLocationsListAcceptedResult] {
        lock.lock(); defer { lock.unlock() }
        return _accepted
    }
    var applications: Int {
        lock.lock(); defer { lock.unlock() }
        return _applications
    }
    var isLoading: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isLoading
    }

    init() {
        applier.beforeApplication = { [weak self] _ in
            guard let self else { return }
            if self.holdBeforeApplication {
                self.holdBeforeApplication = false
                self.holdEntered.signal()
                self.holdRelease.wait()
            }
            self.lock.lock()
            self._applications += 1
            self.lock.unlock()
        }
    }

    func setHoldNextApplication(_ value: Bool) {
        holdBeforeApplication = value
    }

    func waitUntilHeld() {
        _ = holdEntered.wait(timeout: .now() + 5)
    }

    func releaseHold() {
        holdRelease.signal()
    }

    func setLoading(_ value: Bool) {
        lock.lock()
        _isLoading = value
        lock.unlock()
    }

    func prepare(_ kind: WatchLocationsListResultKind) {
        lock.lock()
        _prepareCalls.append(kind)
        lock.unlock()
    }

    func submit(_ result: WatchLocationsListAcceptedResult) {
        lock.lock()
        _accepted.append(result)
        lock.unlock()

        applier.enqueue(
            result,
            persistList: { [weak self] locations in
                self?.lock.lock()
                self?._persisted.append(locations)
                self?.lock.unlock()
            },
            publishListOnMain: { [weak self] accepted in
                guard let self else { return }
                self.lock.lock()
                self._published.append(accepted.kind.locationsToPublish)
                self.lock.unlock()
                _ = self.coordinator.clearLoadingIfOwner(accepted.epoch) {
                    self.lock.lock()
                    self._loadingClears += 1
                    self._isLoading = false
                    self.lock.unlock()
                }
            }
        )
    }

    @discardableResult
    func acceptSuccess(
        epoch: UInt64,
        locations: [CachedLocation],
        selected: SelectedLocation?
    ) -> WatchLocationsListAcceptedResult? {
        coordinator.acceptIfCurrent(
            epoch: epoch,
            kind: .success(locations: locations, selected: selected),
            prepareSelection: prepare,
            submit: submit
        )
    }

    @discardableResult
    func acceptFailure(
        epoch: UInt64,
        cached: [CachedLocation],
        cachedSelected: SelectedLocation?
    ) -> WatchLocationsListAcceptedResult? {
        coordinator.acceptIfCurrent(
            epoch: epoch,
            kind: .failure(cachedLocations: cached, cachedSelected: cachedSelected),
            prepareSelection: prepare,
            submit: submit
        )
    }

    @discardableResult
    func acceptPush(
        locations: [CachedLocation],
        selected: SelectedLocation?
    ) -> WatchLocationsListAcceptedResult {
        coordinator.acceptConnectivityPush(
            locations: locations,
            selected: selected,
            prepareSelection: prepare,
            submit: submit
        )
    }

    func waitUntilApplications(_ count: Int) {
        for _ in 0..<10_000 {
            if applications >= count { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func waitUntilPublished(_ count: Int) {
        for _ in 0..<10_000 {
            if published.count >= count { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func drain() {
        for _ in 0..<200 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }
}

// MARK: - Integrated list + selected-location harness

/// Production list + selection + **shared ingress** coordinators/appliers.
private final class IntegratedListSelectionHarness: @unchecked Sendable {
    let listCoordinator = WatchLocationsListResultCoordinator()
    let listApplier = WatchLocationsListResultApplier(
        label: "test.integrated.list.\(UUID().uuidString)"
    )
    let selectionCoordinator: WatchSelectedLocationTransitionCoordinator
    let selectionApplier = WatchSelectedLocationTransitionApplier(
        label: "test.integrated.sel.\(UUID().uuidString)"
    )
    /// Shared selected-location ingress — same authority as production.
    let ingress = WatchSelectedLocationIngressCoordinator()
    let claims = ClaimCounter()

    private let lock = NSLock()
    private var _listPublished: [[CachedLocation]] = []
    private var _listPersisted: [[CachedLocation]] = []
    private var _selectedPublished: [SelectedLocation] = []
    private var _selectedPersisted: [SelectedLocation] = []
    private var _selectedRefreshes: [(String, UInt64)] = []
    private var _isLoading = false
    private var _loadingClears = 0
    private var _prepareCount = 0
    private var _ingressEntries = 0

    private var holdList = false
    private let listHoldEntered = DispatchSemaphore(value: 0)
    private let listHoldRelease = DispatchSemaphore(value: 0)

    private var holdSelection = false
    private let selHoldEntered = DispatchSemaphore(value: 0)
    private let selHoldRelease = DispatchSemaphore(value: 0)

    private var holdIngress = false
    private let ingressHoldEntered = DispatchSemaphore(value: 0)
    private let ingressHoldRelease = DispatchSemaphore(value: 0)

    var listPublished: [[CachedLocation]] {
        lock.lock(); defer { lock.unlock() }
        return _listPublished
    }
    var selectedPublished: [SelectedLocation] {
        lock.lock(); defer { lock.unlock() }
        return _selectedPublished
    }
    var selectedPersisted: [SelectedLocation] {
        lock.lock(); defer { lock.unlock() }
        return _selectedPersisted
    }
    var selectedRefreshes: [(String, UInt64)] {
        lock.lock(); defer { lock.unlock() }
        return _selectedRefreshes
    }
    var isLoading: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isLoading
    }
    var loadingClears: Int {
        lock.lock(); defer { lock.unlock() }
        return _loadingClears
    }
    var prepareCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _prepareCount
    }
    var ingressEntries: Int {
        lock.lock(); defer { lock.unlock() }
        return _ingressEntries
    }

    init(seed: SelectedLocation?) {
        selectionCoordinator = WatchSelectedLocationTransitionCoordinator(seed: seed)
        listApplier.beforeApplication = { [weak self] _ in
            guard let self else { return }
            if self.holdList {
                self.holdList = false
                self.listHoldEntered.signal()
                self.listHoldRelease.wait()
            }
        }
        selectionApplier.beforePublication = { [weak self] _ in
            guard let self else { return }
            if self.holdSelection {
                self.holdSelection = false
                self.selHoldEntered.signal()
                self.selHoldRelease.wait()
            }
        }
        ingress.beforeBody = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self._ingressEntries += 1
            self.lock.unlock()
            if self.holdIngress {
                self.holdIngress = false
                self.ingressHoldEntered.signal()
                self.ingressHoldRelease.wait()
            }
        }
    }

    func setHoldList(_ v: Bool) { holdList = v }
    func setHoldSelection(_ v: Bool) { holdSelection = v }
    func setHoldIngress(_ v: Bool) { holdIngress = v }
    func waitListHeld() { _ = listHoldEntered.wait(timeout: .now() + 5) }
    func releaseList() { listHoldRelease.signal() }
    func waitSelHeld() { _ = selHoldEntered.wait(timeout: .now() + 5) }
    func releaseSel() { selHoldRelease.signal() }
    func waitIngressHeld() { _ = ingressHoldEntered.wait(timeout: .now() + 5) }
    func releaseIngress() { ingressHoldRelease.signal() }

    func setLoading(_ v: Bool) {
        lock.lock(); _isLoading = v; lock.unlock()
    }

    /// List-result prepareSelection: enters shared ingress (production shape).
    private func prepareSelection(_ kind: WatchLocationsListResultKind) {
        lock.lock(); _prepareCount += 1; lock.unlock()
        ingress.perform {
            if let remote = kind.remoteSelected {
                applyRemoteAlreadyInsideIngress(remote)
            } else if let cached = kind.failureCachedSelected {
                applyRestoreAlreadyInsideIngress(cached)
            }
        }
    }

    private func submitList(_ accepted: WatchLocationsListAcceptedResult) {
        listApplier.enqueue(
            accepted,
            persistList: { [weak self] locations in
                self?.lock.lock()
                self?._listPersisted.append(locations)
                self?.lock.unlock()
            },
            publishListOnMain: { [weak self] accepted in
                guard let self else { return }
                self.lock.lock()
                self._listPublished.append(accepted.kind.locationsToPublish)
                self.lock.unlock()
                _ = self.listCoordinator.clearLoadingIfOwner(accepted.epoch) {
                    self.lock.lock()
                    self._loadingClears += 1
                    self._isLoading = false
                    self.lock.unlock()
                }
            }
        )
    }

    private func submitSelection(_ transition: WatchSelectedLocationTransition) {
        selectionApplier.enqueue(
            transition,
            publish: { [weak self] location in
                self?.lock.lock()
                self?._selectedPublished.append(location)
                self?.lock.unlock()
            },
            persist: { [weak self] location in
                self?.lock.lock()
                self?._selectedPersisted.append(location)
                self?.lock.unlock()
            },
            sendToPhone: { _ in },
            startRefresh: { [weak self] location, token in
                self?.lock.lock()
                self?._selectedRefreshes.append((location.name, token.sequence))
                self?.lock.unlock()
            }
        )
    }

    /// Direct remote path: enters shared ingress.
    func applyRemote(_ incoming: SelectedLocation) {
        ingress.perform {
            applyRemoteAlreadyInsideIngress(incoming)
        }
    }

    /// Direct user path: enters shared ingress.
    func applyUser(_ incoming: SelectedLocation) {
        ingress.perform {
            applyUserAlreadyInsideIngress(incoming)
        }
    }

    private func applyRemoteAlreadyInsideIngress(_ incoming: SelectedLocation) {
        selectionCoordinator.applyRemote(
            incoming,
            claimRefresh: { [claims] in claims.claim() },
            submit: { [self] t in self.submitSelection(t) }
        )
    }

    private func applyUserAlreadyInsideIngress(_ incoming: SelectedLocation) {
        selectionCoordinator.applyUser(
            incoming,
            sendToPhone: true,
            claimRefresh: { [claims] in claims.claim() },
            submit: { [self] t in self.submitSelection(t) }
        )
    }

    private func applyRestoreAlreadyInsideIngress(_ incoming: SelectedLocation) {
        selectionCoordinator.restoreIfUninitialized(
            incoming,
            claimRefresh: { [claims] in claims.claim() },
            submit: { [self] t in self.submitSelection(t) }
        )
    }

    @discardableResult
    func acceptPush(locations: [CachedLocation], selected: SelectedLocation?) -> WatchLocationsListAcceptedResult {
        listCoordinator.acceptConnectivityPush(
            locations: locations,
            selected: selected,
            prepareSelection: { [self] kind in self.prepareSelection(kind) },
            submit: { [self] a in self.submitList(a) }
        )
    }

    @discardableResult
    func acceptSuccess(
        epoch: UInt64,
        locations: [CachedLocation],
        selected: SelectedLocation?
    ) -> WatchLocationsListAcceptedResult? {
        listCoordinator.acceptIfCurrent(
            epoch: epoch,
            kind: .success(locations: locations, selected: selected),
            prepareSelection: { [self] kind in self.prepareSelection(kind) },
            submit: { [self] a in self.submitList(a) }
        )
    }

    @discardableResult
    func acceptFailure(
        epoch: UInt64,
        cached: [CachedLocation],
        cachedSelected: SelectedLocation?
    ) -> WatchLocationsListAcceptedResult? {
        listCoordinator.acceptIfCurrent(
            epoch: epoch,
            kind: .failure(cachedLocations: cached, cachedSelected: cachedSelected),
            prepareSelection: { [self] kind in self.prepareSelection(kind) },
            submit: { [self] a in self.submitList(a) }
        )
    }

    func beginRefresh() -> UInt64 {
        let e = listCoordinator.beginRefresh()
        setLoading(true)
        return e
    }

    func waitSelectedPublished(_ n: Int) {
        for _ in 0..<10_000 {
            if selectedPublished.count >= n { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func waitListPublished(_ n: Int) {
        for _ in 0..<10_000 {
            if listPublished.count >= n { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func drain() {
        for _ in 0..<300 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
    }

    func assertSelectionFinal(_ expected: SelectedLocation, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(selectionCoordinator.currentAuthoritative, expected, file: file, line: line)
        XCTAssertEqual(selectedPublished.last, expected, file: file, line: line)
        XCTAssertEqual(selectedPersisted.last, expected, file: file, line: line)
    }
}

// MARK: - List result baseline (updated API)

final class WatchLocationsListResultCoordinatorTests: XCTestCase {

    func testStaleSuccessNeverAccepted_ZeroEffects() {
        let h = ListResultHarness()
        h.setLoading(true)
        let e1 = h.coordinator.beginRefresh()
        _ = h.coordinator.beginRefresh()

        XCTAssertNil(h.acceptSuccess(
            epoch: e1,
            locations: [ListFixtures.cached("OLD")],
            selected: ListFixtures.selected(name: "OLD")
        ))
        h.drain()
        XCTAssertEqual(h.applications, 0)
        XCTAssertTrue(h.persisted.isEmpty)
        XCTAssertTrue(h.published.isEmpty)
        XCTAssertTrue(h.prepareCalls.isEmpty)
        XCTAssertEqual(h.loadingClears, 0)
        XCTAssertTrue(h.isLoading)
    }

    func testStaleFailureNeverAccepted_ZeroEffects() {
        let h = ListResultHarness()
        h.setLoading(true)
        let e1 = h.coordinator.beginRefresh()
        _ = h.coordinator.beginRefresh()
        XCTAssertNil(h.acceptFailure(
            epoch: e1,
            cached: [ListFixtures.cached("CACHE")],
            cachedSelected: ListFixtures.selected(name: "CACHE")
        ))
        h.drain()
        XCTAssertTrue(h.prepareCalls.isEmpty)
        XCTAssertEqual(h.loadingClears, 0)
    }

    func testConnectivityPushInvalidatesPendingRefreshSuccess() {
        let h = ListResultHarness()
        h.setLoading(true)
        let e1 = h.coordinator.beginRefresh()
        _ = h.acceptPush(
            locations: [ListFixtures.cached("PUSH")],
            selected: ListFixtures.selected(name: "PUSH")
        )
        XCTAssertNil(h.acceptSuccess(
            epoch: e1,
            locations: [ListFixtures.cached("REFRESH")],
            selected: ListFixtures.selected(name: "REFRESH")
        ))
        h.waitUntilPublished(1)
        h.drain()
        XCTAssertEqual(h.persisted.first?.first?.name, "PUSH")
        XCTAssertEqual(h.loadingClears, 1)
    }

    func testQueuedPushThenNewerRefresh_FinalIsRefresh() {
        let h = ListResultHarness()
        h.setHoldNextApplication(true)
        h.setLoading(true)
        _ = h.acceptPush(
            locations: [ListFixtures.cached("PUSH")],
            selected: ListFixtures.selected(name: "PUSH")
        )
        h.waitUntilHeld()
        let e2 = h.coordinator.beginRefresh()
        h.setLoading(true)
        XCTAssertNotNil(h.acceptSuccess(
            epoch: e2,
            locations: [ListFixtures.cached("REFRESH")],
            selected: ListFixtures.selected(name: "REFRESH")
        ))
        h.releaseHold()
        h.waitUntilApplications(2)
        h.waitUntilPublished(2)
        h.drain()
        XCTAssertEqual(h.published.map { $0.first?.name }, ["PUSH", "REFRESH"])
    }

    func testPrepareSelectionInvokedAtAcceptance_BeforeListApply() {
        let h = ListResultHarness()
        h.setHoldNextApplication(true)
        let e1 = h.coordinator.beginRefresh()
        h.setLoading(true)
        let accepted = h.acceptSuccess(
            epoch: e1,
            locations: [ListFixtures.cached("A")],
            selected: ListFixtures.selected(name: "A")
        )
        XCTAssertNotNil(accepted)
        // Prepare ran at accept, list still held.
        XCTAssertEqual(h.prepareCalls.count, 1)
        XCTAssertEqual(h.applications, 0)
        h.waitUntilHeld()
        h.releaseHold()
        h.waitUntilApplications(1)
        h.drain()
    }

    func testLoadingOwnership_AcceptedOldCannotClearNewerRefresh() {
        let h = ListResultHarness()
        h.setHoldNextApplication(true)
        let e1 = h.coordinator.beginRefresh()
        h.setLoading(true)
        XCTAssertNotNil(h.acceptSuccess(
            epoch: e1,
            locations: [ListFixtures.cached("A")],
            selected: nil
        ))
        h.waitUntilHeld()

        // Newer refresh claims loading owner.
        let e2 = h.coordinator.beginRefresh()
        h.setLoading(true)
        XCTAssertEqual(h.coordinator.currentLoadingOwner, e2)
        XCTAssertTrue(h.isLoading)

        h.releaseHold()
        h.waitUntilPublished(1)
        h.drain()

        // A published list but must not clear B's loading.
        XCTAssertEqual(h.published.first?.first?.name, "A")
        XCTAssertEqual(h.loadingClears, 0)
        XCTAssertTrue(h.isLoading)

        XCTAssertNotNil(h.acceptSuccess(
            epoch: e2,
            locations: [ListFixtures.cached("B")],
            selected: nil
        ))
        h.waitUntilPublished(2)
        h.drain()
        XCTAssertEqual(h.loadingClears, 1)
        XCTAssertFalse(h.isLoading)
    }

    func testConnectivityPushClaimsLoadingOwnerAndClears() {
        let h = ListResultHarness()
        _ = h.coordinator.beginRefresh()
        h.setLoading(true)
        _ = h.acceptPush(locations: [ListFixtures.cached("P")], selected: nil)
        h.waitUntilPublished(1)
        h.drain()
        XCTAssertEqual(h.loadingClears, 1)
        XCTAssertFalse(h.isLoading)
    }

    func testPersistenceOrdering_AcceptedAThenB() {
        let h = ListResultHarness()
        let e1 = h.coordinator.beginRefresh()
        XCTAssertNotNil(h.acceptSuccess(epoch: e1, locations: [ListFixtures.cached("A")], selected: nil))
        let e2 = h.coordinator.beginRefresh()
        XCTAssertNotNil(h.acceptSuccess(epoch: e2, locations: [ListFixtures.cached("B")], selected: nil))
        h.waitUntilApplications(2)
        h.drain()
        XCTAssertEqual(h.persisted.map { $0.first?.name }, ["A", "B"])
    }

    func testAcceptIsNonblocking_WhileApplierHeld() {
        let h = ListResultHarness()
        h.setHoldNextApplication(true)
        let e1 = h.coordinator.beginRefresh()
        XCTAssertNotNil(h.acceptSuccess(epoch: e1, locations: [ListFixtures.cached("A")], selected: nil))
        h.waitUntilHeld()
        let e2 = h.coordinator.beginRefresh()
        let start = Date()
        let a2 = h.acceptSuccess(epoch: e2, locations: [ListFixtures.cached("B")], selected: nil)
        XCTAssertNotNil(a2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        h.releaseHold()
        h.waitUntilApplications(2)
        h.drain()
    }

    func testAtomicLoadingOwnerMutation_OldClearAfterNewOwner() {
        let coord = WatchLocationsListResultCoordinator()
        let e1 = coord.beginRefresh()
        var cleared = false
        // New owner before clear attempt.
        _ = coord.beginRefresh()
        let ok = coord.clearLoadingIfOwner(e1) { cleared = true }
        XCTAssertFalse(ok)
        XCTAssertFalse(cleared)
    }

    func testAtomicLoadingOwnerMutation_OwnerClears() {
        let coord = WatchLocationsListResultCoordinator()
        let e1 = coord.beginRefresh()
        var cleared = false
        let ok = coord.clearLoadingIfOwner(e1) { cleared = true }
        XCTAssertTrue(ok)
        XCTAssertTrue(cleared)
    }

    func testProductionManagerSourceAudits() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = try String(
            contentsOf: root.appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(manager.contains("prepareSelectionForAcceptedListResult"))
        XCTAssertTrue(manager.contains("beginRefresh()"))
        XCTAssertTrue(manager.contains("clearLoadingIfOwner"))
        XCTAssertTrue(manager.contains("WatchSelectedLocationIngressCoordinator"))
        XCTAssertTrue(manager.contains("selectedLocationIngress"))
        XCTAssertTrue(manager.contains("ingressRemoteSelection"))
        XCTAssertTrue(manager.contains("ingressUserSelection"))
        XCTAssertTrue(manager.contains("applyRemoteSelectionAlreadyInsideIngress"))
        XCTAssertTrue(manager.contains("applyUserSelectionAlreadyInsideIngress"))
        XCTAssertTrue(manager.contains("applyRestoreAlreadyInsideIngress"))
        // Selection must not be deferred to list application callbacks.
        XCTAssertFalse(manager.contains("applySelected:"))
        XCTAssertFalse(manager.contains("restoreSelectedIfNeeded:"))
        // No check-only then await clear pattern.
        XCTAssertFalse(manager.contains("isCurrent("))
        XCTAssertFalse(manager.contains("WatchLocationsListRequestEpoch"))
        // Guaranteed submit uses strong self in accept paths.
        XCTAssertTrue(manager.contains("prepareSelection: { [self]"))
        XCTAssertTrue(manager.contains("submit: { [self]"))
        XCTAssertFalse(manager.contains("transitionCoordinator.seed("))
        // Transition apply only inside already-inside-ingress helpers.
        XCTAssertFalse(manager.contains("private func handleRemoteSelection"))
        XCTAssertFalse(manager.contains("private func handleUserSelection"))
    }

    func testNoCheckOnlyEpochTypeRemains() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/SharedCode/Core/Services/WatchLocationsListRequestEpoch.swift"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }
}

// MARK: - Integrated cross-state-machine ordering

final class WatchLocationsListSelectionOrderingTests: XCTestCase {

    func testAcceptedPushBDelayedThenUserC_SelectionOrderBThenC() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldList(true)

        _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
        // B reserved immediately at acceptance.
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)
        XCTAssertEqual(h.claims.count, 1)
        h.waitListHeld()

        h.applyUser(c)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, c)
        XCTAssertEqual(h.claims.count, 2)

        h.releaseList()
        h.waitSelectedPublished(2)
        h.waitListPublished(1)
        h.drain()

        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
        h.assertSelectionFinal(c)
        XCTAssertEqual(h.listPublished.last?.first?.name, "B")
    }

    func testAcceptedRefreshSuccessBDelayedThenUserC() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldList(true)
        let e = h.beginRefresh()
        XCTAssertNotNil(h.acceptSuccess(
            epoch: e,
            locations: [ListFixtures.cached("B")],
            selected: b
        ))
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)
        h.waitListHeld()
        h.applyUser(c)
        h.releaseList()
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
        h.assertSelectionFinal(c)
    }

    func testAcceptedListBDelayedThenStandaloneRemoteC() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldList(true)
        _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)
        h.waitListHeld()
        h.applyRemote(c)
        h.releaseList()
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
        h.assertSelectionFinal(c)
    }

    func testAcceptedFailureRestoreAThenUserB() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let h = IntegratedListSelectionHarness(seed: nil)
        h.setHoldList(true)
        let e = h.beginRefresh()
        XCTAssertNotNil(h.acceptFailure(
            epoch: e,
            cached: [ListFixtures.cached("A")],
            cachedSelected: a
        ))
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, a)
        XCTAssertEqual(h.claims.count, 1)
        h.waitListHeld()
        h.applyUser(b)
        h.releaseList()
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["A", "B"])
        h.assertSelectionFinal(b)
    }

    func testUserBBeforeAcceptedFailureRestore_RestoreSuppressed() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let h = IntegratedListSelectionHarness(seed: nil)
        h.applyUser(b)
        XCTAssertEqual(h.claims.count, 1)
        h.setHoldList(true)
        let e = h.beginRefresh()
        XCTAssertNotNil(h.acceptFailure(
            epoch: e,
            cached: [ListFixtures.cached("A")],
            cachedSelected: a
        ))
        // Restore suppressed at acceptance — still B.
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)
        XCTAssertEqual(h.claims.count, 1)
        h.waitListHeld()
        h.releaseList()
        h.waitSelectedPublished(1)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B"])
        h.assertSelectionFinal(b)
    }

    func testDuplicateSelectionPayload_NoClaim() {
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let h = IntegratedListSelectionHarness(seed: b)
        let e = h.beginRefresh()
        XCTAssertNotNil(h.acceptSuccess(
            epoch: e,
            locations: [ListFixtures.cached("B")],
            selected: b
        ))
        XCTAssertEqual(h.claims.count, 0)
        h.waitListPublished(1)
        h.drain()
        XCTAssertTrue(h.selectedPublished.isEmpty)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)
    }

    func testRenameOnlyPayload_ThenUserC() {
        let id = UUID()
        let b = ListFixtures.selected(id: id, name: "B", lat: 2, lon: 2)
        let b2 = ListFixtures.selected(id: id, name: "B Renamed", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: b)
        h.setHoldList(true)
        _ = h.acceptPush(locations: [ListFixtures.cached("B2")], selected: b2)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative?.name, "B Renamed")
        XCTAssertEqual(h.claims.count, 0, "rename-only must not claim")
        h.waitListHeld()
        h.applyUser(c)
        h.releaseList()
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B Renamed", "C"])
        h.assertSelectionFinal(c)
    }

    func testCurrentLocationPayload_ThenSavedUser() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let cl = ListFixtures.currentPlaceholder()
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldList(true)
        _ = h.acceptPush(locations: [ListFixtures.cached("CL")], selected: cl)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative?.source, .currentGPS)
        XCTAssertEqual(h.claims.count, 1)
        h.waitListHeld()
        h.applyUser(b)
        h.releaseList()
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.last?.name, "B")
        h.assertSelectionFinal(b)
    }

    func testCrossApplier_SelectionSlowListFast() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldSelection(true)
        _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)
        h.waitListPublished(1)
        // List applied; selection UI still held.
        XCTAssertTrue(h.selectedPublished.isEmpty)
        h.applyUser(c)
        h.releaseSel()
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
        h.assertSelectionFinal(c)
    }

    func testCrossApplier_ListSlowSelectionFast() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldList(true)
        _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
        h.waitSelectedPublished(1)
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B"])
        XCTAssertTrue(h.listPublished.isEmpty)
        h.releaseList()
        h.waitListPublished(1)
        h.drain()
        h.assertSelectionFinal(b)
    }

    func testAcceptedAThenNewerRefreshB_ADoesNotClearBLoading() {
        let h = IntegratedListSelectionHarness(seed: ListFixtures.selected(name: "S"))
        h.setHoldList(true)
        let e1 = h.beginRefresh()
        XCTAssertNotNil(h.acceptSuccess(
            epoch: e1,
            locations: [ListFixtures.cached("A")],
            selected: nil
        ))
        h.waitListHeld()
        let e2 = h.beginRefresh()
        XCTAssertTrue(h.isLoading)
        XCTAssertEqual(h.listCoordinator.currentLoadingOwner, e2)
        h.releaseList()
        h.waitListPublished(1)
        h.drain()
        XCTAssertEqual(h.loadingClears, 0)
        XCTAssertTrue(h.isLoading)
        XCTAssertNotNil(h.acceptSuccess(
            epoch: e2,
            locations: [ListFixtures.cached("B")],
            selected: nil
        ))
        h.waitListPublished(2)
        h.drain()
        XCTAssertEqual(h.loadingClears, 1)
        XCTAssertFalse(h.isLoading)
    }

    func testAcceptedFailureAfterNewerRefresh_NoLateRestore() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let h = IntegratedListSelectionHarness(seed: nil)
        h.setHoldList(true)
        let e1 = h.beginRefresh()
        // Accept failure with restore A while held.
        XCTAssertNotNil(h.acceptFailure(
            epoch: e1,
            cached: [ListFixtures.cached("A")],
            cachedSelected: a
        ))
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, a)
        h.waitListHeld()
        // User B while list delayed.
        h.applyUser(b)
        // Newer refresh.
        _ = h.beginRefresh()
        h.releaseList()
        h.waitSelectedPublished(2)
        h.drain()
        // Restore already decided at accept; no second restore after list apply.
        XCTAssertEqual(h.selectedPublished.map(\.name), ["A", "B"])
        h.assertSelectionFinal(b)
        XCTAssertEqual(h.loadingClears, 0, "old failure must not clear newer refresh loading")
    }

    func testGuaranteedSubmission_PrepareAndSubmitStrong() {
        // Accept records prepare + list accept; selection authority advances.
        let h = IntegratedListSelectionHarness(seed: nil)
        let e = h.beginRefresh()
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        XCTAssertNotNil(h.acceptSuccess(
            epoch: e,
            locations: [ListFixtures.cached("B")],
            selected: b
        ))
        XCTAssertEqual(h.prepareCount, 1)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)
        h.waitSelectedPublished(1)
        h.waitListPublished(1)
        h.drain()
        h.assertSelectionFinal(b)
    }
}

// MARK: - Shared selected-location ingress ordering

final class WatchSelectedLocationIngressOrderingTests: XCTestCase {

    func testListBOwnsIngressThenUserC_OrderBThenC() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldIngress(true)

        let pushDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
            pushDone.signal()
        }
        h.waitIngressHeld()
        // B owns ingress; transition not yet classified.
        XCTAssertEqual(h.claims.count, 0)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, a)

        let userStarted = DispatchSemaphore(value: 0)
        let userDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            userStarted.signal()
            h.applyUser(c)
            userDone.signal()
        }
        _ = userStarted.wait(timeout: .now() + 1)
        // Give C a chance to block on ingress.
        Thread.sleep(forTimeInterval: 0.02)
        XCTAssertEqual(h.claims.count, 0, "C must not claim while B owns ingress")
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, a)

        h.releaseIngress()
        XCTAssertEqual(pushDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(userDone.wait(timeout: .now() + 5), .success)

        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
        h.assertSelectionFinal(c)
        XCTAssertEqual(h.claims.count, 2)
    }

    func testUserCOwnsIngressFirstThenListB_OrderCThenB() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldIngress(true)

        let userDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            h.applyUser(c)
            userDone.signal()
        }
        h.waitIngressHeld()
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, a)
        XCTAssertEqual(h.claims.count, 0)

        let pushDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
            pushDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.02)
        // Push may be inside list accept awaiting ingress; must not claim/transition yet.
        XCTAssertEqual(h.claims.count, 0)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, a)

        h.releaseIngress()
        XCTAssertEqual(userDone.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(pushDone.wait(timeout: .now() + 5), .success)

        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["C", "B"])
        h.assertSelectionFinal(b)
    }

    func testStandaloneRemoteVersusList_BothIngressOrders() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)

        // List B first.
        do {
            let h = IntegratedListSelectionHarness(seed: a)
            h.setHoldIngress(true)
            let pushDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
                pushDone.signal()
            }
            h.waitIngressHeld()
            let remoteDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                h.applyRemote(c)
                remoteDone.signal()
            }
            Thread.sleep(forTimeInterval: 0.02)
            h.releaseIngress()
            _ = pushDone.wait(timeout: .now() + 5)
            _ = remoteDone.wait(timeout: .now() + 5)
            h.waitSelectedPublished(2)
            h.drain()
            XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
            h.assertSelectionFinal(c)
        }

        // Standalone remote C first.
        do {
            let h = IntegratedListSelectionHarness(seed: a)
            h.setHoldIngress(true)
            let remoteDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                h.applyRemote(c)
                remoteDone.signal()
            }
            h.waitIngressHeld()
            let pushDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
                pushDone.signal()
            }
            Thread.sleep(forTimeInterval: 0.02)
            h.releaseIngress()
            _ = remoteDone.wait(timeout: .now() + 5)
            _ = pushDone.wait(timeout: .now() + 5)
            h.waitSelectedPublished(2)
            h.drain()
            XCTAssertEqual(h.selectedPublished.map(\.name), ["C", "B"])
            h.assertSelectionFinal(b)
        }
    }

    func testFailureRestoreVersusUser_BothIngressOrders() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)

        // Restore A first, then user B.
        do {
            let h = IntegratedListSelectionHarness(seed: nil)
            h.setHoldIngress(true)
            let e = h.beginRefresh()
            let failDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = h.acceptFailure(
                    epoch: e,
                    cached: [ListFixtures.cached("A")],
                    cachedSelected: a
                )
                failDone.signal()
            }
            h.waitIngressHeld()
            let userDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                h.applyUser(b)
                userDone.signal()
            }
            Thread.sleep(forTimeInterval: 0.02)
            XCTAssertEqual(h.claims.count, 0)
            h.releaseIngress()
            _ = failDone.wait(timeout: .now() + 5)
            _ = userDone.wait(timeout: .now() + 5)
            h.waitSelectedPublished(2)
            h.drain()
            XCTAssertEqual(h.selectedPublished.map(\.name), ["A", "B"])
            h.assertSelectionFinal(b)
        }

        // User B first, restore later suppressed.
        do {
            let h = IntegratedListSelectionHarness(seed: nil)
            h.setHoldIngress(true)
            let userDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                h.applyUser(b)
                userDone.signal()
            }
            h.waitIngressHeld()
            let e = h.beginRefresh()
            let failDone = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                _ = h.acceptFailure(
                    epoch: e,
                    cached: [ListFixtures.cached("A")],
                    cachedSelected: a
                )
                failDone.signal()
            }
            Thread.sleep(forTimeInterval: 0.02)
            h.releaseIngress()
            _ = userDone.wait(timeout: .now() + 5)
            _ = failDone.wait(timeout: .now() + 5)
            h.waitSelectedPublished(1)
            h.drain()
            XCTAssertEqual(h.selectedPublished.map(\.name), ["B"])
            XCTAssertEqual(h.claims.count, 1)
            h.assertSelectionFinal(b)
        }
    }

    func testListBOwnsIngressThenCurrentLocationUser() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let cl = ListFixtures.currentPlaceholder()
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldIngress(true)

        let pushDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
            pushDone.signal()
        }
        h.waitIngressHeld()
        let userDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            h.applyUser(cl)
            userDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.02)
        h.releaseIngress()
        _ = pushDone.wait(timeout: .now() + 5)
        _ = userDone.wait(timeout: .now() + 5)
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.source), [.saved, .currentGPS])
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative?.source, .currentGPS)
        XCTAssertEqual(h.claims.count, 2)
        // B's token is 1; CL is 2 and current.
        XCTAssertEqual(h.selectedRefreshes.map(\.1), [1, 2])
    }

    func testDuplicateListBWhileUserCWaits() {
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: b)
        h.setHoldIngress(true)

        let pushDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
            pushDone.signal()
        }
        h.waitIngressHeld()
        let userDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            h.applyUser(c)
            userDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.02)
        h.releaseIngress()
        _ = pushDone.wait(timeout: .now() + 5)
        _ = userDone.wait(timeout: .now() + 5)
        h.waitSelectedPublished(1)
        h.drain()
        XCTAssertEqual(h.claims.count, 1, "duplicate B is no-op; only C claims")
        XCTAssertEqual(h.selectedPublished.map(\.name), ["C"])
        h.assertSelectionFinal(c)
    }

    func testRenameB2OwnsIngressThenUserC() {
        let id = UUID()
        let b = ListFixtures.selected(id: id, name: "B", lat: 2, lon: 2)
        let b2 = ListFixtures.selected(id: id, name: "B Renamed", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: b)
        h.setHoldIngress(true)

        let pushDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = h.acceptPush(locations: [ListFixtures.cached("B2")], selected: b2)
            pushDone.signal()
        }
        h.waitIngressHeld()
        let userDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            h.applyUser(c)
            userDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.02)
        h.releaseIngress()
        _ = pushDone.wait(timeout: .now() + 5)
        _ = userDone.wait(timeout: .now() + 5)
        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B Renamed", "C"])
        XCTAssertEqual(h.claims.count, 1)
        h.assertSelectionFinal(c)
    }

    func testThreeSourceOrdering_ListUserRemote() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let d = ListFixtures.selected(name: "D", lat: 4, lon: 4)
        let h = IntegratedListSelectionHarness(seed: a)

        // Serial ingress acquisition via sequential perform (no hold): list B, user C, remote D.
        _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
        h.applyUser(c)
        h.applyRemote(d)
        h.waitSelectedPublished(3)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C", "D"])
        h.assertSelectionFinal(d)
    }

    func testThreeSourceOrdering_UserListUser() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let d = ListFixtures.selected(name: "D", lat: 4, lon: 4)
        let h = IntegratedListSelectionHarness(seed: a)
        h.applyUser(b)
        _ = h.acceptPush(locations: [ListFixtures.cached("C")], selected: c)
        h.applyUser(d)
        h.waitSelectedPublished(3)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C", "D"])
        h.assertSelectionFinal(d)
    }

    func testListApplierBlockedDoesNotChangeIngressOrder() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)
        h.setHoldList(true)
        h.setHoldIngress(true)

        let pushDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = h.acceptPush(locations: [ListFixtures.cached("B")], selected: b)
            pushDone.signal()
        }
        h.waitIngressHeld()
        let userDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            h.applyUser(c)
            userDone.signal()
        }
        Thread.sleep(forTimeInterval: 0.02)
        h.releaseIngress()
        // Selection completes while list still held.
        _ = pushDone.wait(timeout: .now() + 5)
        _ = userDone.wait(timeout: .now() + 5)
        h.waitSelectedPublished(2)
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
        XCTAssertTrue(h.listPublished.isEmpty)
        h.releaseList()
        h.waitListPublished(1)
        h.drain()
        h.assertSelectionFinal(c)
    }

    func testCallerReturnAfterIngressRelease_OrderPreserved() {
        let a = ListFixtures.selected(name: "A", lat: 1, lon: 1)
        let b = ListFixtures.selected(name: "B", lat: 2, lon: 2)
        let c = ListFixtures.selected(name: "C", lat: 3, lon: 3)
        let h = IntegratedListSelectionHarness(seed: a)

        let bReturned = DispatchSemaphore(value: 0)
        let bHoldReturn = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            h.applyUser(b)
            bReturned.signal()
            _ = bHoldReturn.wait(timeout: .now() + 5)
        }
        // Wait until B has completed ingress (authority B) before C.
        for _ in 0..<5_000 {
            if h.selectionCoordinator.currentAuthoritative == b { break }
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, b)

        h.applyUser(c)
        XCTAssertEqual(h.selectionCoordinator.currentAuthoritative, c)
        bHoldReturn.signal()
        _ = bReturned.wait(timeout: .now() + 5)

        h.waitSelectedPublished(2)
        h.drain()
        XCTAssertEqual(h.selectedPublished.map(\.name), ["B", "C"])
        h.assertSelectionFinal(c)
    }

    func testNoDoubleIngressHelperComposition_SourceAudit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = try String(
            contentsOf: root.appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift"),
            encoding: .utf8
        )
        // prepareSelection enters ingress once and uses already-inside helpers only.
        XCTAssertTrue(manager.contains("selectedLocationIngress.perform"))
        // Count perform call sites — should be 3 wrappers (remote, user, prepare).
        let performCount = manager.components(separatedBy: "selectedLocationIngress.perform").count - 1
        XCTAssertEqual(performCount, 3, "exactly three ingress entry sites")
        // Already-inside helpers must not call ingress again.
        let alreadyInside = [
            "applyRemoteSelectionAlreadyInsideIngress",
            "applyUserSelectionAlreadyInsideIngress",
            "applyRestoreAlreadyInsideIngress",
        ]
        for name in alreadyInside {
            // Extract function body roughly — ensure no nested perform in those functions
            guard let range = manager.range(of: "private func \(name)") else {
                XCTFail("missing \(name)")
                continue
            }
            let rest = manager[range.lowerBound...]
            let end = rest.range(of: "\n    private func ")?.lowerBound
                ?? rest.range(of: "\n    /// Nonblocking")?.lowerBound
                ?? rest.endIndex
            let body = String(rest[..<end])
            XCTAssertFalse(
                body.contains("selectedLocationIngress.perform"),
                "\(name) must not re-enter ingress"
            )
        }
    }

    func testTransitionCallSitesOnlyInsideAlreadyInsideIngress_SourceAudit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = try String(
            contentsOf: root.appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift"),
            encoding: .utf8
        )
        let applyUser = manager.components(separatedBy: "transitionCoordinator.applyUser(").count - 1
        let applyRemote = manager.components(separatedBy: "transitionCoordinator.applyRemote(").count - 1
        let restore = manager.components(separatedBy: "transitionCoordinator.restoreIfUninitialized(").count - 1
        XCTAssertEqual(applyUser, 1)
        XCTAssertEqual(applyRemote, 1)
        XCTAssertEqual(restore, 1)
        // Each occurs inside AlreadyInsideIngress helper name nearby.
        XCTAssertTrue(manager.contains("applyUserSelectionAlreadyInsideIngress"))
        XCTAssertTrue(manager.contains("applyRemoteSelectionAlreadyInsideIngress"))
        XCTAssertTrue(manager.contains("applyRestoreAlreadyInsideIngress"))
        // Public entry points use ingress wrappers.
        XCTAssertTrue(manager.contains("ingressUserSelection("))
        XCTAssertTrue(manager.contains("ingressRemoteSelection("))
        XCTAssertTrue(manager.contains("selectCurrentLocation"))
        // No direct handle* wrappers remaining.
        XCTAssertFalse(manager.contains("handleRemoteSelection"))
        XCTAssertFalse(manager.contains("handleUserSelection"))
        XCTAssertFalse(manager.contains("handleRuntimeCachedSelectionRestore"))
    }
}
