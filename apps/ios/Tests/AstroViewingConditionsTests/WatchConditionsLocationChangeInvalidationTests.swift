@testable import SharedCode
import XCTest

// MARK: - Fixtures

private enum LocationChangeFixtures {
    static let latA = 45.50
    static let lonA = -122.70
    static let latB = 47.60
    static let lonB = -122.30
    static let latC = 40.70
    static let lonC = -74.00
    static let timeZoneID = "America/Los_Angeles"

    static func selectedSaved(
        id: UUID,
        lat: Double = latA,
        lon: Double = lonA,
        name: String = "Site"
    ) -> SelectedLocation {
        SelectedLocation(source: .saved, id: id, name: name, latitude: lat, longitude: lon)
    }

    static func selectedCurrent(lat: Double = 0, lon: Double = 0) -> SelectedLocation {
        SelectedLocation(
            source: .currentGPS,
            id: nil,
            name: "Current Location",
            latitude: lat,
            longitude: lon
        )
    }

    static func analyzableConditions(
        locationID: UUID?,
        lat: Double,
        lon: Double,
        name: String,
        cloudCover: Int = 10,
        referenceDate: Date = Date()
    ) -> ViewingConditions {
        let tz = TimeZone(identifier: timeZoneID)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let startOfDay = calendar.startOfDay(for: referenceDate)

        func hour(_ h: Int, dayOffset: Int = 0) -> Date {
            calendar.date(byAdding: .hour, value: h + dayOffset * 24, to: startOfDay)!
        }

        func sunEvents(dayOffset: Int) -> SunEvents {
            SunEvents(
                sunrise: hour(6, dayOffset: dayOffset),
                sunset: hour(18, dayOffset: dayOffset),
                civilTwilightBegin: hour(5, dayOffset: dayOffset),
                civilTwilightEnd: hour(19, dayOffset: dayOffset),
                nauticalTwilightBegin: hour(4, dayOffset: dayOffset),
                nauticalTwilightEnd: hour(20, dayOffset: dayOffset),
                astronomicalTwilightBegin: hour(3, dayOffset: dayOffset),
                astronomicalTwilightEnd: hour(21, dayOffset: dayOffset)
            )
        }

        let forecasts: [HourlyForecast] = (0..<48).map { index in
            HourlyForecast(
                time: hour(index),
                cloudCover: cloudCover,
                humidity: 40,
                windSpeed: 2,
                windDirection: 180,
                temperature: 12,
                dewPoint: 4,
                visibility: 20_000,
                lowCloudCover: 0,
                midCloudCover: 0,
                highCloudCover: cloudCover,
                windSpeed200hPa: 40
            )
        }

        let moon = MoonInfo(
            phase: 0.1,
            phaseName: "New",
            altitude: 20,
            illumination: 5,
            emoji: "🌑"
        )

        return ViewingConditions(
            fetchedAt: referenceDate,
            location: CachedLocation(
                id: locationID,
                name: name,
                latitude: lat,
                longitude: lon
            ),
            hourlyForecasts: forecasts,
            dailySunEvents: [sunEvents(dayOffset: 0), sunEvents(dayOffset: 1), sunEvents(dayOffset: 2)],
            dailyMoonInfo: [moon, moon, moon],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZoneID
        )
    }
}

// MARK: - Test doubles

private final class RecordingReloader: WatchComplicationReloadReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func reloadComplications() {
        lock.lock(); _count += 1; lock.unlock()
    }
}

private final class InMemoryStore: WatchConditionsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var _conditions: ViewingConditions?
    private var _oq: WatchObservingQualityDocument?
    private var _persistCount = 0
    private var _clearOQCount = 0

    var conditions: ViewingConditions? {
        lock.lock(); defer { lock.unlock() }
        return _conditions
    }
    var observingQuality: WatchObservingQualityDocument? {
        lock.lock(); defer { lock.unlock() }
        return _oq
    }
    var persistCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _persistCount
    }

    func persistAcceptedPair(
        conditions: ViewingConditions,
        observingQuality: WatchObservingQualityDocument?
    ) throws {
        lock.lock()
        _conditions = conditions
        if observingQuality == nil, _oq != nil {
            _clearOQCount += 1
        }
        _oq = observingQuality
        _persistCount += 1
        lock.unlock()
    }
}

