import Foundation

// MARK: - Transition result

/// Classification of a selected-location transition.
public enum WatchSelectedLocationTransitionKind: Sendable, Equatable {
    /// Identical to authoritative selection — no work.
    case noOp
    /// Display/persistence only (e.g. rename); no live claim, no conditions refresh.
    case displayOnly
    /// Material observing-location change — live claim + replacement refresh.
    case material
}

/// Immutable result of a serialized selected-location transition.
///
/// Produced under the transition coordinator lock; non-no-op transitions are
/// submitted to the applier **atomically under the same lock** so submission
/// order always matches classification / claim / authority-advance order.
/// Application remains publish → persist → optional phone send → refresh.
public struct WatchSelectedLocationTransition: Sendable, Equatable {
    /// Monotonic order of classified transitions (including no-ops that are not submitted).
    public let order: UInt64
    public let incoming: SelectedLocation
    public let kind: WatchSelectedLocationTransitionKind
    public let requiresPublication: Bool
    public let requiresPersistence: Bool
    /// Non-nil only for ``WatchSelectedLocationTransitionKind/material``.
    public let refreshToken: WatchConditionsLiveUpdateToken?
    public let sendToPhone: Bool

    public init(
        order: UInt64,
        incoming: SelectedLocation,
        kind: WatchSelectedLocationTransitionKind,
        requiresPublication: Bool,
        requiresPersistence: Bool,
        refreshToken: WatchConditionsLiveUpdateToken?,
        sendToPhone: Bool
    ) {
        self.order = order
        self.incoming = incoming
        self.kind = kind
        self.requiresPublication = requiresPublication
        self.requiresPersistence = requiresPersistence
        self.refreshToken = refreshToken
        self.sendToPhone = sendToPhone
    }

    public var isNoOp: Bool { kind == .noOp }
}

// MARK: - Coordinator

