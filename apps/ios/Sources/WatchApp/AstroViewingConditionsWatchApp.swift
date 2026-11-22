import SwiftUI
import SharedCode

@main
struct AstroViewingConditionsWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UnitSystemStorage.initializeIfNeeded()
        MigrationHelper.migrateIfNeeded()
        WatchAppRuntime.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .backgroundTask(.appRefresh(WatchBackgroundRefreshScheduler.appRefreshIdentifier)) {
            await WatchAppRuntime.handleAppRefresh()
        }
        // Astro Conditions 2.3.1 scheduled refreshes without an identifier.
        // The same handler schedules their successor with the current identifier.
        .backgroundTask(.appRefresh) { identifier in
            guard identifier == nil else { return }
            await WatchAppRuntime.handleAppRefresh()
        }
        .backgroundTask(.watchConnectivity) {
            await WatchAppRuntime.handleWatchConnectivity()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            WatchAppRuntime.handleScenePhase(phase)
        }
    }
}