/// Async-safe gate/result bookkeeping for blocked acquisition steps.
private actor RefreshGateBox {
    var phoneGates: [UInt64: CheckedContinuation<Void, Never>] = [:]
    var gpsGates: [UInt64: CheckedContinuation<Void, Never>] = [:]
    var timezoneGates: [UInt64: CheckedContinuation<Void, Never>] = [:]
    var phoneResults: [UInt64: Result<ViewingConditions, Error>] = [:]
    var failFetch: [UInt64: Error] = [:]
    var blockPhone = Set<UInt64>()
    var blockGPS = Set<UInt64>()
    var blockTimezone = Set<UInt64>()

    func configure(
        sequence: UInt64,
        conditions: ViewingConditions?,
        fail: Bool,
        blockPhone: Bool,
        blockGPS: Bool,
        blockTimezone: Bool
    ) {
        if fail {
            failFetch[sequence] = NSError(domain: "test", code: 1)
        } else if let conditions {
            phoneResults[sequence] = .success(conditions)
        }
        if blockPhone { self.blockPhone.insert(sequence) }
        if blockGPS { self.blockGPS.insert(sequence) }
        if blockTimezone { self.blockTimezone.insert(sequence) }
    }

    func releasePhone(_ sequence: UInt64) -> CheckedContinuation<Void, Never>? {
        blockPhone.remove(sequence)
        return phoneGates.removeValue(forKey: sequence)
    }

    func releaseGPS(_ sequence: UInt64) -> CheckedContinuation<Void, Never>? {
        blockGPS.remove(sequence)
        return gpsGates.removeValue(forKey: sequence)
    }

    func releaseTimezone(_ sequence: UInt64) -> CheckedContinuation<Void, Never>? {
        blockTimezone.remove(sequence)
        return timezoneGates.removeValue(forKey: sequence)
    }

    /// Atomically: if still blocked, store continuation (caller waits); else return false (caller resumes).
    func claimPhoneWait(_ sequence: UInt64, _ cont: CheckedContinuation<Void, Never>) -> Bool {
        guard blockPhone.contains(sequence) else { return false }
        phoneGates[sequence] = cont
        return true
    }

    func claimGPSWait(_ sequence: UInt64, _ cont: CheckedContinuation<Void, Never>) -> Bool {
        guard blockGPS.contains(sequence) else { return false }
        gpsGates[sequence] = cont
        return true
    }

    func claimTimezoneWait(_ sequence: UInt64, _ cont: CheckedContinuation<Void, Never>) -> Bool {
        guard blockTimezone.contains(sequence) else { return false }
        timezoneGates[sequence] = cont
        return true
    }

    func takeFetch(_ sequence: UInt64) -> (Error?, Result<ViewingConditions, Error>?) {
        (failFetch[sequence], phoneResults[sequence])
    }
}

/// Mirrors production WatchConditionsManager bound-refresh + selection invalidation.
private final class BoundRefreshHarness: @unchecked Sendable {
    let coordinator: WatchConditionsAcceptedUpdateCoordinator
    let store: InMemoryStore
    let reloader: RecordingReloader
    private let liveIngress: WatchConditionsLiveEventIngress
    private let gates = RefreshGateBox()

    // UI state mutated only on MainActor.
    @MainActor private(set) var isLoading = false
    @MainActor private(set) var error: Error?
    @MainActor private var _published: [WatchConditionsAppliedState] = []
    @MainActor private var _observables: [(locationID: UUID?, lat: Double, lon: Double, name: String)] = []

