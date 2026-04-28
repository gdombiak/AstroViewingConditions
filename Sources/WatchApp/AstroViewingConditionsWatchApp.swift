import SwiftUI
import SharedCode

@main
struct AstroViewingConditionsWatchApp: App {
    init() {
        UnitSystemStorage.initializeIfNeeded()
        MigrationHelper.migrateIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}