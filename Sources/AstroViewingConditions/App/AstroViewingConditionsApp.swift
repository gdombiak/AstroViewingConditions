import SwiftUI
import SwiftData

@main
struct AstroViewingConditionsApp: App {
    init() {
        UserDefaults.standard.initializeUnitSystemIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedLocation.self)
    }
}
