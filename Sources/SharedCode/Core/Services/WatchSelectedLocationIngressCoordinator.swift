import Foundation

/// Serializes **all** selected-location ingress into ``WatchSelectedLocationTransitionCoordinator``.
///
/// ## Formal ordering rule
/// Transition order equals acquisition order of this lock — not wall-clock callback start,
/// not list-result accept order alone, and not caller return order.
///
/// ## Sources that must use this type
/// 1. List-result selected payloads (`prepareSelection` under list lock)
/// 2. Accepted failure cached-selection restores
/// 3. User selections
/// 4. Standalone remote selected-location callbacks
///
/// ## Critical section (must remain tiny)
/// Only: transition comparison, optional live-token claim, authority advance, nonblocking
/// selected-applier `queue.async`.
///
/// **Never** under this lock: await, MainActor wait, persistence, phone send, refresh start,
/// list persistence, GPS, or applier execution.
///
/// ## Lock order
/// 1. List-result coordinator lock (when processing a list result)
/// 2. **This ingress lock**
/// 3. Selected-location transition coordinator lock
/// 4. Live sequencer claim lock
/// 5. Nonblocking selected-applier submit
/// 6. Nonblocking list-applier submit
///
/// **Never reverse:** ingress / transition / live / appliers must not acquire the list lock.
/// **Non-recursive:** callers already holding this lock must not call `perform` again.
///
/// ## Test hook
/// ``beforeBody`` runs after the lock is acquired and before `body`, still under the lock.
/// Production: nil.
public final class WatchSelectedLocationIngressCoordinator: @unchecked Sendable {
    private let lock = NSLock()

    /// Invoked under the ingress lock immediately before `body` (tests may block here).
    public var beforeBody: (() -> Void)?

    public init() {}

    /// Run `body` while holding the shared selected-location ingress lock.
    @discardableResult
    public func perform<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        beforeBody?()
        return try body()
    }
}
