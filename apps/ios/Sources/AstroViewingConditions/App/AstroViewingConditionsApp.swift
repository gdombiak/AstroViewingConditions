import SwiftUI
import SwiftData
import SharedCode

@main
struct AstroViewingConditionsApp: App {
    @State private var unitSystemPreference: UnitSystemPreference

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    init() {
        UnitSystemStorage.initializeIfNeeded()
        MigrationHelper.migrateIfNeeded()
        _unitSystemPreference = State(initialValue: UnitSystemPreference(
            selection: UnitSystemStorage.loadSelectedUnitSystem(),
            onChange: { selection in
                UnitSystemStorage.saveSelectedUnitSystem(selection)
                WatchConnectivityService.shared.sendUnitSystemToWatch(selection)
            }
        ))
    }
    
    var body: some Scene {
        WindowGroup {
            // Field Mode ownership lives in a View, not on the App struct (see FieldModeRootView).
            FieldModeRootView {
                ContentView(unitSystemPreference: unitSystemPreference)
            }
        }
        .modelContainer(for: [SavedLocation.self, EquipmentItem.self], inMemory: Self.isRunningUnitTests)
    }
}
