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
        .backgroundTask(.appRefresh) { _ in
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