import Foundation
import StoreKit
import SwiftUI

/// Inputs for one review-policy evaluation.
///
/// Dashboard, Locations, and Settings stay mounted together. A qualifying display
/// is only the selected Dashboard tab, with real conditions on screen, while the
/// scene is active. `hasViewingConditions` matches `DashboardView`'s branch:
/// loading, error, and empty states render only when `viewingConditions` is nil.
struct AppStoreReviewPromptContext: Equatable, Sendable {
    var isDashboardSelected: Bool
    var isShowingSuccessfulConditions: Bool
    var isSceneActive: Bool

    var isQualifyingDisplay: Bool {
        isDashboardSelected && isShowingSuccessfulConditions && isSceneActive
    }

    init(
        isDashboardSelected: Bool,
        isShowingSuccessfulConditions: Bool,
        isSceneActive: Bool
    ) {
        self.isDashboardSelected = isDashboardSelected
        self.isShowingSuccessfulConditions = isShowingSuccessfulConditions
        self.isSceneActive = isSceneActive
    }

    init(
        isDashboardTabSelected: Bool,
        hasViewingConditions: Bool,
        scenePhase: ScenePhase
    ) {
        self.init(
            isDashboardSelected: isDashboardTabSelected,
            isShowingSuccessfulConditions: hasViewingConditions,
            isSceneActive: scenePhase == .active
        )
    }
}

/// Persisted review cadence. Dates are evaluated with the device calendar.
///
/// The storage schema has no app version. An update must not restart the cadence.
struct AppStoreReviewPromptState: Codable, Equatable, Sendable {
    var qualifyingDayStarts: [Date] = []
    var attemptInstants: [Date] = []

    static let empty = AppStoreReviewPromptState()
    static let minimumDistinctQualifyingDays = 4
    static let minimumCalendarDaysFromFirstQualifyingDay = 7

    private enum CodingKeys: String, CodingKey {
        case qualifyingDayStarts
        case attemptInstants
    }

    /// Cooldown after `count` completed attempts. The first attempt uses the
    /// qualifying-day rule instead of a cooldown.
    static func cooldownCalendarDays(afterCompletedAttemptCount count: Int) -> Int {
        switch count {
        case 1: return 30
        case 2: return 60
        default: return 120
        }
    }

    /// Records `date`'s local calendar day at most once.
    /// Returns whether this call added a new day.
    @discardableResult
    mutating func recordQualifyingDay(_ date: Date, calendar: Calendar) -> Bool {
        if qualifyingDayStarts.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            return false
        }
        qualifyingDayStarts.append(calendar.startOfDay(for: date))
        qualifyingDayStarts.sort()
        return true
    }

    mutating func recordAttempt(_ date: Date) {
        attemptInstants.append(date)
    }

    func isEligibleForAttempt(at date: Date, calendar: Calendar) -> Bool {
        if attemptInstants.isEmpty {
            guard qualifyingDayStarts.count >= Self.minimumDistinctQualifyingDays,
                  let firstQualifyingDay = qualifyingDayStarts.min() else {
                return false
            }
            return Self.calendarDays(from: firstQualifyingDay, to: date, calendar: calendar)
                >= Self.minimumCalendarDaysFromFirstQualifyingDay
        }

        guard let latestAttempt = attemptInstants.max() else { return false }
        let cooldown = Self.cooldownCalendarDays(afterCompletedAttemptCount: attemptInstants.count)
        return Self.calendarDays(from: latestAttempt, to: date, calendar: calendar) >= cooldown
    }

    /// Distance in local calendar days, using each instant's start of day.
    /// DST does not add or remove a day, and the clock time of an attempt does not
    /// extend the cooldown past the start of the later calendar day.
    static func calendarDays(from earlier: Date, to later: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

protocol AppStoreReviewPromptStoring: AnyObject {
    func load() -> AppStoreReviewPromptState
    func save(_ state: AppStoreReviewPromptState)
}

final class UserDefaultsAppStoreReviewPromptStore: AppStoreReviewPromptStoring {
    /// Stable across releases. Deliberately not namespaced by app version.
    static let storageKey = "appStoreReviewPrompt.state"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = storageKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AppStoreReviewPromptState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(AppStoreReviewPromptState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(_ state: AppStoreReviewPromptState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Applies the review policy for a visible Dashboard and invokes the native review action.
///
/// The attempt is saved before the action runs. StoreKit does not report whether it
/// presented UI, and a re-entrant evaluation must see the cooldown immediately.
@MainActor
final class AppStoreReviewPromptCoordinator {
    /// After successful Dashboard content is already visible. Long enough that a
    /// cached launch does not present the sheet in the first moment; leaving the
    /// Dashboard cancels the wait.
    static let naturalPause: Duration = .seconds(3)

    private let store: any AppStoreReviewPromptStoring
    private let calendar: Calendar
    private let now: () -> Date
    private let pause: Duration
    private let requestReview: () -> Void
    private var state: AppStoreReviewPromptState
    private var evaluationGeneration = 0

    init(
        store: any AppStoreReviewPromptStoring,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        pause: Duration = AppStoreReviewPromptCoordinator.naturalPause,
        requestReview: @escaping () -> Void
    ) {
        self.store = store
        self.calendar = calendar
        self.now = now
        self.pause = pause
        self.requestReview = requestReview
        self.state = store.load()
    }

    func evaluateAfterNaturalPause(_ context: AppStoreReviewPromptContext) async {
        guard context.isQualifyingDisplay else { return }

        evaluationGeneration &+= 1
        let generation = evaluationGeneration
        if pause > .zero {
            do {
                try await Task.sleep(for: pause)
            } catch {
                return
            }
        }
        guard generation == evaluationGeneration, !Task.isCancelled else { return }

        let timestamp = now()
        if state.recordQualifyingDay(timestamp, calendar: calendar) {
            store.save(state)
        }
        guard state.isEligibleForAttempt(at: timestamp, calendar: calendar) else { return }

        state.recordAttempt(timestamp)
        store.save(state)
        requestReview()
    }
}

enum AppStoreReviewPromptIntegration {
    /// The XCTest host launches this app. That process must not record use or call StoreKit.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}

/// Observes Dashboard visibility without putting review policy inside `DashboardView`.
struct AppStoreReviewPromptAnchor: View {
    var isDashboardSelected: Bool
    var viewModel: DashboardViewModel

    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: AppStoreReviewPromptCoordinator?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: promptContext) {
                guard AppStoreReviewPromptIntegration.isEnabled else { return }
                await resolveCoordinator().evaluateAfterNaturalPause(promptContext)
            }
    }

    private var promptContext: AppStoreReviewPromptContext {
        AppStoreReviewPromptContext(
            isDashboardTabSelected: isDashboardSelected,
            hasViewingConditions: viewModel.viewingConditions != nil,
            scenePhase: scenePhase
        )
    }

    private func resolveCoordinator() -> AppStoreReviewPromptCoordinator {
        if let coordinator {
            return coordinator
        }
        let action = requestReview
        let created = AppStoreReviewPromptCoordinator(
            store: UserDefaultsAppStoreReviewPromptStore(),
            requestReview: { action() }
        )
        coordinator = created
        return created
    }
}
