import SwiftUI
import SharedCode

struct ContentView: View {
    var body: some View {
        WatchDashboardView()
            .task {
                WatchLocationManager.shared.refresh()
            }
    }
}

struct WatchLocationItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: Coordinate?

    static let currentLocation = WatchLocationItem(name: "Current Location", coordinate: nil)

    static func from(_ cached: CachedLocation) -> WatchLocationItem {
        WatchLocationItem(
            name: cached.name,
            coordinate: cached.coordinate
        )
    }
}
