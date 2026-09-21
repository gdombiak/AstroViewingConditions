import SwiftUI
import XCTest
@testable import AstroViewingConditions

@MainActor
final class AppStoreReviewPromptTests: XCTestCase {
    func testFewerThanFourQualifyingDaysNeverRequests() async {
        let harness = Harness()
        let first = harness.date(year: 2026, month: 4, day: 1)
        await harness.openDashboard(on: first)
        await harness.openDashboard(on: harness.adding(days: 3, to: first))
        await harness.openDashboard(on: harness.adding(days: 7, to: first))

        XCTAssertEqual(harness.store.state.qualifyingDayStarts.count, 3)
        XCTAssertEqual(harness.requestCount, 0)
        XCTAssertTrue(harness.store.state.attemptInstants.isEmpty)
    }

    func testFourQualifyingDaysBeforeSevenElapsedDaysDoesNotRequest() async {
        let consecutive = Harness()
        let consecutiveStart = consecutive.date(year: 2026, month: 5, day: 1)
        for offset in 0..<4 {
            await consecutive.openDashboard(on: consecutive.adding(days: offset, to: consecutiveStart))
        }
        XCTAssertEqual(consecutive.store.state.qualifyingDayStarts.count, 4)
        XCTAssertEqual(consecutive.requestCount, 0)

        let harness = Harness()
        let first = harness.date(year: 2026, month: 4, day: 1)
        for offset in [0, 2, 4, 6] {
            await harness.openDashboard(on: harness.adding(days: offset, to: first))
        }

        XCTAssertEqual(harness.store.state.qualifyingDayStarts.count, 4)
        XCTAssertEqual(
            AppStoreReviewPromptState.calendarDays(
                from: harness.store.state.qualifyingDayStarts[0],
                to: harness.now,
                calendar: harness.calendar
            ),
            6
        )
        XCTAssertEqual(harness.requestCount, 0)
    }

    func testFirstAttemptBecomesEligibleOnTheSeventhCalendarDay() async throws {
        let harness = Harness()
        let attempt = try await harness.satisfyFirstAttempt()

        XCTAssertEqual(harness.store.state.qualifyingDayStarts.count, 4)
        XCTAssertEqual(harness.store.state.attemptInstants, [attempt])
        XCTAssertEqual(harness.persistedAttemptCountsAtRequest, [1])

        await harness.openDashboard(on: harness.adding(hours: 5, to: attempt))
        XCTAssertEqual(harness.requestCount, 1)
        XCTAssertEqual(harness.store.state.qualifyingDayStarts.count, 4)
        XCTAssertEqual(harness.store.state.attemptInstants, [attempt])
    }

    func testSameLocalCalendarDayCountsOnceIncludingAcrossUTCMidnight() async {
        let harness = Harness()
        let utc = Calendar(identifier: .gregorian)
        var utcCalendar = utc
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let lateLocalEvening = utcCalendar.date(from: DateComponents(
            timeZone: utcCalendar.timeZone,
            year: 2026, month: 1, day: 2, hour: 7, minute: 30
        ))!
        let earlyNextLocalMorning = utcCalendar.date(from: DateComponents(
            timeZone: utcCalendar.timeZone,
            year: 2026, month: 1, day: 2, hour: 8, minute: 30
        ))!

        XCTAssertTrue(utcCalendar.isDate(lateLocalEvening, inSameDayAs: earlyNextLocalMorning))
        XCTAssertFalse(harness.calendar.isDate(lateLocalEvening, inSameDayAs: earlyNextLocalMorning))

        await harness.openDashboard(on: lateLocalEvening)
        await harness.openDashboard(on: harness.date(year: 2026, month: 1, day: 1, hour: 12))
        await harness.openDashboard(on: earlyNextLocalMorning)

        XCTAssertEqual(
            harness.store.state.qualifyingDayStarts,
            [
                harness.calendar.startOfDay(for: lateLocalEvening),
                harness.calendar.startOfDay(for: earlyNextLocalMorning)
            ]
        )
        XCTAssertEqual(harness.requestCount, 0)
    }

