@testable import SharedCode
import XCTest

// MARK: - Blocking refresh UI gate (holds claim lock while paused)

/// Synchronous test gate: blocks inside `onRefreshUIPublicationEntered` under the live lock.
private final class BlockingRefreshUIGate: WatchConditionsUpdateGate, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var enteredKinds: [WatchRefreshUIPublicationKind] = []
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func beforePersist() async {}
    func beforeApplyCached() async {}
    func beforeCachePublication() async {}
    func onCachePublicationEntered() {}

    func onRefreshUIPublicationEntered(_ kind: WatchRefreshUIPublicationKind) {
        lock.lock()
        enteredKinds.append(kind)
        lock.unlock()
        // Still holding the live-token claim lock in the caller.
        entered.signal()
        release.wait()
    }

    func waitUntilEntered(timeout: TimeInterval = 5) -> Bool {
        entered.wait(timeout: .now() + timeout) == .success
    }

    func releaseEntered() {
        release.signal()
    }
}

// MARK: - Sequencer + coordinator atomic UI tests

private final class UInt64Box: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: UInt64?
    var value: UInt64? {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func set(_ v: UInt64) {
        lock.lock(); _value = v; lock.unlock()
    }
}

private final class BoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func set(_ v: Bool) {
        lock.lock(); _value = v; lock.unlock()
    }
}

final class WatchLiveIngressSequencerRefreshUITests: XCTestCase {
    func testWithCurrentTokenBlocksConcurrentClaim() {
        let sequencer = WatchLiveIngressSequencer()
        let token = WatchConditionsLiveUpdateToken(sequence: sequencer.claim())
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = sequencer.withCurrentToken(token) {
                entered.signal()
                release.wait()
            }
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)

        let claimBox = UInt64Box()
        let claimDone = expectation(description: "claim")
        DispatchQueue.global().async {
            claimBox.set(sequencer.claim())
            claimDone.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertNil(claimBox.value, "claim must wait while withCurrentToken holds the lock")

        release.signal()
        wait(for: [claimDone], timeout: 5)
        XCTAssertEqual(claimBox.value, 2)
    }

    func testStaleTokenZeroExecution() {
        let sequencer = WatchLiveIngressSequencer()
        let a = sequencer.claim()
        _ = sequencer.claim()
        var count = 0
        let ran = sequencer.withCurrentToken(a) {
            count += 1
        }
        XCTAssertFalse(ran)
        XCTAssertEqual(count, 0)
        let result: Int? = sequencer.withCurrentTokenResult(a) {
            count += 1
            return 42
        }
        XCTAssertNil(result)
        XCTAssertEqual(count, 0)
    }