    @MainActor var publishedCount: Int { _published.count }
    @MainActor var publishedLocationSnapshots: [(locationID: UUID?, lat: Double, lon: Double, name: String)] {
        _observables
    }

    private let publisher: WatchConditionsObservablePublisher

    init() {
        let store = InMemoryStore()
        let reloader = RecordingReloader()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader,
            gate: ImmediateWatchConditionsUpdateGate()
        )
        self.store = store
        self.reloader = reloader
        self.coordinator = coordinator
        self.liveIngress = WatchConditionsLiveEventIngress(claim: {
            coordinator.claimLiveUpdate()
        })
        self.publisher = WatchConditionsObservablePublisher(coordinator: coordinator)
    }

    // MARK: Selection invalidation (production ordering)

    @discardableResult
    func select(
        _ location: SelectedLocation,
        conditions: ViewingConditions? = nil,
        shouldFail: Bool = false
    ) -> WatchConditionsLiveUpdateToken {
        let token = liveIngress.claimLocationSelectionIngress()
        // Schedule replacement refresh with same token (no second claim).
        liveIngress.scheduleProcessing { [weak self] in
            guard let self else { return }
            if let conditions {
                await self.gates.configure(
                    sequence: token.sequence,
                    conditions: conditions,
                    fail: shouldFail,
                    blockPhone: false,
                    blockGPS: false,
                    blockTimezone: false
                )
            }
            await self.performRefresh(
                context: WatchConditionsRefreshContext(token: token, selectedLocation: location)
            )
        }
        return token
    }

    /// Manual refresh claim (like conditionsManager.refresh()).
    @discardableResult
    func startManualRefresh(
        for location: SelectedLocation,
        conditions: ViewingConditions,
        blockPhone: Bool = false,
        blockGPS: Bool = false,
        blockTimezone: Bool = false,
        shouldFail: Bool = false
    ) -> WatchConditionsLiveUpdateToken {
        let token = liveIngress.claimRefreshIngress()
        liveIngress.scheduleProcessing { [weak self] in
            guard let self else { return }
            await self.gates.configure(
                sequence: token.sequence,
                conditions: conditions,
                fail: shouldFail,
                blockPhone: blockPhone,
                blockGPS: blockGPS,
                blockTimezone: blockTimezone
            )
            await self.performRefresh(
                context: WatchConditionsRefreshContext(token: token, selectedLocation: location)
            )
        }
        return token
    }

    /// Push claim at "callback receipt".
    @discardableResult
    func startPush(
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation,
        blockTimezone: Bool = false
    ) -> WatchConditionsLiveUpdateToken {
        let token = liveIngress.claimPushIngress()
        liveIngress.scheduleProcessing { [weak self] in
            guard let self else { return }
            if blockTimezone {
                await self.gates.configure(
                    sequence: token.sequence,
                    conditions: nil,
                    fail: false,
                    blockPhone: false,
                    blockGPS: false,
                    blockTimezone: true
                )
            }
            await self.completeLiveUpdate(
                conditions: conditions,
                selectedLocation: selectedLocation,
                token: token
            )
            await self.applyTerminalUIIfCurrent(token: token, error: nil)
        }
        return token
    }

    func releasePhone(for token: WatchConditionsLiveUpdateToken) async {
        let cont = await gates.releasePhone(token.sequence)
        cont?.resume()
    }

    func releaseGPS(for token: WatchConditionsLiveUpdateToken) async {
        let cont = await gates.releaseGPS(token.sequence)
        cont?.resume()
    }

    func releaseTimezone(for token: WatchConditionsLiveUpdateToken) async {
        let cont = await gates.releaseTimezone(token.sequence)
        cont?.resume()
    }

    // MARK: Pipeline (mirrors production)

    private func performRefresh(context: WatchConditionsRefreshContext) async {
        await beginLoadingIfCurrent(token: context.token)
        guard isTokenCurrent(context.token) else { return }

        do {
            // GPS gate (Current Location only) — models blocked getCurrentCoordinate.
            if context.selectedLocation.source == .currentGPS {
                await waitIfBlockedGPS(token: context.token)
                guard isTokenCurrent(context.token) else {
                    throw NSError(domain: "test", code: 99, userInfo: [NSLocalizedDescriptionKey: "superseded"])
                }
            }

            await waitIfBlockedPhone(token: context.token)
            guard isTokenCurrent(context.token) else {
                throw NSError(domain: "test", code: 99, userInfo: [NSLocalizedDescriptionKey: "superseded"])
            }

            let (fail, result) = await gates.takeFetch(context.token.sequence)

            if let fail {
                throw fail
            }
            guard case let .success(conditions)? = result else {
                throw NSError(domain: "test", code: 2)
            }

            await completeLiveUpdate(
                conditions: conditions,
                selectedLocation: context.selectedLocation,
                token: context.token
            )
            await applyTerminalUIIfCurrent(token: context.token, error: nil)
        } catch {
            await applyTerminalUIIfCurrent(token: context.token, error: error)
        }
    }

    private func completeLiveUpdate(
        conditions: ViewingConditions,
        selectedLocation: SelectedLocation,
        token: WatchConditionsLiveUpdateToken
    ) async {
        guard isTokenCurrent(token) else { return }
        await waitIfBlockedTimezone(token: token)
        guard isTokenCurrent(token) else { return }

        let result = await coordinator.accept(
            conditions: conditions,
            transported: nil,
            selectedLocation: selectedLocation,
            locationTimeZone: TimeZone(identifier: LocationChangeFixtures.timeZoneID),
            reloadComplications: true,
            token: token
        )
        switch result {
        case .discardedStale, .persistFailed:
            return
        case .applied(let state):
            await MainActor.run {
                _ = self.publisher.publish(state) { applied in
                    self._published.append(applied)
                    self._observables.append((
                        locationID: applied.conditions.location.id,
                        lat: applied.conditions.location.latitude,
                        lon: applied.conditions.location.longitude,
                        name: applied.conditions.location.name
                    ))
                }
            }
        }
    }

    private func isTokenCurrent(_ token: WatchConditionsLiveUpdateToken) -> Bool {
        token.sequence == coordinator.currentLiveSequence
    }

    private func beginLoadingIfCurrent(token: WatchConditionsLiveUpdateToken) async {
        // Production order: MainActor hop, then atomic currency check + mutation under claim lock.
        await MainActor.run {
            _ = self.coordinator.withCurrentLiveTokenForRefreshUI(token, kind: .beginLoading) {
                self.isLoading = true
                self.error = nil
            }
        }
    }

    private func applyTerminalUIIfCurrent(token: WatchConditionsLiveUpdateToken, error: Error?) async {
        await MainActor.run {
            _ = self.coordinator.withCurrentLiveTokenForRefreshUI(token, kind: .terminal) {
                self.error = error
                self.isLoading = false
            }
        }
    }

    private func waitIfBlockedPhone(token: WatchConditionsLiveUpdateToken) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task {
                let waiting = await self.gates.claimPhoneWait(token.sequence, cont)
                if !waiting { cont.resume() }
            }
        }
    }

    private func waitIfBlockedGPS(token: WatchConditionsLiveUpdateToken) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task {
                let waiting = await self.gates.claimGPSWait(token.sequence, cont)
                if !waiting { cont.resume() }
            }
        }
    }

    private func waitIfBlockedTimezone(token: WatchConditionsLiveUpdateToken) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task {
                let waiting = await self.gates.claimTimezoneWait(token.sequence, cont)
                if !waiting { cont.resume() }
            }
        }
    }

    /// Wait until publishedCount reaches n or timeout via yields.
    func waitForPublished(count: Int) async {
        for _ in 0..<5_000 {
            let n = await MainActor.run { publishedCount }
            if n >= count { return }
            await Task.yield()
        }
    }

    func waitUntilLoading(_ value: Bool) async {
        for _ in 0..<5_000 {
            let loading = await MainActor.run { isLoading }
            if loading == value { return }
            await Task.yield()
        }
    }
}

