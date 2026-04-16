import SwiftUI
import SharedCode

@main
struct AstroViewingConditionsWatchApp: App {
    init() {
        UnitSystemStorage.initializeIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}