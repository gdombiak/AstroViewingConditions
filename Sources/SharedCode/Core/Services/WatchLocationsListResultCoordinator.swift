import Foundation

// MARK: - Result kinds

/// Immutable payload for one locations-list outcome (refresh success/failure or connectivity push).
public enum WatchLocationsListResultKind: Sendable {
    /// Phone reply with a locations list and optional selected location.
    case success(locations: [CachedLocation], selected: SelectedLocation?)
    /// Phone request failed; apply cached list. Selection restore is decided at acceptance.
    case failure(cachedLocations: [CachedLocation], cachedSelected: SelectedLocation?)
    /// Unsolicited connectivity push of locations (+ optional selection).
    case connectivityPush(locations: [CachedLocation], selected: SelectedLocation?)

    /// Selected location carried for remote-style transition (success / push), if any.
    public var remoteSelected: SelectedLocation? {
        switch self {
        case .success(_, let selected), .connectivityPush(_, let selected):
            return selected
        case .failure:
            return nil
        }
    }

    /// Cached selected for conditional restore (failure only).
    public var failureCachedSelected: SelectedLocation? {
        switch self {
        case .failure(_, let cachedSelected):
            return cachedSelected
        case .success, .connectivityPush:
            return nil
        }
    }

    /// Locations list to publish (and persist for success/push).
    public var locationsToPublish: [CachedLocation] {
        switch self {
        case .success(let locations, _), .connectivityPush(let locations, _):
            return locations
        case .failure(let cached, _):
            return cached
        }
    }

    public var shouldPersistList: Bool {
        switch self {
        case .success, .connectivityPush: return true
        case .failure: return false
        }
    }
}

/// Result that has passed the atomic accept boundary and may be applied (list/loading only).
///
/// **Linearization of list results:** Acceptance order is total. Already-accepted results are
/// never cancelled by a later `beginRefresh()`. They apply FIFO; a later accepted result
/// supersedes list UI/storage.
///
/// **Selected-location order** is reserved **during acceptance** via `prepareSelection`, not
/// during list application. See ``WatchLocationsListResultCoordinator``.
public struct WatchLocationsListAcceptedResult: Sendable {
    /// Epoch that began the request or push.
    public let epoch: UInt64
    /// Monotonic acceptance order (list application FIFO key).
    public let acceptOrder: UInt64
    public let kind: WatchLocationsListResultKind

    public init(
        epoch: UInt64,
        acceptOrder: UInt64,
        kind: WatchLocationsListResultKind
    ) {
        self.epoch = epoch
        self.acceptOrder = acceptOrder
        self.kind = kind
    }
}

// MARK: - Coordinator

