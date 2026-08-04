import Foundation

/// Production live-event ingress used by the watch manager.
///
/// **Ordering contract:** ``receive`` / ``beginRefresh`` call ``claimLiveUpdate()``
/// **synchronously** on the calling thread before any unstructured `Task` is created.
/// Unstructured Task execution order may differ from arrival order; the claimed token
/// already encodes arrival order, so later processing cannot become “newer.”
public struct WatchConditionsLiveEventIngress: Sendable {
    private let claim: @Sendable () -> WatchConditionsLiveUpdateToken

    public init(claiming: any WatchLiveIngressClaiming) {
        // Capture nonisolated claim for synchronous use.
        self.claim = { claiming.claimLiveUpdate() }
    }

    public init(claim: @escaping @Sendable () -> WatchConditionsLiveUpdateToken) {
        self.claim = claim
    }

    /// Claim live sequence for a pushed conditions event (call at WC callback receipt).
    public func claimPushIngress() -> WatchConditionsLiveUpdateToken {
        claim()
    }

    /// Claim live sequence for a refresh (call as the first step of refresh, before any await).
    public func claimRefreshIngress() -> WatchConditionsLiveUpdateToken {
        claim()
    }

    /// Schedule async processing that carries a **pre-claimed** token.
    /// Task run order is irrelevant to live ordering.
    public func scheduleProcessing(
        _ work: @escaping @Sendable () async -> Void
    ) {
        Task {
            await work()
        }
    }
}