    func testSecondAttemptRequiresThirtyCalendarDays() async throws {
        let harness = Harness()
        let firstAttempt = try await harness.satisfyFirstAttempt()
        let dayBefore = harness.date(year: 2026, month: 3, day: 30, hour: 23, minute: 50)
        let thirtiethCalendarDay = harness.date(year: 2026, month: 3, day: 31, hour: 0, minute: 15)
        let sameClockTimeAnniversary = try XCTUnwrap(
            harness.calendar.date(byAdding: .day, value: 30, to: firstAttempt)
        )

        XCTAssertEqual(
            AppStoreReviewPromptState.calendarDays(
                from: firstAttempt,
                to: dayBefore,
                calendar: harness.calendar
            ),
            29
        )
        XCTAssertEqual(
            AppStoreReviewPromptState.calendarDays(
                from: firstAttempt,
                to: thirtiethCalendarDay,
                calendar: harness.calendar
            ),
            30
        )
        // March 2026 includes the US spring-forward. Early on the 30th calendar day is
        // still short of both 30 absolute 24-hour periods and the original clock time.
        XCTAssertLessThan(thirtiethCalendarDay, sameClockTimeAnniversary)
        XCTAssertLessThan(
            thirtiethCalendarDay.timeIntervalSince(firstAttempt),
            30 * 24 * 60 * 60
        )

        await harness.openDashboard(on: dayBefore)
        XCTAssertEqual(harness.requestCount, 1)

        await harness.openDashboard(on: thirtiethCalendarDay)
        XCTAssertEqual(harness.requestCount, 2)
        XCTAssertEqual(harness.store.state.attemptInstants, [firstAttempt, thirtiethCalendarDay])
        XCTAssertEqual(harness.persistedAttemptCountsAtRequest, [1, 2])
    }

    func testThirdAttemptRequiresSixtyCalendarDays() async throws {
        let harness = Harness()
        let firstAttempt = try await harness.satisfyFirstAttempt()
        let secondAttempt = try await harness.advanceAttempt(
            from: firstAttempt,
            cooldownDays: 30,
            expectedRequestCount: 2
        )

        await harness.openDashboard(on: harness.adding(days: 59, to: secondAttempt))
        XCTAssertEqual(harness.requestCount, 2)

        let thirdAttempt = harness.adding(days: 60, to: secondAttempt)
        await harness.openDashboard(on: thirdAttempt)
        XCTAssertEqual(harness.requestCount, 3)
        XCTAssertEqual(harness.store.state.attemptInstants.last, thirdAttempt)
    }

    func testLaterAttemptsRequireOneHundredTwentyCalendarDays() async throws {
        let harness = Harness()
        let firstAttempt = try await harness.satisfyFirstAttempt()
        let secondAttempt = try await harness.advanceAttempt(
            from: firstAttempt,
            cooldownDays: 30,
            expectedRequestCount: 2
        )
        let thirdAttempt = try await harness.advanceAttempt(
            from: secondAttempt,
            cooldownDays: 60,
            expectedRequestCount: 3
        )

        await harness.openDashboard(on: harness.adding(days: 119, to: thirdAttempt))
        XCTAssertEqual(harness.requestCount, 3)

        let fourthAttempt = try await harness.advanceAttempt(
            from: thirdAttempt,
            cooldownDays: 120,
            expectedRequestCount: 4
        )

        await harness.openDashboard(on: harness.adding(days: 119, to: fourthAttempt))
        XCTAssertEqual(harness.requestCount, 4)

        let fifthAttempt = harness.adding(days: 120, to: fourthAttempt)
        await harness.openDashboard(on: fifthAttempt)
        XCTAssertEqual(harness.requestCount, 5)
        XCTAssertEqual(harness.store.state.attemptInstants.last, fifthAttempt)
    }

    func testHiddenDashboardCannotRequestEvenWhenPolicyIsEligible() async throws {
        let day = Harness.referenceAttempt
        let seed = try Harness.eligibleFirstAttemptSeed(on: day)
        let contexts = [
            AppStoreReviewPromptContext(
                isDashboardTabSelected: false,
                hasViewingConditions: true,
                scenePhase: .active
            ),
            AppStoreReviewPromptContext(
                isDashboardTabSelected: true,
                hasViewingConditions: false,
                scenePhase: .active
            ),
            AppStoreReviewPromptContext(
                isDashboardTabSelected: true,
                hasViewingConditions: true,
                scenePhase: .inactive
            ),
            AppStoreReviewPromptContext(
                isDashboardTabSelected: true,
                hasViewingConditions: true,
                scenePhase: .background
            )
        ]

        for context in contexts {
            let harness = Harness(now: day, seed: seed)
            XCTAssertFalse(context.isQualifyingDisplay)
            await harness.openDashboard(context, on: day)
            XCTAssertEqual(harness.requestCount, 0)
            XCTAssertEqual(harness.store.state, seed)
            XCTAssertEqual(harness.store.saveCount, 0)
        }

        let visible = Harness(now: day, seed: seed)
        await visible.openDashboard(on: day)
        XCTAssertEqual(visible.requestCount, 1)
        XCTAssertEqual(visible.store.state.attemptInstants, [day])
    }