/// Authorizes locations-list side effects and **reserves selected-location event order** at accept.
///
/// ## Cross-state-machine linearization (accepted result)
/// 1. Validate epoch / claim push epoch under list lock
/// 2. Assign list accept order
/// 3. **`prepareSelection`** — must enter ``WatchSelectedLocationIngressCoordinator`` then
///    selected-location transition apply-and-submit (nests locks below)
/// 4. Nonblocking **list** applier submit
/// 5. Unlock list coordinator
/// 6. Selected and list appliers run independently in their established FIFO orders
///
/// Temporary UI divergence is allowed (list faster than selection or vice versa). Authoritative
/// selection order and final list order remain correct.
///
/// **Formal selected-location order** is shared-ingress acquisition order (not list accept alone).
/// User and standalone remote paths use the same ingress lock as `prepareSelection`.
///
/// ## Loading ownership
/// - ``beginRefresh()`` assigns `loadingOwner = newEpoch` and returns that epoch.
/// - Connectivity push acceptance also claims loading ownership for its epoch.
/// - Clearing `isLoading` must use ``clearLoadingIfOwner(_:mutate:)`` **on MainActor**, where
///   ownership check and mutation are one protected boundary (no check-then-await).
/// - An older accepted result may still publish its list but **cannot** clear loading owned by a
///   newer refresh/push.
/// - Loading clear must **not** enter selected-location ingress while holding the list lock.
///
/// ## Lock order (only nested locks allowed)
/// 1. Locations-list result coordinator lock
/// 2. Shared selected-location **ingress** lock (via `prepareSelection`)
/// 3. Selected-location transition coordinator lock
/// 4. Live sequencer claim lock
/// 5. Nonblocking selected-applier `queue.async`
/// 6. Nonblocking list-applier `queue.async`
///
/// **Must never reverse:** ingress / selection / live / appliers must not acquire the list-result lock.
/// **Never under coordinator locks:** MainActor wait, persistence I/O, connectivity send, await.
///
/// ## Guaranteed submission
/// `prepareSelection` and `submit` are invoked **synchronously** while still holding the list
/// lock. Callers must use a strong capture for those synchronous enqueues so acceptance cannot
/// be recorded without enqueue. Async applier action closures may use weak self.
public final class WatchLocationsListResultCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var acceptOrder: UInt64 = 0
    /// Epoch currently allowed to clear `isLoading` (0 = none).
    private var loadingOwner: UInt64 = 0

    public init() {}

    /// Latest list epoch (tests / diagnostics).
    public var currentEpoch: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    /// Current loading owner epoch (tests / diagnostics).
    public var currentLoadingOwner: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return loadingOwner
    }

    /// Start a refresh: new list epoch **and** loading owner in one lock.
    ///
    /// Call before publishing `isLoading = true` so older accepted results cannot clear the new
    /// owner's loading.
    @discardableResult
    public func beginRefresh() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        loadingOwner = generation
        return generation
    }

    /// Accept a refresh success/failure if `epoch` is still current.
    ///
    /// Under lock: prepare selection (if any) → nonblocking list submit.
    @discardableResult
    public func acceptIfCurrent(
        epoch: UInt64,
        kind: WatchLocationsListResultKind,
        prepareSelection: (WatchLocationsListResultKind) -> Void,
        submit: (WatchLocationsListAcceptedResult) -> Void
    ) -> WatchLocationsListAcceptedResult? {
        lock.lock()
        guard epoch == generation else {
            lock.unlock()
            return nil
        }
        acceptOrder &+= 1
        let accepted = WatchLocationsListAcceptedResult(
            epoch: epoch,
            acceptOrder: acceptOrder,
            kind: kind
        )
        // Reserve selected-location event order before list enqueue and before unlock.
        prepareSelection(kind)
        // Nonblocking list submit — acceptance order ≡ list submission order.
        submit(accepted)
        lock.unlock()
        return accepted
    }

    /// Connectivity push: new epoch, claim loading ownership, prepare selection, submit list.
    @discardableResult
    public func acceptConnectivityPush(
        locations: [CachedLocation],
        selected: SelectedLocation?,
        prepareSelection: (WatchLocationsListResultKind) -> Void,
        submit: (WatchLocationsListAcceptedResult) -> Void
    ) -> WatchLocationsListAcceptedResult {
        lock.lock()
        generation &+= 1
        let epoch = generation
        // Push terminates in-flight refresh loading ownership.
        loadingOwner = epoch
        acceptOrder &+= 1
        let kind = WatchLocationsListResultKind.connectivityPush(
            locations: locations,
            selected: selected
        )
        let accepted = WatchLocationsListAcceptedResult(
            epoch: epoch,
            acceptOrder: acceptOrder,
            kind: kind
        )
        prepareSelection(kind)
        submit(accepted)
        lock.unlock()
        return accepted
    }

    /// Clear loading only if `epoch` still owns loading.
    ///
    /// **Must be called on MainActor.** Locks, verifies owner, runs `mutate` under the lock.
    /// Does not dispatch or wait on MainActor itself.
    @discardableResult
    public func clearLoadingIfOwner(
        _ epoch: UInt64,
        mutate: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard loadingOwner == epoch else {
            return false
        }
        mutate()
        return true
    }
}

// MARK: - Applier

/// FIFO application of **list/loading** effects for accepted locations-list results.
///
/// Selection is **not** applied here — it was reserved at acceptance via `prepareSelection`.
///
/// **Order for every accepted result:**
/// 1. Persist list when kind is success/push
/// 2. MainActor: publish `locations` and ownership-aware loading clear
public final class WatchLocationsListResultApplier: @unchecked Sendable {
    private let queue: DispatchQueue

    /// Test hook: runs on apply queue before any side effect.
    public var beforeApplication: ((WatchLocationsListAcceptedResult) -> Void)?

    /// Test hook: after MainActor list/loading publication.
    public var afterListPublication: ((WatchLocationsListAcceptedResult) -> Void)?

    public init(
        label: String = "com.astroviewing.conditions.watch.locations.list.apply"
    ) {
        self.queue = DispatchQueue(label: label)
    }

    private struct Actions: @unchecked Sendable {
        let persistList: ([CachedLocation]) -> Void
        let publishListOnMain: (WatchLocationsListAcceptedResult) -> Void
    }

    /// Enqueue an accepted result. Returns immediately after `queue.async`.
    ///
    /// - Parameters:
    ///   - publishListOnMain: Invoked on MainActor. Should publish locations and call
    ///     ``WatchLocationsListResultCoordinator/clearLoadingIfOwner(_:mutate:)`` for the result epoch.
    public func enqueue(
        _ result: WatchLocationsListAcceptedResult,
        persistList: @escaping ([CachedLocation]) -> Void,
        publishListOnMain: @escaping (WatchLocationsListAcceptedResult) -> Void
    ) {
        let actions = Actions(
            persistList: persistList,
            publishListOnMain: publishListOnMain
        )

        queue.async { [weak self] in
            guard let self else { return }

            self.beforeApplication?(result)

            if result.kind.shouldPersistList {
                actions.persistList(result.kind.locationsToPublish)
            }
            self.publishOnMain(result, publish: actions.publishListOnMain)
            self.afterListPublication?(result)
        }
    }

    private func publishOnMain(
        _ result: WatchLocationsListAcceptedResult,
        publish: @escaping (WatchLocationsListAcceptedResult) -> Void
    ) {
        let group = DispatchGroup()
        group.enter()
        // Strong capture of publish; leave is unconditional.
        let publishAction = Actions(
            persistList: { _ in },
            publishListOnMain: publish
        )
        DispatchQueue.main.async {
            publishAction.publishListOnMain(result)
            group.leave()
        }
        group.wait()
    }
}
