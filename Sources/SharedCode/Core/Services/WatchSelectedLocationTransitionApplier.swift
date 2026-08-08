import Foundation

/// FIFO application of selected-location transitions.
///
/// **Order for every non-no-op transition (remote and user):**
/// 1. MainActor `selectedLocation` publication
/// 2. Persistence
/// 3. Optional phone send
/// 4. Replacement refresh with the transition’s preclaimed token
///
/// Classification, live claim, and **submission** happen in
/// ``WatchSelectedLocationTransitionCoordinator`` under one lock. This type only
/// applies work already submitted in coordinator order.
///
/// **`enqueue` is nonblocking:** returns immediately after `queue.async`.
/// Test hooks (`beforePublication`, etc.) run only during application on the
/// serial queue — never synchronously inside `enqueue`.
///
/// **Deadlock:** The serial queue waits for MainActor only via `main.async` + `DispatchGroup`.
/// Callers (including under the coordinator lock) must only **submit** via `enqueue`
/// and return — they must never wait on this queue.
///
/// **DispatchGroup leave:** `publishOnMain` always leaves the group on MainActor after
/// invoking `publish`, independent of weak-self behavior in the publish closure.
/// Weak-self loss on the apply queue before `publishOnMain` never leaves a group entered.
public final class WatchSelectedLocationTransitionApplier: @unchecked Sendable {
    private let queue: DispatchQueue

    /// Invoked on the apply queue immediately **before** MainActor publication is scheduled.
    /// Production: nil. Tests may block here with a semaphore (still not under a claim lock).
    public var beforePublication: ((WatchSelectedLocationTransition) -> Void)?

    /// Invoked on the apply queue immediately **after** MainActor publication completes.
    public var afterPublication: ((WatchSelectedLocationTransition) -> Void)?

    /// Invoked on the apply queue immediately before `startRefresh` (after persist/send).
    public var beforeRefresh: ((WatchSelectedLocationTransition) -> Void)?

    /// Invoked on the apply queue when a block begins (tests: prove enqueue did not run work).
    public var onBeginApplication: ((WatchSelectedLocationTransition) -> Void)?

    public init(
        label: String = "com.astroviewing.conditions.watch.selection.transition.apply"
    ) {
        self.queue = DispatchQueue(label: label)
    }

    /// Bundles application callbacks for cross-queue transfer (FIFO serial use only).
    private struct Actions: @unchecked Sendable {
        let publish: (SelectedLocation) -> Void
        let persist: (SelectedLocation) -> Void
        let sendToPhone: (SelectedLocation) -> Void
        let startRefresh: (SelectedLocation, WatchConditionsLiveUpdateToken) -> Void
    }

    /// Enqueue a transition for FIFO application. No-ops are ignored.
    ///
    /// Returns immediately after scheduling work on the serial queue. Never runs
    /// publication, persistence, send, or refresh synchronously.
    ///
    /// Safe to call while holding the transition coordinator lock (nonblocking only).
    ///
    /// - Parameters:
    ///   - publish: Called **on MainActor** to assign `@Published selectedLocation`.
    ///   - persist: Called on the apply queue after publication.
    ///   - sendToPhone: Called on the apply queue when `transition.sendToPhone`.
    ///   - startRefresh: Called on the apply queue after publication + persistence.
    public func enqueue(
        _ transition: WatchSelectedLocationTransition,
        publish: @escaping (SelectedLocation) -> Void,
        persist: @escaping (SelectedLocation) -> Void,
        sendToPhone: @escaping (SelectedLocation) -> Void,
        startRefresh: @escaping (SelectedLocation, WatchConditionsLiveUpdateToken) -> Void
    ) {
        guard !transition.isNoOp else { return }

        let actions = Actions(
            publish: publish,
            persist: persist,
            sendToPhone: sendToPhone,
            startRefresh: startRefresh
        )

        // Nonblocking: only schedules. Must not wait on MainActor or this queue.
        queue.async { [weak self] in
            guard let self else { return }

            self.onBeginApplication?(transition)

            if transition.requiresPublication {
                self.beforePublication?(transition)
                self.publishOnMain(transition.incoming, publish: actions.publish)
                self.afterPublication?(transition)
            }

            if transition.requiresPersistence {
                actions.persist(transition.incoming)
            }

            if transition.sendToPhone {
                actions.sendToPhone(transition.incoming)
            }

            if let token = transition.refreshToken {
                self.beforeRefresh?(transition)
                actions.startRefresh(transition.incoming, token)
            }
        }
    }

    /// Publish on MainActor and wait until the assignment has completed.
    ///
    /// Must only be called from the apply queue (never from MainActor waiting on apply queue).
    ///
    /// `group.leave()` is owned by this method and always runs after `publish`, even if
    /// a weak-self publish closure no-ops.
    private func publishOnMain(
        _ location: SelectedLocation,
        publish: @escaping (SelectedLocation) -> Void
    ) {
        let group = DispatchGroup()
        group.enter()
        // Capture publish strongly for the MainActor hop; leave is unconditional.
        let publishAction = Actions(
            publish: publish,
            persist: { _ in },
            sendToPhone: { _ in },
            startRefresh: { _, _ in }
        )
        DispatchQueue.main.async {
            // Always leave after publish attempt — never skip leave for weak-self.
            publishAction.publish(location)
            group.leave()
        }
        // Apply queue blocks until MainActor assignment finishes — keeps FIFO publish order.
        group.wait()
    }
}
