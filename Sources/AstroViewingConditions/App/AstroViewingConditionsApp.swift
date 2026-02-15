import SwiftUI
import SwiftData

@main
struct AstroViewingConditionsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedLocation.self)
    }
}
