import Foundation

/// Per-process bookkeeping for a *successful* Watch background-refresh schedule.
///
/// `.appRefresh` always *requests* its successor before work. Foreground activation
/// should seed the chain only if this process has not already **succeeded** at scheduling.
/// A failed `scheduledCompletion` must leave the seed retryable.
public struct WatchBackgroundRefreshSeedState: Sendable, Equatable {
    public private(set) var hasScheduledThisProcess: Bool

    public init(hasScheduledThisProcess: Bool = false) {
        self.hasScheduledThisProcess = hasScheduledThisProcess
    }

    /// Whether a foreground `.active` transition should call `scheduleBackgroundRefresh`.
    public var shouldSeedOnForegroundActivation: Bool {
        !hasScheduledThisProcess
    }

    /// Record WatchKit's asynchronous `scheduledCompletion` result.
    public mutating func recordSchedulingOutcome(success: Bool) {
        if success {
            hasScheduledThisProcess = true
        }
    }
}