    func testCurrentTokenExactlyOnce() {
        let sequencer = WatchLiveIngressSequencer()
        let a = WatchConditionsLiveUpdateToken(sequence: sequencer.claim())
        var count = 0
        let value = sequencer.withCurrentTokenResult(a) { () -> Int in
            count += 1
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(count, 1)
        let ran = sequencer.withCurrentToken(a) {
            count += 1
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(count, 2)
    }
}

final class WatchConditionsRefreshUIAtomicityTests: XCTestCase {
    func testBeginLoadingBoundary_AHoldsLockBeforeBClaim() {
        let gate = BlockingRefreshUIGate()
        let sequencer = WatchLiveIngressSequencer()
        let store = InMemoryUIStore()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: NoopReloader(),
            gate: gate,
            liveIngress: sequencer
        )

        let tokenA = coordinator.claimLiveUpdate()
        let aApplied = BoolBox()
        let aDone = expectation(description: "A UI done")

        DispatchQueue.global().async {
            // Simulate MainActor-sync section using the production boundary.
            let ran = coordinator.withCurrentLiveTokenForRefreshUI(tokenA, kind: .beginLoading) {
                aApplied.set(true)
            }
            XCTAssertTrue(ran)
            aDone.fulfill()
        }

        XCTAssertTrue(gate.waitUntilEntered())
        XCTAssertFalse(aApplied.value, "mutate runs after hook; still inside critical section")

        let bSequence = UInt64Box()
        let bClaimed = expectation(description: "B claim")
        DispatchQueue.global(qos: .userInitiated).async {
            bSequence.set(sequencer.claim())
            bClaimed.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertNil(bSequence.value, "B cannot claim while A holds UI boundary lock")

        gate.releaseEntered()
        wait(for: [aDone, bClaimed], timeout: 5)
        XCTAssertTrue(aApplied.value)
        XCTAssertEqual(bSequence.value, 2)
    }

    func testBeginLoadingBoundary_BClaimsFirst_AZeroMutation() {
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: InMemoryUIStore(),
            reloader: NoopReloader(),
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )
        let tokenA = coordinator.claimLiveUpdate()
        _ = coordinator.claimLiveUpdate() // B

        var mutated = false
        let ran = coordinator.withCurrentLiveTokenForRefreshUI(tokenA, kind: .beginLoading) {
            mutated = true
        }
        XCTAssertFalse(ran)
        XCTAssertFalse(mutated)
    }

    func testTerminalSuccessBoundary_BClaimsFirst_AZeroMutation() {
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: InMemoryUIStore(),
            reloader: NoopReloader(),
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )
        let tokenA = coordinator.claimLiveUpdate()
        _ = coordinator.claimLiveUpdate()

        var isLoading = true
        var error: String? = "B-error"
        let ran = coordinator.withCurrentLiveTokenForRefreshUI(tokenA, kind: .terminal) {
            error = nil
            isLoading = false
        }
        XCTAssertFalse(ran)
        XCTAssertEqual(error, "B-error")
        XCTAssertTrue(isLoading)
    }

    func testTerminalFailureBoundary_BClaimsFirst_ACannotSetError() {
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: InMemoryUIStore(),
            reloader: NoopReloader(),
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )
        let tokenA = coordinator.claimLiveUpdate()
        _ = coordinator.claimLiveUpdate()

        var isLoading = true
        var error: String?
        let ran = coordinator.withCurrentLiveTokenForRefreshUI(tokenA, kind: .terminal) {
            error = "A-fail"
            isLoading = false
        }
        XCTAssertFalse(ran)
        XCTAssertNil(error)
        XCTAssertTrue(isLoading)
    }

    func testPushTerminalBoundary_BClaimsFirst_PushZeroUIMutation() {
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: InMemoryUIStore(),
            reloader: NoopReloader(),
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )
        let pushToken = coordinator.claimLiveUpdate()
        _ = coordinator.claimLiveUpdate() // selection B

        var isLoading = true
        var error: String? = "keep"
        let ran = coordinator.withCurrentLiveTokenForRefreshUI(pushToken, kind: .terminal) {
            error = nil
            isLoading = false
        }
        XCTAssertFalse(ran)
        XCTAssertEqual(error, "keep")
        XCTAssertTrue(isLoading)
    }

    func testPushTerminalBoundary_PushCompletesBeforeBClaim() {
        let gate = BlockingRefreshUIGate()
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: InMemoryUIStore(),
            reloader: NoopReloader(),
            gate: gate,
            liveIngress: sequencer
        )
        let pushToken = coordinator.claimLiveUpdate()
        let cleared = BoolBox()
        let pushDone = expectation(description: "push UI")
        DispatchQueue.global().async {
            _ = coordinator.withCurrentLiveTokenForRefreshUI(pushToken, kind: .terminal) {
                cleared.set(true)
            }
            pushDone.fulfill()
        }
        XCTAssertTrue(gate.waitUntilEntered())

        let bSeq = UInt64Box()
        let bDone = expectation(description: "B")
        DispatchQueue.global().async {
            bSeq.set(sequencer.claim())
            bDone.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertNil(bSeq.value)

        gate.releaseEntered()
        wait(for: [pushDone, bDone], timeout: 5)
        XCTAssertTrue(cleared.value)
        XCTAssertEqual(bSeq.value, 2)
    }

    func testRapidABC_OnlyCMutatesFinalState() {
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: InMemoryUIStore(),
            reloader: NoopReloader(),
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )
        let a = coordinator.claimLiveUpdate()
        let b = coordinator.claimLiveUpdate()
        let c = coordinator.claimLiveUpdate()

        var isLoading = true
        var error: String?
        var mutations = 0

        XCTAssertFalse(coordinator.withCurrentLiveTokenForRefreshUI(a, kind: .terminal) {
            mutations += 1
            isLoading = false
            error = "A"
        })
        XCTAssertFalse(coordinator.withCurrentLiveTokenForRefreshUI(b, kind: .terminal) {
            mutations += 1
            isLoading = false
            error = "B"
        })
        XCTAssertTrue(coordinator.withCurrentLiveTokenForRefreshUI(c, kind: .terminal) {
            mutations += 1
            isLoading = false
            error = nil
        })
        XCTAssertEqual(mutations, 1)
        XCTAssertNil(error)
        XCTAssertFalse(isLoading)
        _ = a; _ = b
    }

    func testNoSelectedLocationError_StaleTokenZeroMutation() {
        let sequencer = WatchLiveIngressSequencer()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: InMemoryUIStore(),
            reloader: NoopReloader(),
            gate: ImmediateWatchConditionsUpdateGate(),
            liveIngress: sequencer
        )
        let a = coordinator.claimLiveUpdate()
        _ = coordinator.claimLiveUpdate()

        var error: String?
        var isLoading = true
        XCTAssertFalse(coordinator.withCurrentLiveTokenForRefreshUI(a, kind: .terminal) {
            error = "No location selected"
            isLoading = false
        })
        XCTAssertNil(error)
        XCTAssertTrue(isLoading)
    }
}