/// Serializes selected-location compare → optional live claim → authoritative advance
/// → **nonblocking applier submission**.
///
/// **Authority:** This coordinator’s locked `authoritativeSelection` is the sole
/// comparison source for remote/user transitions — **not** `@Published selectedLocation`.
///
/// **Atomic apply-and-submit:** Classification, order assignment, optional live claim,
/// authority advance, and `submit(transition)` all run while holding this lock.
/// Callers must not separately enqueue after return — that would reintroduce a
/// scheduling gap that can reorder submission relative to coordinator order.
///
/// **Lock order (only nested locks allowed):**
/// 1. Transition coordinator lock
/// 2. Live sequencer claim lock (via `claimRefresh`, brief)
/// 3. Applier serial-queue **submission** via nonblocking `queue.async` (via `submit`)
///
/// **Must never nest under this lock:**
/// - MainActor waiting
/// - Applier *execution* (publish / persist / send / refresh)
/// - Persistence, connectivity send, or refresh start
/// - Any `await`
/// - Coordinator re-entry (`submit` / `claimRefresh` must not call back into this type)
///
/// **Submit contract:** `submit` must only perform a nonblocking serial-queue enqueue.
/// It must not execute publication, wait on MainActor, wait on the applier queue,
/// re-enter this coordinator, claim another live token, or acquire locks in reverse order.
///
/// **No-ops:** Consume a transition.order but are **not** submitted. Later non-no-op
/// submissions remain correctly ordered without an applier order-gap buffer.
public final class WatchSelectedLocationTransitionCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var authoritativeSelection: SelectedLocation?
    private var order: UInt64 = 0

    public init(seed: SelectedLocation? = nil) {
        self.authoritativeSelection = seed
    }

    /// Latest transition-authority selection (thread-safe read).
    public var currentAuthoritative: SelectedLocation? {
        lock.lock()
        defer { lock.unlock() }
        return authoritativeSelection
    }

    /// Seed restored selection **only at initialization** (before remote callbacks).
    ///
    /// Synchronous; no claim, no submit. **Must not** be used on runtime refresh-failure
    /// paths — those use ``restoreIfUninitialized`` so a newer selection cannot be rolled back.
    public func seed(_ selection: SelectedLocation?) {
        lock.lock()
        authoritativeSelection = selection
        lock.unlock()
    }

    /// Remote / connectivity-driven transition (`forceRefresh: false`).
    ///
    /// Non-no-op transitions are submitted via `submit` **before** unlock.
    @discardableResult
    public func applyRemote(
        _ incoming: SelectedLocation,
        claimRefresh: () -> WatchConditionsLiveUpdateToken?,
        submit: (WatchSelectedLocationTransition) -> Void
    ) -> WatchSelectedLocationTransition {
        apply(
            incoming,
            forceRefresh: false,
            sendToPhone: false,
            claimRefresh: claimRefresh,
            submit: submit
        )
    }

    /// User-initiated selection (`forceRefresh: true`).
    ///
    /// Non-no-op transitions are submitted via `submit` **before** unlock.
    @discardableResult
    public func applyUser(
        _ incoming: SelectedLocation,
        sendToPhone: Bool,
        claimRefresh: () -> WatchConditionsLiveUpdateToken?,
        submit: (WatchSelectedLocationTransition) -> Void
    ) -> WatchSelectedLocationTransition {
        apply(
            incoming,
            forceRefresh: true,
            sendToPhone: sendToPhone,
            claimRefresh: claimRefresh,
            submit: submit
        )
    }

    /// Conditional runtime restore when authority is still uninitialized.
    ///
    /// Used by failed locations-list requests that find a cached selection but must
    /// **not** overwrite a selection established while the request was in flight.
    ///
    /// Under the coordinator lock:
    /// 1. If `authoritativeSelection != nil` → return `nil` (no claim, submit, or mutation).
    /// 2. If nil → classify `incoming` from nil as a normal remote-style transition,
    ///    claim/advance/submit atomically (no phone send).
    ///
    /// Never use ``seed`` for this path.
    @discardableResult
    public func restoreIfUninitialized(
        _ incoming: SelectedLocation,
        claimRefresh: () -> WatchConditionsLiveUpdateToken?,
        submit: (WatchSelectedLocationTransition) -> Void
    ) -> WatchSelectedLocationTransition? {
        lock.lock()
        // Early exit without consuming order when authority already exists.
        if authoritativeSelection != nil {
            lock.unlock()
            return nil
        }
        // Authority is nil — unlock is handled by applyLocked (called while locked).
        let transition = applyLocked(
            incoming,
            forceRefresh: false,
            sendToPhone: false,
            claimRefresh: claimRefresh,
            submit: submit
        )
        lock.unlock()
        return transition
    }

    // MARK: - Core

    private func apply(
        _ incoming: SelectedLocation,
        forceRefresh: Bool,
        sendToPhone: Bool,
        claimRefresh: () -> WatchConditionsLiveUpdateToken?,
        submit: (WatchSelectedLocationTransition) -> Void
    ) -> WatchSelectedLocationTransition {
        lock.lock()
        let transition = applyLocked(
            incoming,
            forceRefresh: forceRefresh,
            sendToPhone: sendToPhone,
            claimRefresh: claimRefresh,
            submit: submit
        )
        lock.unlock()
        return transition
    }

    /// Core classification / claim / advance / submit. Caller must hold `lock`.
    private func applyLocked(
        _ incoming: SelectedLocation,
        forceRefresh: Bool,
        sendToPhone: Bool,
        claimRefresh: () -> WatchConditionsLiveUpdateToken?,
        submit: (WatchSelectedLocationTransition) -> Void
    ) -> WatchSelectedLocationTransition {
        order &+= 1
        let transitionOrder = order
        let previous = authoritativeSelection

        let needsRefresh = WatchSelectedLocationMaterialIdentity.requiresConditionsRefresh(
            from: previous,
            to: incoming,
            forceRefresh: forceRefresh
        )
        let needsPersist = WatchSelectedLocationMaterialIdentity.requiresSelectionPersistence(
            from: previous,
            to: incoming
        )

        if !needsRefresh, !needsPersist {
            // No-op: order consumed, not submitted.
            return WatchSelectedLocationTransition(
                order: transitionOrder,
                incoming: incoming,
                kind: .noOp,
                requiresPublication: false,
                requiresPersistence: false,
                refreshToken: nil,
                sendToPhone: false
            )
        }

        let kind: WatchSelectedLocationTransitionKind = needsRefresh ? .material : .displayOnly
        var token: WatchConditionsLiveUpdateToken?
        if needsRefresh {
            // Nested live claim while holding transition lock — establishes claim order.
            // Fail closed: material change without a live token must not advance authority.
            guard let claimed = claimRefresh() else {
                return WatchSelectedLocationTransition(
                    order: transitionOrder,
                    incoming: incoming,
                    kind: .noOp,
                    requiresPublication: false,
                    requiresPersistence: false,
                    refreshToken: nil,
                    sendToPhone: false
                )
            }
            token = claimed
        }

        // Advance authority before submit/unlock so the next callback compares against `incoming`.
        authoritativeSelection = incoming

        let transition = WatchSelectedLocationTransition(
            order: transitionOrder,
            incoming: incoming,
            kind: kind,
            requiresPublication: true,
            requiresPersistence: needsPersist,
            refreshToken: token,
            sendToPhone: sendToPhone && needsPersist
        )

        // Atomic nonblocking submission — must complete before unlock so no later
        // transition can submit ahead of this one due to caller descheduling.
        // Contract: submit only enqueues; never runs application work.
        submit(transition)

        return transition
    }
}