    func testPersistedCadenceSurvivesRelaunchWithoutAnAppVersion() async throws {
        let suiteName = "AppStoreReviewPromptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let calendar = Harness.makeCalendar()
        let firstDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: Harness.referenceAttempt))
        var now = firstDay
        var requestCount = 0
        let first = AppStoreReviewPromptCoordinator(
            store: UserDefaultsAppStoreReviewPromptStore(defaults: defaults),
            calendar: calendar,
            now: { now },
            pause: .zero,
            requestReview: { requestCount += 1 }
        )

        for offset in 0..<3 {
            now = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstDay))
            await first.evaluateAfterNaturalPause(.qualifying)
        }

        let loaded = UserDefaultsAppStoreReviewPromptStore(defaults: defaults).load()
        XCTAssertEqual(loaded.qualifyingDayStarts.count, 3)
        XCTAssertTrue(loaded.attemptInstants.isEmpty)
        XCTAssertEqual(requestCount, 0)

        let reloaded = AppStoreReviewPromptCoordinator(
            store: UserDefaultsAppStoreReviewPromptStore(defaults: defaults),
            calendar: calendar,
            now: { now },
            pause: .zero,
            requestReview: { requestCount += 1 }
        )
        now = Harness.referenceAttempt
        await reloaded.evaluateAfterNaturalPause(
            AppStoreReviewPromptContext(
                isDashboardTabSelected: false,
                hasViewingConditions: true,
                scenePhase: .active
            )
        )
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(
            UserDefaultsAppStoreReviewPromptStore(defaults: defaults).load().qualifyingDayStarts.count,
            3
        )

        await reloaded.evaluateAfterNaturalPause(.qualifying)
        await reloaded.evaluateAfterNaturalPause(.qualifying)
        XCTAssertEqual(requestCount, 1)

        let persisted = UserDefaultsAppStoreReviewPromptStore(defaults: defaults).load()
        XCTAssertEqual(persisted.attemptInstants, [Harness.referenceAttempt])
        XCTAssertGreaterThanOrEqual(persisted.qualifyingDayStarts.count, 4)

        let payload = try XCTUnwrap(defaults.data(forKey: UserDefaultsAppStoreReviewPromptStore.storageKey))
        let json = try XCTUnwrap(String(data: payload, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("version"))

        let afterUpdate = AppStoreReviewPromptCoordinator(
            store: UserDefaultsAppStoreReviewPromptStore(defaults: defaults),
            calendar: calendar,
            now: { now },
            pause: .zero,
            requestReview: { requestCount += 1 }
        )
        await afterUpdate.evaluateAfterNaturalPause(.qualifying)
        XCTAssertEqual(requestCount, 1)

        defaults.set(Data("not-json".utf8), forKey: UserDefaultsAppStoreReviewPromptStore.storageKey)
        XCTAssertEqual(UserDefaultsAppStoreReviewPromptStore(defaults: defaults).load(), .empty)
    }

    func testCancelledNaturalPauseDoesNotRecordOrRequest() async {
        let harness = Harness(pause: .seconds(30))
        let task = Task { await harness.coordinator.evaluateAfterNaturalPause(.qualifying) }
        task.cancel()

        let finished = await taskFinishes(task, within: .seconds(2))
        XCTAssertTrue(finished)
        XCTAssertEqual(harness.requestCount, 0)
        XCTAssertEqual(harness.store.state, .empty)
        XCTAssertEqual(harness.store.saveCount, 0)
    }

    func testNonQualifyingDisplayDoesNotWaitForTheNaturalPause() async {
        let harness = Harness(pause: .seconds(30))
        let context = AppStoreReviewPromptContext(
            isDashboardTabSelected: false,
            hasViewingConditions: true,
            scenePhase: .active
        )
        let task = Task { await harness.coordinator.evaluateAfterNaturalPause(context) }
        let finished = await taskFinishes(task, within: .seconds(2))

        XCTAssertTrue(finished)
        XCTAssertEqual(harness.requestCount, 0)
        XCTAssertEqual(harness.store.saveCount, 0)
    }

    func testReviewIntegrationIsDisabledWhileRunningXCTest() {
        XCTAssertFalse(AppStoreReviewPromptIntegration.isEnabled)
    }

    private func taskFinishes(_ task: Task<Void, Never>, within timeout: Duration) async -> Bool {
        let completion = CompletionFlag()
        return await withCheckedContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                task.cancel()
                completion.resume(continuation, returning: false)
            }
            Task {
                await task.value
                timeoutTask.cancel()
                completion.resume(continuation, returning: true)
            }
        }
    }
}

