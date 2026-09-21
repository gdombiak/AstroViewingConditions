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
            // Field Mode ownership lives in a View, not on the App struct (see FieldModeRootView).
            FieldModeRootView {
                ContentView()
            }
        }
        .modelContainer(for: [SavedLocation.self, EquipmentItem.self], inMemory: Self.isRunningUnitTests)
    }
}
