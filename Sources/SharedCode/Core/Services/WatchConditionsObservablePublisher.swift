import Foundation

/// Generation-aware publication of coordinator applied state to observable UI properties.
///
/// Validation and mutation run under the same ingress lock via
/// ``WatchConditionsAcceptedUpdateCoordinator/publishIfCurrent(_:mutate:)`` so a concurrent
/// live claim cannot slip between check and mutation.
///
/// Call ``publish(_:mutate:)`` only from the MainActor so competing publications are ordered.
public final class WatchConditionsObservablePublisher: @unchecked Sendable {
    private let publishIfCurrent: @Sendable (WatchConditionsAppliedState, () -> Void) -> Bool
    private let lock = NSLock()
    private var lastPublishedIdentity: WatchConditionsAppliedStateIdentity?

    public init(
        publishIfCurrent: @escaping @Sendable (WatchConditionsAppliedState, () -> Void) -> Bool
    ) {
        self.publishIfCurrent = publishIfCurrent
    }

    /// Convenience: coordinator-backed production publisher.
    public convenience init(coordinator: WatchConditionsAcceptedUpdateCoordinator) {
        self.init { state, mutate in
            coordinator.publishIfCurrent(state, mutate: mutate)
        }
    }

    /// Applies `mutate` only when `state.identity` is still publishable.
    ///
    /// - Important: Call from MainActor. Check and mutation are one lock-held section.
    /// - Returns: `true` if observables were updated.
    @discardableResult
    @MainActor
    public func publish(
        _ state: WatchConditionsAppliedState,
        mutate: (WatchConditionsAppliedState) -> Void
    ) -> Bool {
        var didPublish = false
        let accepted = publishIfCurrent(state) {
            mutate(state)
            lock.lock()
            lastPublishedIdentity = state.identity
            lock.unlock()
            didPublish = true
        }
        return accepted && didPublish
    }

    public var lastPublished: WatchConditionsAppliedStateIdentity? {
        lock.lock()
        defer { lock.unlock() }
        return lastPublishedIdentity
    }
}
