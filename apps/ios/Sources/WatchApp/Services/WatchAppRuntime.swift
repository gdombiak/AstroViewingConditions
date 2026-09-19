import Foundation
import SwiftUI

/// Watch-app composition root for connectivity + background liveness.
///
/// `WindowGroup` content is not guaranteed to load for background launches, so managers
/// and `WCSession` must be started here — not from `WatchDashboardView`.
enum WatchAppRuntime {
    /// Activate session and seed managers. Must not call `scheduleBackgroundRefresh`:
    /// `WKApplication` is not ready during SwiftUI `App.init()`.
    @MainActor
    static func bootstrap() {
        _ = WatchConditionsManager.shared
    }

    /// First foreground `.active` after launch — seeds the refresh chain once per process
    /// if `.appRefresh` has not already scheduled a successor.
    @MainActor
    static func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        WatchBackgroundRefreshScheduler.scheduleInitialIfNeeded()
    }

    /// Scheduled `WKApplication` refresh: reuse the existing conditions refresh path.
    /// Schedule the successor first so cancellation cannot drop the chain.
    static func handleAppRefresh() async {
        await WatchBackgroundRefreshScheduler.scheduleNext()
        await WatchConnectivityManager.shared.processPendingApplicationContext()
        await WatchConditionsManager.shared.refreshIfNeeded()
    }

    /// Connectivity background runtime: apply the latest snapshot, then refresh if needed.
    static func handleWatchConnectivity() async {
        await WatchConnectivityManager.shared.processPendingApplicationContext()
        await WatchConditionsManager.shared.refreshIfNeeded()
        await WatchBackgroundRefreshScheduler.scheduleNext()
    }
}
