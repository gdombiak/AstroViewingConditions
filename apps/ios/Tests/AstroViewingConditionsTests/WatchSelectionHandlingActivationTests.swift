@testable import SharedCode
import XCTest

// MARK: - Handler double

private final class RecordingSelectionHandler: WatchSelectedLocationChangeHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var _claims = 0
    private var _refreshes: [(SelectedLocation, UInt64)] = []
    private var next: UInt64 = 1
    /// Identity used for same-handler checks.
    let id = UUID()

    var claims: Int {
        lock.lock(); defer { lock.unlock() }
        return _claims
    }
    var refreshes: [(SelectedLocation, UInt64)] {
        lock.lock(); defer { lock.unlock() }
        return _refreshes
    }

    func claimSelectedLocationChange() -> WatchConditionsLiveUpdateToken {
        lock.lock()
        defer { lock.unlock() }
        let t = WatchConditionsLiveUpdateToken(sequence: next)
        next &+= 1
        _claims += 1
        return t
    }

    func startRefresh(for location: SelectedLocation, token: WatchConditionsLiveUpdateToken) {
        lock.lock()
        _refreshes.append((location, token.sequence))
        lock.unlock()
    }
}

// MARK: - Activation unit tests

final class WatchSelectionHandlingActivationTests: XCTestCase {

    func testInactiveUntilActivate() {
        let a = WatchSelectionHandlingActivation()
        XCTAssertEqual(a.currentState, .inactive)
        XCTAssertFalse(a.isSelectionDeliveryEnabled)
        XCTAssertNil(a.resolvedHandlerForTransition())
    }

    func testActivateInstallsHandlerBeforeRegisterDelegate() {
        let a = WatchSelectionHandlingActivation()
        let handler = RecordingSelectionHandler()
        var sawHandlerDuringRegister = false
        var registerCalls = 0

        let result = a.activate(handler: handler) {
            registerCalls += 1
            // During registration, delivery must already be enabled and handler resolvable.
            XCTAssertTrue(a.isSelectionDeliveryEnabled)
            XCTAssertTrue(a.currentState == .activating || a.currentState == .active)
            if let resolved = a.resolvedHandlerForTransition() {
                sawHandlerDuringRegister = (resolved as AnyObject) === handler
            }
        }

        XCTAssertEqual(result, .activated)
        XCTAssertEqual(a.currentState, .active)
        XCTAssertEqual(registerCalls, 1)
        XCTAssertTrue(sawHandlerDuringRegister)
        XCTAssertTrue((a.resolvedHandlerForTransition() as AnyObject?) === handler)
    }

    func testExactlyOnceRegistration_SameHandlerIdempotent() {
        let a = WatchSelectionHandlingActivation()
        let handler = RecordingSelectionHandler()
        var registerCalls = 0
        XCTAssertEqual(a.activate(handler: handler) { registerCalls += 1 }, .activated)
        XCTAssertEqual(a.activate(handler: handler) { registerCalls += 1 }, .alreadyActive)
        XCTAssertEqual(registerCalls, 1)
        XCTAssertEqual(a.currentState, .active)
    }

    func testDifferentHandlerRejected() {
        let a = WatchSelectionHandlingActivation()
        let h1 = RecordingSelectionHandler()
        let h2 = RecordingSelectionHandler()
        var registerCalls = 0
        XCTAssertEqual(a.activate(handler: h1) { registerCalls += 1 }, .activated)
        XCTAssertEqual(a.activate(handler: h2) { registerCalls += 1 }, .rejectedDifferentHandler)
        XCTAssertEqual(registerCalls, 1)
        XCTAssertTrue((a.resolvedHandlerForTransition() as AnyObject?) === h1)
    }

