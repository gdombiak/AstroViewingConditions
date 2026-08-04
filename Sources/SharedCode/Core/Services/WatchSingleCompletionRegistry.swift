import Foundation

// MARK: - Timeout scheduling

/// Handle that can cancel a previously scheduled timeout.
public protocol WatchRequestTimeoutHandle: Sendable {
    func cancel()
}

/// Schedules delayed work for request timeouts (injectable for deterministic tests).
public protocol WatchRequestTimeoutScheduling: Sendable {
    /// Schedule `work` after `seconds`. Returns a handle that cancels if still pending.
    func schedule(
        after seconds: TimeInterval,
        work: @escaping @Sendable () -> Void
    ) -> any WatchRequestTimeoutHandle
}

/// Production scheduler: `DispatchQueue.asyncAfter`.
public final class DispatchQueueWatchRequestTimeoutScheduler: WatchRequestTimeoutScheduling, @unchecked Sendable {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue) {
        self.queue = queue
    }

    public func schedule(
        after seconds: TimeInterval,
        work: @escaping @Sendable () -> Void
    ) -> any WatchRequestTimeoutHandle {
        let item = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
        return DispatchWorkItemTimeoutHandle(item: item)
    }
}

private final class DispatchWorkItemTimeoutHandle: WatchRequestTimeoutHandle, @unchecked Sendable {
    private let item: DispatchWorkItem
    init(item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}

// MARK: - Single-completion registry

/// Thread-safe registry that resumes each request continuation **at most once**.
///
/// Used by watch WatchConnectivity for conditions (and locations) request/reply/timeout.
/// `complete` removes the entry before resume so concurrent reply/timeout/error races
/// cannot double-resume.
public final class WatchSingleCompletionRegistry<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: CheckedContinuation<Value, Error>] = [:]

    public init() {}

    /// Outstanding request count (for tests / diagnostics).
    public var outstandingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return continuations.count
    }

    public func contains(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return continuations[id] != nil
    }

    public func store(_ id: UUID, continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        continuations[id] = continuation
        lock.unlock()
    }

    /// Completes the request if still outstanding. Returns `true` if this call resumed.
    @discardableResult
    public func complete(_ id: UUID, with result: Result<Value, Error>) -> Bool {
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}

// MARK: - Request lifecycle (registry + timeout)

/// Owns store → timeout schedule → single complete for one family of requests.
///
/// Production component used by `WatchConnectivityManager` for conditions requests.
public final class WatchRequestLifecycleController<Value: Sendable>: @unchecked Sendable {
    private let registry = WatchSingleCompletionRegistry<Value>()
    private let scheduler: any WatchRequestTimeoutScheduling
    private let lock = NSLock()
    private var timeoutHandles: [UUID: any WatchRequestTimeoutHandle] = [:]

    public init(scheduler: any WatchRequestTimeoutScheduling) {
        self.scheduler = scheduler
    }

    /// Test/diagnostics access to the underlying registry.
    public var outstandingCount: Int { registry.outstandingCount }

    public func contains(_ id: UUID) -> Bool { registry.contains(id) }

    /// Register continuation and schedule timeout. Timeout completion uses `timeoutError`.
    ///
    /// Does **not** hold the lifecycle lock while invoking the scheduler (avoids deadlock
    /// if a test scheduler fires synchronously into `complete`). After scheduling, if the
    /// request already completed (eager timeout), the handle is cancelled and not retained.
    public func begin(
        id: UUID,
        timeout: TimeInterval,
        timeoutError: @escaping @Sendable () -> Error,
        continuation: CheckedContinuation<Value, Error>
    ) {
        registry.store(id, continuation: continuation)
        let handle = scheduler.schedule(after: timeout) { [weak self] in
            self?.complete(id, with: .failure(timeoutError()))
        }
        lock.lock()
        if registry.contains(id) {
            timeoutHandles[id] = handle
            lock.unlock()
        } else {
            // Eager scheduler already completed; do not retain a stale handle.
            lock.unlock()
            handle.cancel()
        }
    }

    /// Single-completion path for reply, send error, or timeout.
    @discardableResult
    public func complete(_ id: UUID, with result: Result<Value, Error>) -> Bool {
        lock.lock()
        let handle = timeoutHandles.removeValue(forKey: id)
        lock.unlock()
        handle?.cancel()
        return registry.complete(id, with: result)
    }
}

// MARK: - Conditions request message builder

/// Pure builder for watch → phone `requestConditions` message keys.
///
/// Shared so unit tests can prove Current Location context encoding without WCSession.
public enum WatchConditionsRequestMessageBuilder: Sendable {
    public static let messageType = "requestConditions"
    public static let typeKey = "type"
    public static let idKey = "id"
    public static let currentLocationRequestKey = "currentLocationRequest"

    public static func makeMessage(
        requestID: UUID,
        currentLocationRequest: WatchCurrentLocationRequestContext? = nil
    ) -> [String: Any] {
        var message: [String: Any] = [
            typeKey: messageType,
            idKey: requestID.uuidString
        ]
        if let currentLocationRequest,
           let data = try? JSONEncoder().encode(currentLocationRequest) {
            message[currentLocationRequestKey] = data
        }
        return message
    }
}
