import Foundation

/// Identity of a successfully applied conditions/OQ state for ordered UI publication.
public enum WatchConditionsAppliedStateIdentity: Sendable, Equatable {
    /// Live update that claimed this ingress sequence.
    case live(sequence: UInt64)
    /// Deferred cache apply authorized under this live generation + deferred start.
    case cache(liveGeneration: UInt64, deferredSequence: UInt64)
}

/// Synchronous, lock-backed live/deferred ingress sequencing and commit/publish authorization.
///
/// Token order is determined by the order of `claim()` / `beginDeferred()` calls, not by when
/// unstructured `Task`s later run.
///
/// ## Commit boundary (`withCurrentToken` / `withAuthorizedCachePublication`)
///
/// Holds the same lock as `claim()` for the entire body. Concurrent `claim()` waits.
///
/// ## Observable publication (`withPublishableIdentity`)
///
/// Holds the same lock while validating identity **and** running the publication mutate
/// closure, so a concurrent live claim cannot slip between check and UI mutation.
public final class WatchLiveIngressSequencer: @unchecked Sendable {
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var deferredSequence: UInt64 = 0

    public init() {}

    /// Increments and returns the next live sequence (synchronous).
    ///
    /// Blocks while another thread is inside a protected commit/publish section.
    public func claim() -> UInt64 {
        lock.lock()
        sequence &+= 1
        let value = sequence
        lock.unlock()
        return value
    }

    /// Current latest claimed live sequence (0 if none).
    public var current: UInt64 {
        lock.lock()
        let value = sequence
        lock.unlock()
        return value
    }

    /// Current latest deferred-cache start sequence (0 if none).
    public var currentDeferred: UInt64 {
        lock.lock()
        let value = deferredSequence
        lock.unlock()
        return value
    }

    /// Bumps deferred sequence and captures current live sequence under one lock.
    public func beginDeferred() -> (liveGeneration: UInt64, deferredSequence: UInt64) {
        lock.lock()
        deferredSequence &+= 1
        let result = (sequence, deferredSequence)
        lock.unlock()
        return result
    }

    /// Runs `perform` only if `sequence` is still the latest **live** claim.
    ///
    /// Holds the same lock as ``claim()`` for the entire body. Concurrent `claim()` waits.
    /// **Non-reentrant:** `perform` must not call `claim`, `withCurrentToken`, or other
    /// methods on this sequencer (would deadlock). Never `await` inside `perform`.
    @discardableResult
    public func withCurrentToken(
        _ sequence: UInt64,
        perform: () throws -> Void
    ) rethrows -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard sequence == self.sequence else {
            return false
        }
        try perform()
        return true
    }

    /// Runs `perform` only if `sequence` is still the latest **live** claim.
    ///
    /// - Returns: `perform`'s result when current; `nil` when stale (closure not executed).
    /// - Important: Holds the claim lock for the whole closure. No `await` inside.
    @discardableResult
    public func withCurrentTokenResult<R>(
        _ sequence: UInt64,
        perform: () throws -> R
    ) rethrows -> R? {
        lock.lock()
        defer { lock.unlock() }
        guard sequence == self.sequence else {
            return nil
        }
        return try perform()
    }

    /// Token-typed convenience for live refresh/push UI and commit boundaries.
    @discardableResult
    public func withCurrentToken(
        _ token: WatchConditionsLiveUpdateToken,
        perform: () throws -> Void
    ) rethrows -> Bool {
        try withCurrentToken(token.sequence, perform: perform)
    }

    /// Token-typed result convenience for live refresh/push UI and commit boundaries.
    @discardableResult
    public func withCurrentTokenResult<R>(
        _ token: WatchConditionsLiveUpdateToken,
        perform: () throws -> R
    ) rethrows -> R? {
        try withCurrentTokenResult(token.sequence, perform: perform)
    }

    /// Cache publication under live + deferred currency (same lock as claim).
    ///
    /// - Returns: `true` if `perform` ran; `false` if live or deferred is stale.
    @discardableResult
    public func withAuthorizedCachePublication(
        liveGeneration: UInt64,
        deferredSequence: UInt64,
        perform: () throws -> Void
    ) rethrows -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard liveGeneration == self.sequence,
              deferredSequence == self.deferredSequence else {
            return false
        }
        try perform()
        return true
    }

    /// True when the applied identity may still be published to the UI.
    ///
    /// Live: sequence must still equal the latest **claim** (a failed newer claim still
    /// invalidates older pending publication).
    /// Cache: live generation and deferred sequence must both still match.
    public func isPublishable(_ identity: WatchConditionsAppliedStateIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPublishableUnlocked(identity)
    }

    /// Validates publishability and runs `perform` under the same lock (no await).
    ///
    /// Use for MainActor observable mutation so a concurrent claim cannot interleave.
    @discardableResult
    public func withPublishableIdentity(
        _ identity: WatchConditionsAppliedStateIdentity,
        perform: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isPublishableUnlocked(identity) else {
            return false
        }
        perform()
        return true
    }

    private func isPublishableUnlocked(_ identity: WatchConditionsAppliedStateIdentity) -> Bool {
        switch identity {
        case let .live(sequence):
            return sequence == self.sequence
        case let .cache(liveGeneration, deferredSequence):
            return liveGeneration == self.sequence
                && deferredSequence == self.deferredSequence
        }
    }
}