    func testConcurrentActivation_ExactlyOneRegister() {
        let a = WatchSelectionHandlingActivation()
        let handler = RecordingSelectionHandler()
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            var value: Int {
                lock.lock(); defer { lock.unlock() }
                return n
            }
            func increment() {
                lock.lock()
                n += 1
                lock.unlock()
            }
        }
        let registerCalls = Counter()
        let group = DispatchGroup()

        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                _ = a.activate(handler: handler) {
                    registerCalls.increment()
                    // Simulate slow registration so concurrent callers race.
                    Thread.sleep(forTimeInterval: 0.01)
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(registerCalls.value, 1)
        XCTAssertEqual(a.currentState, .active)
    }

    func testSynchronousCallbackDuringRegister_SeesHandler() {
        let a = WatchSelectionHandlingActivation()
        let handler = RecordingSelectionHandler()
        var claimDuringRegister = 0

        _ = a.activate(handler: handler) {
            // Synchronous selection-style work during addDelegate.
            if let h = a.resolvedHandlerForTransition() {
                _ = h.claimSelectedLocationChange()
                claimDuringRegister = handler.claims
            }
        }

        XCTAssertEqual(claimDuringRegister, 1)
        XCTAssertEqual(handler.claims, 1)
        XCTAssertEqual(a.currentState, .active)
    }

    func testWeakHandlerDeallocation_FailClosedResolve() {
        let a = WatchSelectionHandlingActivation()
        var handler: RecordingSelectionHandler? = RecordingSelectionHandler()
        _ = a.activate(handler: handler!) { }
        XCTAssertNotNil(a.resolvedHandlerForTransition())
        handler = nil
        // Weak handler cleared — fail closed.
        XCTAssertNil(a.resolvedHandlerForTransition())
        // Delivery still "enabled" at state level, but resolve returns nil.
        XCTAssertEqual(a.currentState, .active)
    }
}

// MARK: - Material transition fail-closed without claim

final class WatchSelectedLocationMaterialWithoutTokenTests: XCTestCase {

    func testMaterialRemoteWithoutClaimToken_DoesNotAdvanceAuthority() {
        let a = SelectedLocation(source: .saved, id: UUID(), name: "A", latitude: 1, longitude: 1)
        let b = SelectedLocation(source: .saved, id: UUID(), name: "B", latitude: 2, longitude: 2)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        var submits = 0
        let t = coord.applyRemote(
            b,
            claimRefresh: { nil },
            submit: { _ in submits += 1 }
        )
        XCTAssertEqual(t.kind, .noOp)
        XCTAssertEqual(submits, 0)
        XCTAssertEqual(coord.currentAuthoritative, a)
    }

    func testMaterialUserWithoutClaimToken_DoesNotAdvanceAuthority() {
        let a = SelectedLocation(source: .saved, id: UUID(), name: "A", latitude: 1, longitude: 1)
        let b = SelectedLocation(source: .saved, id: UUID(), name: "B", latitude: 2, longitude: 2)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        var submits = 0
        let t = coord.applyUser(
            b,
            sendToPhone: true,
            claimRefresh: { nil },
            submit: { _ in submits += 1 }
        )
        XCTAssertEqual(t.kind, .noOp)
        XCTAssertEqual(submits, 0)
        XCTAssertEqual(coord.currentAuthoritative, a)
    }

    func testRenameOnlyStillWorksWithoutTokenClaim() {
        let id = UUID()
        let a = SelectedLocation(source: .saved, id: id, name: "A", latitude: 1, longitude: 1)
        let a2 = SelectedLocation(source: .saved, id: id, name: "A Renamed", latitude: 1, longitude: 1)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        var claims = 0
        var submits = 0
        let t = coord.applyRemote(
            a2,
            claimRefresh: {
                claims += 1
                return WatchConditionsLiveUpdateToken(sequence: 1)
            },
            submit: { _ in submits += 1 }
        )
        XCTAssertEqual(t.kind, .displayOnly)
        XCTAssertEqual(claims, 0)
        XCTAssertEqual(submits, 1)
        XCTAssertEqual(coord.currentAuthoritative?.name, "A Renamed")
    }

