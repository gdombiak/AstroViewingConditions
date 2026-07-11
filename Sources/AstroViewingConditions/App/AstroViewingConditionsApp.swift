import SwiftUI
import SwiftData
import SharedCode

@main
struct AstroViewingConditionsApp: App {
    @AppStorage(FieldModePreference.key) private var fieldModeEnabled = FieldModePreference.defaultValue

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
                .appAppearance(fieldModeEnabled: fieldModeEnabled)
        }
        .modelContainer(for: SavedLocation.self, inMemory: Self.isRunningUnitTests)
    }
}
