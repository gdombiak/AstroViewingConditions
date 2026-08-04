import Foundation

/// One-time activation of selected-location connectivity delivery + conditions-change handling.
///
/// ## State machine
/// - ``State/inactive``: no connectivity selection delivery; no runtime selection should be accepted
/// - ``State/activating``: handler installed and usable; `registerDelegate` may be in flight
///   (including synchronous callbacks during registration)
/// - ``State/active``: delegate registered; selection delivery fully enabled
///
/// ## Linearization
/// Handler is stored and state becomes `activating` **before** `registerDelegate` runs, so any
/// synchronous callback during registration observes a valid handler.
///
/// `registerDelegate` is **never** called under the activation lock (avoids re-entry deadlock if
/// registration synchronously delivers selection events).
///
/// ## Exactly once
/// Only the first successful activation from `inactive` invokes `registerDelegate`.
/// Same-handler re-activation is idempotent. Different-handler re-activation is rejected.
public final class WatchSelectionHandlingActivation: @unchecked Sendable {
    public enum State: Sendable, Equatable {
        case inactive
        case activating
        case active
    }

    public enum ActivationResult: Sendable, Equatable {
        case activated
        case alreadyActive
        case rejectedDifferentHandler
    }

    private let lock = NSLock()
    private var state: State = .inactive
    private weak var handler: (any WatchSelectedLocationChangeHandling)?
    private var attachedHandlerID: ObjectIdentifier?

    public init() {}

    public var currentState: State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Currently attached handler (weak). Non-nil only when activating or active.
    public var currentHandler: (any WatchSelectedLocationChangeHandling)? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    /// Whether selection transitions may proceed (handler installed; delivery enabling or active).
    public var isSelectionDeliveryEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .activating || state == .active
    }

    /// Install `handler`, then invoke `registerDelegate` exactly once from `inactive`.
    ///
    /// - Parameter registerDelegate: Must register the location manager as a connectivity
    ///   delegate. May synchronously deliver callbacks; handler is already installed.
    @discardableResult
    public func activate(
        handler newHandler: any WatchSelectedLocationChangeHandling,
        registerDelegate: () -> Void
    ) -> ActivationResult {
        let newID = ObjectIdentifier(newHandler as AnyObject)

        lock.lock()
        switch state {
        case .active, .activating:
            if attachedHandlerID == newID {
                // Refresh weak reference in case it was cleared (should not happen with live owner).
                handler = newHandler
                lock.unlock()
                return .alreadyActive
            }
            lock.unlock()
            // Reject replacement without trapping — production composition root must not replace.
            #if DEBUG
            print(
                "WatchSelectionHandlingActivation: rejected different-handler reactivation"
            )
            #endif
            return .rejectedDifferentHandler

        case .inactive:
            handler = newHandler
            attachedHandlerID = newID
            state = .activating
            lock.unlock()
        }

        // Outside lock: registration may re-enter selection paths that take activation lock.
        registerDelegate()

        lock.lock()
        // Only promote to active if we still own this activation (same handler).
        if attachedHandlerID == newID, state == .activating {
            state = .active
        }
        lock.unlock()
        return .activated
    }

    /// Snapshot handler when delivery is enabled. Fail-closed if inactive or deallocated.
    public func resolvedHandlerForTransition() -> (any WatchSelectedLocationChangeHandling)? {
        lock.lock()
        defer { lock.unlock() }
        guard state == .activating || state == .active else {
            return nil
        }
        return handler
    }
}
