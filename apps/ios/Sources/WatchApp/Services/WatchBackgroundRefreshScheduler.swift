import Foundation
import SharedCode
import WatchKit

/// Schedules the next Watch-app background refresh.
///
/// watchOS may delay or skip the preferred date. This is best-effort liveness, not a
/// guaranteed hourly timer. Always reschedule after every attempt so the chain continues.
///
/// `WKApplication.shared()` and `scheduleBackgroundRefresh` are MainActor-isolated.
@MainActor
enum WatchBackgroundRefreshScheduler {
    /// Aligns with ``WatchConditionsPushAcceptance/freshConditionsInterval``.
    static let preferredInterval: TimeInterval = WatchConditionsPushAcceptance.freshConditionsInterval

    /// Lock-backed so WatchKit's nonisolated `scheduledCompletion` can record
    /// success without a fire-and-forget MainActor hop.
    private static let seed = SeedBox()

    /// Always *requests* a replacement preferred date before/after work.
    /// Success is recorded only in `scheduledCompletion` when `error == nil`.
    static func scheduleNext(now: Date = Date()) {
        submit(preferredDate: now.addingTimeInterval(preferredInterval))
    }

    /// Foreground process-start seed. No-op if this process already **succeeded**
    /// at scheduling (including an `.appRefresh` successor that completed).
    static func scheduleInitialIfNeeded(now: Date = Date()) {
        guard seed.shouldSeedOnForegroundActivation else { return }
        scheduleNext(now: now)
    }

    private static func submit(preferredDate: Date) {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error {
                print("WatchBackgroundRefreshScheduler: schedule failed: \(error.localizedDescription)")
                seed.recordSchedulingOutcome(success: false)
                return
            }
            seed.recordSchedulingOutcome(success: true)
        }
    }
}

/// Nonisolated bookkeeping for WatchKit's completion callback.
private final class SeedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state = WatchBackgroundRefreshSeedState()

    var shouldSeedOnForegroundActivation: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.shouldSeedOnForegroundActivation
    }

    func recordSchedulingOutcome(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        state.recordSchedulingOutcome(success: success)
    }
}