private extension AppStoreReviewPromptContext {
    static let qualifying = AppStoreReviewPromptContext(
        isDashboardTabSelected: true,
        hasViewingConditions: true,
        scenePhase: .active
    )
}

@MainActor
private final class Harness {
    /// March 1, 2026, 00:30 in Los Angeles. Seven days after February 22, and early
    /// enough that a +30 calendar-day follow-up still precedes 30 absolute days.
    static let referenceAttempt = makeCalendar().date(from: DateComponents(
        timeZone: TimeZone(identifier: "America/Los_Angeles"),
        year: 2026, month: 3, day: 1, hour: 0, minute: 30
    ))!

    let calendar: Calendar
    let store: InMemoryAppStoreReviewPromptStore
    let coordinator: AppStoreReviewPromptCoordinator
    private let clock: Clock
    private let recorder: Recorder

    var now: Date {
        get { clock.now }
        set { clock.now = newValue }
    }

    var requestCount: Int { recorder.requestCount }
    var persistedAttemptCountsAtRequest: [Int] { recorder.persistedAttemptCountsAtRequest }

    init(
        now: Date = referenceAttempt,
        pause: Duration = .zero,
        seed: AppStoreReviewPromptState = .empty
    ) {
        let calendar = Self.makeCalendar()
        let clock = Clock(now: now)
        let store = InMemoryAppStoreReviewPromptStore(state: seed)
        let recorder = Recorder()
        self.calendar = calendar
        self.clock = clock
        self.store = store
        self.recorder = recorder
        self.coordinator = AppStoreReviewPromptCoordinator(
            store: store,
            calendar: calendar,
            now: { clock.now },
            pause: pause,
            requestReview: {
                recorder.requestCount += 1
                recorder.persistedAttemptCountsAtRequest.append(store.state.attemptInstants.count)
            }
        )
    }

    static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func eligibleFirstAttemptSeed(on date: Date) throws -> AppStoreReviewPromptState {
        let calendar = makeCalendar()
        let first = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: date))
        let offsets = [0, 1, 2, 7]
        return AppStoreReviewPromptState(
            qualifyingDayStarts: offsets.map { offset in
                calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: first)!)
            },
            attemptInstants: []
        )
    }

    func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    func adding(days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    func adding(hours: Int, to date: Date) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: date)!
    }

    func openDashboard(on date: Date) async {
        await openDashboard(.qualifying, on: date)
    }

    func openDashboard(_ context: AppStoreReviewPromptContext, on date: Date) async {
        now = date
        await coordinator.evaluateAfterNaturalPause(context)
    }

    func satisfyFirstAttempt() async throws -> Date {
        let attempt = Self.referenceAttempt
        let first = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: attempt))
        for offset in [0, 1, 2] {
            await openDashboard(on: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: first)))
        }
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(store.state.qualifyingDayStarts.count, 3)

        await openDashboard(on: attempt)
        XCTAssertEqual(requestCount, 1)
        return attempt
    }

    func advanceAttempt(
        from previousAttempt: Date,
        cooldownDays: Int,
        expectedRequestCount: Int
    ) async throws -> Date {
        await openDashboard(on: adding(days: cooldownDays - 1, to: previousAttempt))
        XCTAssertEqual(requestCount, expectedRequestCount - 1)

        let boundary = adding(days: cooldownDays, to: previousAttempt)
        await openDashboard(on: boundary)
        XCTAssertEqual(requestCount, expectedRequestCount)
        return boundary
    }
}

private final class Clock {
    var now: Date
    init(now: Date) {
        self.now = now
    }
}

private final class Recorder {
    var requestCount = 0
    var persistedAttemptCountsAtRequest: [Int] = []
}

private final class InMemoryAppStoreReviewPromptStore: AppStoreReviewPromptStoring {
    var state: AppStoreReviewPromptState
    private(set) var saveCount = 0

    init(state: AppStoreReviewPromptState = .empty) {
        self.state = state
    }

    func load() -> AppStoreReviewPromptState { state }

    func save(_ state: AppStoreReviewPromptState) {
        self.state = state
        saveCount += 1
    }
}

private final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<Bool, Never>, returning value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: value)
    }
}