// MARK: - Tests

final class WatchConditionsLocationChangeInvalidationTests: XCTestCase {
    /// Shared coordinator for pure atomic UI-boundary assertions (no acquisition).
    private let coordinatorForAtomicTest = WatchConditionsAcceptedUpdateCoordinator(
        store: InMemoryStore(),
        reloader: RecordingReloader(),
        gate: ImmediateWatchConditionsUpdateGate()
    )

    func testSavedAToSavedBDuringPhoneRequest_OnlyBCommits() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, lat: LocationChangeFixtures.latA, lon: LocationChangeFixtures.lonA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B")
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A", cloudCover: 5
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B", cloudCover: 40
        )

        let tokenA = harness.startManualRefresh(
            for: locA,
            conditions: conditionsA,
            blockPhone: true
        )
        await harness.waitUntilLoading(true)

        // Select B while A blocked on phone.
        let tokenB = harness.select(locB, conditions: conditionsB)
        XCTAssertGreaterThan(tokenB.sequence, tokenA.sequence)

        // Complete A first — must be discarded.
        await harness.releasePhone(for: tokenA)
        await Task.yield(); await Task.yield()

        XCTAssertEqual(harness.store.persistCount, 0, "A must not persist")
        XCTAssertEqual(harness.reloader.count, 0)
        let _ui550 = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(_ui550, 0)
        let _ui551 = await MainActor.run { harness.isLoading }
        XCTAssertTrue(_ui551, "B still loading — A must not clear isLoading")
        let _ui552 = await MainActor.run { harness.error }
        XCTAssertNil(_ui552)

        // B completes.
        await harness.waitForPublished(count: 1)
        XCTAssertEqual(harness.store.persistCount, 1)
        XCTAssertEqual(harness.store.conditions?.location.id, idB)
        XCTAssertEqual(harness.reloader.count, 1)
        let _ui559 = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(_ui559, 1)
        let _ui560 = await MainActor.run { harness.isLoading }
        XCTAssertFalse(_ui560)
        let _ui561 = await MainActor.run { harness.error }
        XCTAssertNil(_ui561)
        let _ui562 = await MainActor.run { harness.publishedLocationSnapshots.first?.locationID }
        XCTAssertEqual(_ui562, idB)
    }

    func testSavedAToCurrentLocation_OnlyCLCommits() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locCL = LocationChangeFixtures.selectedCurrent()
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsCL = LocationChangeFixtures.analyzableConditions(
            locationID: nil,
            lat: LocationChangeFixtures.latB,
            lon: LocationChangeFixtures.lonB,
            name: "Current Location",
            cloudCover: 20
        )

        let tokenA = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        _ = harness.select(locCL, conditions: conditionsCL)
        await harness.releasePhone(for: tokenA)
        await harness.waitForPublished(count: 1)

        XCTAssertEqual(harness.store.conditions?.location.id, nil)
        XCTAssertEqual(harness.store.conditions?.location.name, "Current Location")
        let _ui588 = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(_ui588, 1)
        XCTAssertEqual(harness.store.persistCount, 1)
    }

    func testCurrentLocationBlockedOnGPS_SelectSavedB_OnlyBCommits() async {
        let harness = BoundRefreshHarness()
        let idB = UUID()
        let locCL = LocationChangeFixtures.selectedCurrent()
        let locB = LocationChangeFixtures.selectedSaved(id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B")
        let conditionsCL = LocationChangeFixtures.analyzableConditions(
            locationID: nil, lat: LocationChangeFixtures.latA, lon: LocationChangeFixtures.lonA, name: "CL"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let tokenCL = harness.startManualRefresh(
            for: locCL,
            conditions: conditionsCL,
            blockGPS: true
        )
        await harness.waitUntilLoading(true)

        _ = harness.select(locB, conditions: conditionsB)
        // Release old GPS — must not commit.
        await harness.releaseGPS(for: tokenCL)
        await harness.waitForPublished(count: 1)

        XCTAssertEqual(harness.store.conditions?.location.id, idB)
        XCTAssertEqual(harness.store.persistCount, 1)
        let _ui618 = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(_ui618, 1)
    }

    func testSelectionChangeDuringTimezone_ADiscarded() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B", cloudCover: 50
        )

        let tokenA = harness.startManualRefresh(
            for: locA,
            conditions: conditionsA,
            blockTimezone: true
        )
        // Let A pass phone and reach timezone gate.
        await Task.yield(); await Task.yield(); await Task.yield()

        _ = harness.select(locB, conditions: conditionsB)
        await harness.releaseTimezone(for: tokenA)
        await harness.waitForPublished(count: 1)

        XCTAssertEqual(harness.store.conditions?.location.id, idB)
        XCTAssertEqual(harness.store.persistCount, 1)
        // A never published.
        let _ui651 = await MainActor.run { harness.publishedLocationSnapshots }
        XCTAssertFalse(_ui651.contains { $0.locationID == idA })
    }

    func testPhoneOriginatedSelectionChangeInvalidatesInFlight() async {
        // Models didReceiveSelectedLocation: claim then startRefresh.
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let tokenA = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        // Phone-originated B (same path as select).
        _ = harness.select(locB, conditions: conditionsB)
        await harness.releasePhone(for: tokenA)
        await harness.waitForPublished(count: 1)

        XCTAssertEqual(harness.store.conditions?.location.id, idB)
        let _ui677 = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(_ui677, 1)
    }

    func testOldFailureAfterNewSuccessDoesNotSetError() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let tokenA = harness.startManualRefresh(
            for: locA,
            conditions: conditionsA,
            blockPhone: true,
            shouldFail: true
        )
        _ = harness.select(locB, conditions: conditionsB)
        await harness.waitForPublished(count: 1)
        await harness.waitUntilLoading(false)
        let loadingAfterB = await MainActor.run { harness.isLoading }
        XCTAssertFalse(loadingAfterB)
        let errorAfterB = await MainActor.run { harness.error }
        XCTAssertNil(errorAfterB)

        // A fails late.
        await harness.releasePhone(for: tokenA)
        for _ in 0..<50 { await Task.yield() }

        let errorAfterA = await MainActor.run { harness.error }
        XCTAssertNil(errorAfterA, "stale A failure must not set error")
        let loadingAfterA = await MainActor.run { harness.isLoading }
        XCTAssertFalse(loadingAfterA)
        XCTAssertEqual(harness.store.conditions?.location.id, idB)
    }

    func testOldSuccessWhileNewStillLoadingKeepsLoading() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        // A then B both blocked on phone — B is later generation.
        let tokenA = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        let tokenB = harness.startManualRefresh(for: locB, conditions: conditionsB, blockPhone: true)
        await harness.waitUntilLoading(true)

        await harness.releasePhone(for: tokenA)
        await Task.yield(); await Task.yield()
        let _ui737 = await MainActor.run { harness.isLoading }
        XCTAssertTrue(_ui737, "B still loading — A must not clear isLoading")
        let _ui738 = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(_ui738, 0)
        XCTAssertEqual(harness.store.persistCount, 0)

        await harness.releasePhone(for: tokenB)
        await harness.waitForPublished(count: 1)
        XCTAssertEqual(harness.store.conditions?.location.id, idB)
        let _ui744 = await MainActor.run { harness.isLoading }
        XCTAssertFalse(_ui744)
    }

    func testNewFailureAfterStaleSuccessReflectsBOnly() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let tokenA = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        // B will fail.
        let tokenB = harness.startManualRefresh(
            for: locB,
            conditions: conditionsB,
            blockPhone: true,
            shouldFail: true
        )
        await harness.waitUntilLoading(true)
        await harness.releasePhone(for: tokenA)
        // Give A time to attempt (and discard) commit while B remains blocked.
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(harness.store.persistCount, 0, "stale A must not persist")
        let loadingAfterA = await MainActor.run { harness.isLoading }
        XCTAssertTrue(loadingAfterA, "B still in flight — loading remains true")
        let errorAfterA = await MainActor.run { harness.error }
        XCTAssertNil(errorAfterA, "stale A must not set error")

        await harness.releasePhone(for: tokenB)
        await harness.waitUntilLoading(false)
        let err = await MainActor.run { harness.error }
        XCTAssertNotNil(err, "B failure must set error")
        XCTAssertEqual(harness.store.persistCount, 0, "neither A nor failed B persist")
        let pubs = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(pubs, 0)
    }

    func testPushThenSelectB_OnlyBCommits() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let pushToken = harness.startPush(
            conditions: conditionsA,
            selectedLocation: locA,
            blockTimezone: true
        )
        _ = harness.select(locB, conditions: conditionsB)
        await harness.releaseTimezone(for: pushToken)
        await harness.waitForPublished(count: 1)

        XCTAssertEqual(harness.store.conditions?.location.id, idB)
        let _ui807 = await MainActor.run { harness.publishedLocationSnapshots }
        XCTAssertFalse(_ui807.contains { $0.locationID == idA })
    }

    func testSelectBThenPushAMismatched_ProductionValidatorRejects() async {
        // Production pure seam: WatchConditionsPushAcceptance.shouldAccept.
        let idA = UUID()
        let idB = UUID()
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA,
            lat: LocationChangeFixtures.latA,
            lon: LocationChangeFixtures.lonA,
            name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let harness = BoundRefreshHarness()
        _ = harness.select(locB, conditions: conditionsB)
        await harness.waitForPublished(count: 1)
        let persist = harness.store.persistCount

        XCTAssertFalse(
            WatchConditionsPushAcceptance.shouldAccept(
                conditions: conditionsA,
                selectedLocation: locB
            ),
            "production push acceptance must reject mismatched selection"
        )
        XCTAssertEqual(harness.store.persistCount, persist)
        XCTAssertEqual(harness.store.conditions?.location.id, idB)
    }

    func testSelectBThenPushB_PushMayReplace() async {
        let harness = BoundRefreshHarness()
        let idB = UUID()
        let locB = LocationChangeFixtures.selectedSaved(id: idB, name: "B")
        let conditionsB1 = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B", cloudCover: 10
        )
        let conditionsB2 = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B", cloudCover: 80
        )

        _ = harness.select(locB, conditions: conditionsB1)
        await harness.waitForPublished(count: 1)
        let persistAfterSelect = harness.store.persistCount

        _ = harness.startPush(conditions: conditionsB2, selectedLocation: locB)
        await harness.waitForPublished(count: 2)

        XCTAssertGreaterThan(harness.store.persistCount, persistAfterSelect)
        XCTAssertEqual(harness.store.conditions?.location.id, idB)
    }

    func testStaleAHasNoOQSideEffects() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let tokenA = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        _ = harness.select(locB, conditions: conditionsB)
        await harness.releasePhone(for: tokenA)
        await harness.waitForPublished(count: 1)

        // Only B's single persist (night-only OQ cleared path may still write once).
        XCTAssertEqual(harness.store.persistCount, 1)
        XCTAssertEqual(harness.reloader.count, 1)
        XCTAssertNil(harness.store.observingQuality)
    }

    func testNoMismatchedPublishedStateUnderB() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        let tokenA = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        _ = harness.select(locB, conditions: conditionsB)
        await harness.releasePhone(for: tokenA)
        await harness.waitForPublished(count: 1)

        let snaps = await MainActor.run { harness.publishedLocationSnapshots }
        for snap in snaps {
            XCTAssertEqual(snap.locationID, idB, "never publish A under B selection")
            XCTAssertNotEqual(snap.name, "A")
        }
    }

    func testReplacementRefreshNotSkippedWhileLoading() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )

        _ = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        await harness.waitUntilLoading(true)
        // Direct selection while loading — must start B (not skipped by Boolean).
        _ = harness.select(locB, conditions: conditionsB)
        await harness.waitForPublished(count: 1)
        XCTAssertEqual(harness.store.conditions?.location.id, idB)
    }

    func testRapidABC_OnlyCCommits() async {
        let harness = BoundRefreshHarness()
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()
        let locA = LocationChangeFixtures.selectedSaved(id: idA, name: "A")
        let locB = LocationChangeFixtures.selectedSaved(
            id: idB, lat: LocationChangeFixtures.latB, lon: LocationChangeFixtures.lonB, name: "B"
        )
        let locC = LocationChangeFixtures.selectedSaved(
            id: idC, lat: LocationChangeFixtures.latC, lon: LocationChangeFixtures.lonC, name: "C"
        )
        let conditionsA = LocationChangeFixtures.analyzableConditions(
            locationID: idA, lat: locA.latitude, lon: locA.longitude, name: "A"
        )
        let conditionsB = LocationChangeFixtures.analyzableConditions(
            locationID: idB, lat: locB.latitude, lon: locB.longitude, name: "B"
        )
        let conditionsC = LocationChangeFixtures.analyzableConditions(
            locationID: idC, lat: locC.latitude, lon: locC.longitude, name: "C", cloudCover: 60
        )

        let tokenA = harness.startManualRefresh(for: locA, conditions: conditionsA, blockPhone: true)
        let tokenB = harness.startManualRefresh(for: locB, conditions: conditionsB, blockPhone: true)
        _ = harness.select(locC, conditions: conditionsC)

        await harness.releasePhone(for: tokenA)
        await harness.releasePhone(for: tokenB)
        await harness.waitForPublished(count: 1)

        XCTAssertEqual(harness.store.conditions?.location.id, idC)
        XCTAssertEqual(harness.store.persistCount, 1)
        XCTAssertEqual(harness.reloader.count, 1)
        let _ui964 = await MainActor.run { harness.publishedCount }
        XCTAssertEqual(_ui964, 1)
        let _ui965 = await MainActor.run { harness.isLoading }
        XCTAssertFalse(_ui965)
        let snaps = await MainActor.run { harness.publishedLocationSnapshots }
        for snap in snaps {
            XCTAssertEqual(snap.locationID, idC)
        }
    }

    func testAtomicRefreshUIBoundaryRejectsStaleToken() {
        let tokenA = coordinatorForAtomicTest.claimLiveUpdate()
        _ = coordinatorForAtomicTest.claimLiveUpdate()
        var mutated = false
        let ran = coordinatorForAtomicTest.withCurrentLiveTokenForRefreshUI(tokenA, kind: .terminal) {
            mutated = true
        }
        XCTAssertFalse(ran)
        XCTAssertFalse(mutated)
    }

    func testRefreshContextCarriesImmutableSelection() {
        let token = WatchConditionsLiveUpdateToken(sequence: 1)
        let selected = LocationChangeFixtures.selectedSaved(id: UUID(), name: "Pinned")
        let context = WatchConditionsRefreshContext(token: token, selectedLocation: selected)
        XCTAssertEqual(context.selectedLocation.name, "Pinned")
        XCTAssertEqual(context.token.sequence, 1)
        // Mutating a copy of selected elsewhere must not affect context (value type).
        var other = selected
        other.name = "Changed"
        XCTAssertEqual(context.selectedLocation.name, "Pinned")
        _ = other
    }
}
