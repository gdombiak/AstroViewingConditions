@testable import SharedCode
import XCTest

final class WatchBackgroundRefreshPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: Phase4BFixtures.timeZoneID)!
        return cal
    }

    func testNoSelectedLocationSkipsBeforeAcquisition() {
        let conditions = Phase4BFixtures.analyzableConditions(locationID: UUID())
        let decision = WatchBackgroundRefreshPolicy.decide(
            selectedLocation: nil,
            conditions: conditions
        )
        XCTAssertEqual(decision, .skip(.noSelectedLocation))
        XCTAssertNil(decision.selectedLocation)
    }

    func testDecisionBindsTheSelectedLocationBeforeAcquisition() {
        let id = UUID()
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let decision = WatchBackgroundRefreshPolicy.decide(
            selectedLocation: selected,
            conditions: nil
        )
        guard case let .refresh(bound) = decision else {
            return XCTFail("expected refresh, got \(decision)")
        }
        XCTAssertEqual(bound, selected)
        XCTAssertEqual(bound.id, id)
    }

    func testFreshDisplayablePairSkips() {
        let id = UUID()
        let now = Date()
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: now
        )
        let decision = WatchBackgroundRefreshPolicy.decide(
            selectedLocation: selected,
            conditions: conditions,
            referenceDate: now
        )
        XCTAssertEqual(decision, .skip(.stillFreshAndDisplayable))
    }

    func testOneHourStalePairRefreshesTheSameLocation() {
        let id = UUID()
        let evening = date(year: 2026, month: 6, day: 1, hour: 21)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: evening
        )
        let later = evening.addingTimeInterval(
            WatchConditionsPushAcceptance.freshConditionsInterval + 60
        )
        let decision = WatchBackgroundRefreshPolicy.decide(
            selectedLocation: selected,
            conditions: conditions,
            referenceDate: later
        )
        XCTAssertEqual(decision, .refresh(selected))
    }

    func testStaleCompanionDisplayPolicyRefreshes() {
        let id = UUID()
        let evening = date(year: 2026, month: 6, day: 1, hour: 21)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: evening
        )
        let later = evening.addingTimeInterval(
            WatchComplicationCompanionDisplayPolicy.companionDisplayMaxAge + 60
        )
        let display = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selected,
            conditions: conditions,
            referenceDate: later
        )
        guard case .failure(.stale) = display else {
            return XCTFail("expected stale display, got \(display)")
        }
        XCTAssertEqual(
            WatchBackgroundRefreshPolicy.decide(
                selectedLocation: selected,
                conditions: conditions,
                referenceDate: later
            ),
            .refresh(selected)
        )
    }

    func testInactiveObservingNightRefreshesEvenIfNotCalendarStaleBy24h() {
        let id = UUID()
        let evening = date(year: 2026, month: 6, day: 1, hour: 21)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let conditions = makeSingleDayConditions(locationID: id, referenceDate: evening)
        let nextMorning = date(year: 2026, month: 6, day: 2, hour: 10)
        let display = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selected,
            conditions: conditions,
            referenceDate: nextMorning
        )
        guard case .failure(.inactiveObservingNight) = display else {
            return XCTFail("expected inactive night, got \(display)")
        }
        XCTAssertEqual(
            WatchBackgroundRefreshPolicy.decide(
                selectedLocation: selected,
                conditions: conditions,
                referenceDate: nextMorning
            ),
            .refresh(selected)
        )
    }

    func testLocationMismatchRefreshesBoundSelection() {
        let selected = Phase4BFixtures.selectedSaved(id: UUID())
        let conditions = Phase4BFixtures.analyzableConditions(
            locationID: UUID(),
            lat: Phase4BFixtures.latitude + 1
        )
        let decision = WatchBackgroundRefreshPolicy.decide(
            selectedLocation: selected,
            conditions: conditions
        )
        XCTAssertEqual(decision, .refresh(selected))
    }

    func testWeatherAndBrightnessMustMatchTheSameSelectedLocation() {
        let id = UUID()
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let conditions = Phase4BFixtures.analyzableConditions(locationID: id)
        let matching = Phase4BFixtures.sample(id: id)
        XCTAssertTrue(
            WatchBackgroundRefreshPolicy.inputsMatchSelectedLocation(
                selectedLocation: selected,
                conditions: conditions,
                brightnessSample: matching
            )
        )
        XCTAssertTrue(
            WatchBackgroundRefreshPolicy.inputsMatchSelectedLocation(
                selectedLocation: selected,
                conditions: conditions,
                brightnessSample: nil
            )
        )

        let otherWeather = Phase4BFixtures.analyzableConditions(
            locationID: UUID(),
            lat: Phase4BFixtures.latitude + 1
        )
        XCTAssertFalse(
            WatchBackgroundRefreshPolicy.inputsMatchSelectedLocation(
                selectedLocation: selected,
                conditions: otherWeather,
                brightnessSample: matching
            )
        )

        let otherBrightness = Phase4BFixtures.sample(id: UUID())
        XCTAssertFalse(
            WatchBackgroundRefreshPolicy.inputsMatchSelectedLocation(
                selectedLocation: selected,
                conditions: conditions,
                brightnessSample: otherBrightness
            )
        )
    }

    // MARK: - Existing accept path recovers `--` without a second pipeline

    func testSuccessfulAcceptRecoversStaleUnavailableComplication() async {
        let id = UUID()
        let evening = date(year: 2026, month: 6, day: 1, hour: 21)
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let stale = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: evening
        )
        let staleAt = evening.addingTimeInterval(
            WatchComplicationCompanionDisplayPolicy.companionDisplayMaxAge + 120
        )
        XCTAssertEqual(
            WatchBackgroundRefreshPolicy.decide(
                selectedLocation: selected,
                conditions: stale,
                referenceDate: staleAt
            ),
            .refresh(selected)
        )
        guard case .failure = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selected,
            conditions: stale,
            referenceDate: staleAt
        ) else {
            return XCTFail("stale pair must present as --")
        }

        let store = InMemoryWatchConditionsStore()
        let reloader = RecordingReloadReporter()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: reloader
        )
        let now = Date()
        let fresh = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: now
        )
        XCTAssertTrue(
            WatchBackgroundRefreshPolicy.inputsMatchSelectedLocation(
                selectedLocation: selected,
                conditions: fresh,
                brightnessSample: Phase4BFixtures.sample(id: id)
            )
        )
        let token = coordinator.claimLiveUpdate()
        let result = await coordinator.accept(
            conditions: fresh,
            transported: Phase4BFixtures.validPayload(id: id, conditions: fresh),
            selectedLocation: selected,
            locationTimeZone: TimeZone(identifier: Phase4BFixtures.timeZoneID),
            reloadComplications: true,
            token: token,
            referenceDate: now
        )
        guard case .applied = result else {
            return XCTFail("expected applied, got \(result)")
        }
        XCTAssertEqual(store.persistCount, 1)
        XCTAssertEqual(reloader.count, 1)
        guard case .success = WatchComplicationCompanionDisplayPolicy.evaluate(
            selectedLocation: selected,
            conditions: store.conditions,
            referenceDate: now
        ) else {
            return XCTFail("accepted pair must recover complication display")
        }
    }

    func testFailedAcceptPreservesLastKnownGoodPair() async {
        let id = UUID()
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let existing = Phase4BFixtures.analyzableConditions(locationID: id)
        let store = InMemoryWatchConditionsStore()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: RecordingReloadReporter()
        )
        let first = coordinator.claimLiveUpdate()
        let firstResult = await coordinator.accept(
            conditions: existing,
            transported: nil,
            selectedLocation: selected,
            locationTimeZone: TimeZone(identifier: Phase4BFixtures.timeZoneID),
            reloadComplications: true,
            token: first
        )
        guard case .applied = firstResult else {
            return XCTFail("seed persist failed: \(firstResult)")
        }
        store.setFailureMode(.conditionsWrite)

        let newer = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: Date().addingTimeInterval(60)
        )
        let second = coordinator.claimLiveUpdate()
        let failed = await coordinator.accept(
            conditions: newer,
            transported: nil,
            selectedLocation: selected,
            locationTimeZone: TimeZone(identifier: Phase4BFixtures.timeZoneID),
            reloadComplications: true,
            token: second
        )
        guard case .persistFailed = failed else {
            return XCTFail("expected persistFailed, got \(failed)")
        }
        XCTAssertEqual(store.conditions?.fetchedAt, existing.fetchedAt)
    }

    func testStaleTokenCannotReplaceNewerAcceptedPair() async {
        let id = UUID()
        let selected = Phase4BFixtures.selectedSaved(id: id)
        let older = Phase4BFixtures.analyzableConditions(
            locationID: id,
            referenceDate: Date().addingTimeInterval(-120)
        )
        let newer = Phase4BFixtures.analyzableConditions(locationID: id)
        let store = InMemoryWatchConditionsStore()
        let coordinator = WatchConditionsAcceptedUpdateCoordinator(
            store: store,
            reloader: RecordingReloadReporter()
        )
        let staleToken = coordinator.claimLiveUpdate()
        let currentToken = coordinator.claimLiveUpdate()
        let current = await coordinator.accept(
            conditions: newer,
            transported: nil,
            selectedLocation: selected,
            locationTimeZone: TimeZone(identifier: Phase4BFixtures.timeZoneID),
            reloadComplications: true,
            token: currentToken
        )
        guard case .applied = current else {
            return XCTFail("current token should apply: \(current)")
        }
        let discarded = await coordinator.accept(
            conditions: older,
            transported: nil,
            selectedLocation: selected,
            locationTimeZone: TimeZone(identifier: Phase4BFixtures.timeZoneID),
            reloadComplications: true,
            token: staleToken
        )
        XCTAssertEqual(String(describing: discarded), String(describing: WatchConditionsAcceptResult.discardedStale))
        if case .discardedStale = discarded {} else {
            return XCTFail("expected discardedStale, got \(discarded)")
        }
        XCTAssertEqual(store.conditions?.fetchedAt, newer.fetchedAt)
    }

    func testSuccessfulForegroundSeedMakesLaterActivationANoOp() {
        var state = WatchBackgroundRefreshSeedState()
        XCTAssertTrue(state.shouldSeedOnForegroundActivation)
        state.recordSchedulingOutcome(success: true)
        XCTAssertFalse(state.shouldSeedOnForegroundActivation)
        state.recordSchedulingOutcome(success: true)
        XCTAssertFalse(state.shouldSeedOnForegroundActivation)
    }

    func testFailedForegroundSeedRemainsRetryable() {
        var state = WatchBackgroundRefreshSeedState()
        state.recordSchedulingOutcome(success: false)
        XCTAssertTrue(
            state.shouldSeedOnForegroundActivation,
            "failed scheduledCompletion must not consume the initial seed"
        )
        state.recordSchedulingOutcome(success: true)
        XCTAssertFalse(state.shouldSeedOnForegroundActivation)
    }

    func testSuccessfulAppRefreshSuccessorSuppressesForegroundSeed() {
        var state = WatchBackgroundRefreshSeedState()
        state.recordSchedulingOutcome(success: true)
        XCTAssertFalse(
            state.shouldSeedOnForegroundActivation,
            "if .appRefresh successor completed, later .active must not seed again"
        )
    }

    func testWatchWidgetRemainsReadOnlyAndWatchAppWiresBackgroundRefresh() throws {
        let widget = try sourceText("Sources/WatchWidget/NightConditionsWatchWidget.swift")
        XCTAssertFalse(widget.contains("ConditionsProvider()"))
        XCTAssertFalse(widget.contains("saveWatchNightConditions"))
        XCTAssertTrue(widget.contains("WatchComplicationCompanionDisplayPolicy"))

        let app = try sourceText("Sources/WatchApp/AstroViewingConditionsWatchApp.swift")
        XCTAssertTrue(app.contains("backgroundTask(.appRefresh)"))
        XCTAssertTrue(app.contains("backgroundTask(.watchConnectivity)"))
        XCTAssertTrue(app.contains("WatchAppRuntime.bootstrap()"))
        XCTAssertFalse(app.contains("scheduleNext"))
        XCTAssertFalse(app.contains("scheduleBackgroundRefresh"))

        let runtime = try sourceText("Sources/WatchApp/Services/WatchAppRuntime.swift")
        XCTAssertTrue(runtime.contains("refreshIfNeeded()"))
        XCTAssertFalse(runtime.contains("ConditionsProvider()"))

        let manager = try sourceText("Sources/WatchApp/Services/WatchConditionsManager.swift")
        XCTAssertTrue(manager.contains("WatchBackgroundRefreshPolicy.decide"))
        XCTAssertTrue(manager.contains("updateCoordinator.accept"))
        XCTAssertTrue(manager.contains("authoritativeSelectedLocation"))

        let phone = try sourceText("Sources/AstroViewingConditions/Services/WatchConnectivityService.swift")
        XCTAssertTrue(phone.contains("publishCompanionSnapshot"))
        XCTAssertTrue(phone.contains("WatchCompanionSnapshotAccumulator"))
    }

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year, month: month, day: day, hour: hour
        ))!
    }

    private func makeSingleDayConditions(
        locationID: UUID,
        referenceDate: Date
    ) -> ViewingConditions {
        let full = Phase4BFixtures.analyzableConditions(
            locationID: locationID,
            referenceDate: referenceDate
        )
        return ViewingConditions(
            fetchedAt: full.fetchedAt,
            location: full.location,
            hourlyForecasts: full.hourlyForecasts,
            dailySunEvents: Array(full.dailySunEvents.prefix(1)),
            dailyMoonInfo: Array(full.dailyMoonInfo.prefix(1)),
            issPasses: [],
            fogScore: full.fogScore,
            timeZoneIdentifier: full.timeZoneIdentifier
        )
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
