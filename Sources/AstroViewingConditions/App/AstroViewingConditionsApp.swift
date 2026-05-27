import SwiftUI
import SwiftData
import SharedCode

@main
struct AstroViewingConditionsApp: App {
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    init() {
        UnitSystemStorage.initializeIfNeeded()
        MigrationHelper.migrateIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedLocation.self, inMemory: Self.isRunningUnitTests)
    }
}