// MARK: - Same-selection suppression + push acceptance

final class WatchSelectedLocationMaterialIdentityTests: XCTestCase {
    func testIdenticalSavedEchoDoesNotRequireRefresh() {
        let id = UUID()
        let a = SelectedLocation(source: .saved, id: id, name: "Home", latitude: 45.5, longitude: -122.7)
        XCTAssertFalse(
            WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
                from: a, to: a, forceRefresh: false
            )
        )
    }

    func testSavedRenameRequiresPersistenceButNotRefresh() {
        let id = UUID()
        let a = SelectedLocation(source: .saved, id: id, name: "Home", latitude: 45.5, longitude: -122.7)
        let b = SelectedLocation(source: .saved, id: id, name: "Home Renamed", latitude: 45.5, longitude: -122.7)
        XCTAssertFalse(
            WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
                from: a, to: b, forceRefresh: false
            )
        )
        XCTAssertTrue(
            WatchSelectedLocationMaterialIdentity.requiresSelectionPersistence(from: a, to: b)
        )
    }

    func testSavedIDChangeRequiresRefresh() {
        let a = SelectedLocation(source: .saved, id: UUID(), name: "A", latitude: 45.5, longitude: -122.7)
        let b = SelectedLocation(source: .saved, id: UUID(), name: "B", latitude: 45.5, longitude: -122.7)
        XCTAssertTrue(
            WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
                from: a, to: b, forceRefresh: false
            )
        )
    }

    func testSavedCoordinateChangeRequiresRefresh() {
        let id = UUID()
        let a = SelectedLocation(source: .saved, id: id, name: "A", latitude: 45.5, longitude: -122.7)
        let b = SelectedLocation(source: .saved, id: id, name: "A", latitude: 47.6, longitude: -122.3)
        XCTAssertTrue(
            WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
                from: a, to: b, forceRefresh: false
            )
        )
    }

    func testRepeatedCurrentLocationPlaceholderDoesNotRequireRefresh() {
        let a = SelectedLocation(source: .currentGPS, name: "Current Location", latitude: 0, longitude: 0)
        let b = SelectedLocation(source: .currentGPS, name: "Current Location", latitude: 0, longitude: 0)
        XCTAssertFalse(
            WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
                from: a, to: b, forceRefresh: false
            )
        )
    }

    func testUserForceRefreshAlwaysRequiresRefresh() {
        let a = SelectedLocation(source: .currentGPS, name: "Current Location", latitude: 0, longitude: 0)
        XCTAssertTrue(
            WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
                from: a, to: a, forceRefresh: true
            )
        )
    }

    func testSourceChangeRequiresRefresh() {
        let saved = SelectedLocation(source: .saved, id: UUID(), name: "A", latitude: 45.5, longitude: -122.7)
        let cl = SelectedLocation(source: .currentGPS, name: "Current Location", latitude: 0, longitude: 0)
        XCTAssertTrue(
            WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
                from: saved, to: cl, forceRefresh: false
            )
        )
    }
}