    func testDuplicateStillNoOp() {
        let a = SelectedLocation(source: .saved, id: UUID(), name: "A", latitude: 1, longitude: 1)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        var claims = 0
        let t = coord.applyRemote(
            a,
            claimRefresh: {
                claims += 1
                return WatchConditionsLiveUpdateToken(sequence: 1)
            },
            submit: { _ in XCTFail("no submit") }
        )
        XCTAssertEqual(t.kind, .noOp)
        XCTAssertEqual(claims, 0)
    }
}

// MARK: - Stable handler snapshot (claim + startRefresh same instance)

final class WatchSelectionHandlerSnapshotTests: XCTestCase {

    func testClaimAndStartRefreshUseSameHandlerInstance() {
        let handler = RecordingSelectionHandler()
        let a = SelectedLocation(source: .saved, id: UUID(), name: "A", latitude: 1, longitude: 1)
        let b = SelectedLocation(source: .saved, id: UUID(), name: "B", latitude: 2, longitude: 2)
        let coord = WatchSelectedLocationTransitionCoordinator(seed: a)
        let applier = WatchSelectedLocationTransitionApplier(
            label: "test.handler.snapshot.\(UUID().uuidString)"
        )
        // Snapshot like production.
        let stable = handler as any WatchSelectedLocationChangeHandling
        let t = coord.applyRemote(
            b,
            claimRefresh: { stable.claimSelectedLocationChange() },
            submit: { transition in
                applier.enqueue(
                    transition,
                    publish: { _ in },
                    persist: { _ in },
                    sendToPhone: { _ in },
                    startRefresh: { location, token in
                        stable.startRefresh(for: location, token: token)
                    }
                )
            }
        )
        XCTAssertEqual(t.kind, .material)
        for _ in 0..<5_000 {
            if handler.refreshes.count >= 1 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        }
        XCTAssertEqual(handler.claims, 1)
        XCTAssertEqual(handler.refreshes.count, 1)
        XCTAssertEqual(handler.refreshes.first?.1, t.refreshToken?.sequence)
    }
}

// MARK: - Production source audits

final class WatchSelectionActivationSourceAuditTests: XCTestCase {

    func testLocationManagerInitDoesNotAddDelegate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = try String(
            contentsOf: root.appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift"),
            encoding: .utf8
        )
        // Init body must not call addDelegate — only activateSelectionHandling.
        XCTAssertTrue(manager.contains("activateSelectionHandling"))
        XCTAssertTrue(manager.contains("WatchSelectionHandlingActivation"))
        // Optional silent claim/start forbidden.
        XCTAssertFalse(manager.contains("handler?.claimSelectedLocationChange()"))
        XCTAssertFalse(manager.contains("handler?.startRefresh"))
        // Stable non-optional startRefresh on captured handler.
        XCTAssertTrue(manager.contains("handler.startRefresh(for: location, token: token)"))
        XCTAssertTrue(manager.contains("stableHandler"))
    }

    func testConditionsManagerActivatesLocationHandlingOnce() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let conditions = try String(
            contentsOf: root.appendingPathComponent("Sources/WatchApp/Services/WatchConditionsManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(conditions.contains("activateSelectionHandling(handler: self)"))
        XCTAssertFalse(conditions.contains("selectedLocationChangeHandler = self"))
        // Activation before cached load.
        let act = conditions.range(of: "activateSelectionHandling(handler: self)")!
        let cache = conditions.range(of: "loadCachedConditions()")!
        XCTAssertLessThan(act.lowerBound, cache.lowerBound)
    }

    func testNoInitAddDelegateOnLocationManager() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = try String(
            contentsOf: root.appendingPathComponent("Sources/WatchApp/Services/WatchLocationManager.swift"),
            encoding: .utf8
        )
        // Find init and ensure addDelegate is only inside activateSelectionHandling closure.
        XCTAssertTrue(manager.contains("connectivityManager.addDelegate(self)"))
        // Should appear once, in activate path.
        let count = manager.components(separatedBy: "connectivityManager.addDelegate(self)").count - 1
        XCTAssertEqual(count, 1)
        XCTAssertTrue(manager.contains("selectionActivation.activate"))
    }
}