final class WatchConditionsPushAcceptanceTests: XCTestCase {
    func testMismatchedSavedPushRejected() {
        let idA = UUID()
        let idB = UUID()
        let conditionsA = makeConditions(id: idA, lat: 45.5, lon: -122.7, name: "A")
        let selectedB = SelectedLocation(source: .saved, id: idB, name: "B", latitude: 47.6, longitude: -122.3)
        XCTAssertFalse(
            WatchConditionsPushAcceptance.shouldAccept(
                conditions: conditionsA,
                selectedLocation: selectedB
            )
        )
    }

    func testMatchingSavedPushAccepted() {
        let id = UUID()
        let conditions = makeConditions(id: id, lat: 45.5, lon: -122.7, name: "A")
        let selected = SelectedLocation(source: .saved, id: id, name: "A", latitude: 45.5, longitude: -122.7)
        XCTAssertTrue(
            WatchConditionsPushAcceptance.shouldAccept(
                conditions: conditions,
                selectedLocation: selected
            )
        )
    }

    func testStaleConditionsRejected() {
        let id = UUID()
        var conditions = makeConditions(id: id, lat: 45.5, lon: -122.7, name: "A")
        // Force old fetchedAt
        conditions = ViewingConditions(
            fetchedAt: Date().addingTimeInterval(-10_000),
            location: conditions.location,
            hourlyForecasts: conditions.hourlyForecasts,
            dailySunEvents: conditions.dailySunEvents,
            dailyMoonInfo: conditions.dailyMoonInfo,
            issPasses: conditions.issPasses,
            fogScore: conditions.fogScore,
            timeZoneIdentifier: conditions.timeZoneIdentifier
        )
        let selected = SelectedLocation(source: .saved, id: id, name: "A", latitude: 45.5, longitude: -122.7)
        XCTAssertFalse(
            WatchConditionsPushAcceptance.shouldAccept(
                conditions: conditions,
                selectedLocation: selected
            )
        )
    }

    private func makeConditions(id: UUID, lat: Double, lon: Double, name: String) -> ViewingConditions {
        let tz = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let start = calendar.startOfDay(for: Date())
        func hour(_ h: Int) -> Date { calendar.date(byAdding: .hour, value: h, to: start)! }
        let sun = SunEvents(
            sunrise: hour(6), sunset: hour(18),
            civilTwilightBegin: hour(5), civilTwilightEnd: hour(19),
            nauticalTwilightBegin: hour(4), nauticalTwilightEnd: hour(20),
            astronomicalTwilightBegin: hour(3), astronomicalTwilightEnd: hour(21)
        )
        let forecasts = (0..<48).map { i in
            HourlyForecast(
                time: hour(i), cloudCover: 10, humidity: 40, windSpeed: 2,
                windDirection: 180, temperature: 12, dewPoint: 4, visibility: 20_000,
                lowCloudCover: 0, midCloudCover: 0, highCloudCover: 10, windSpeed200hPa: 40
            )
        }
        let moon = MoonInfo(phase: 0.1, phaseName: "New", altitude: 20, illumination: 5, emoji: "🌑")
        return ViewingConditions(
            fetchedAt: Date(),
            location: CachedLocation(id: id, name: name, latitude: lat, longitude: lon),
            hourlyForecasts: forecasts,
            dailySunEvents: [sun, sun, sun],
            dailyMoonInfo: [moon, moon, moon],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: "America/Los_Angeles"
        )
    }
}

// MARK: - Doubles

private final class NoopReloader: WatchComplicationReloadReporting, @unchecked Sendable {
    func reloadComplications() {}
}

private final class InMemoryUIStore: WatchConditionsPersisting, @unchecked Sendable {
    func persistAcceptedPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?
    ) throws {}
}
