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
    let id: UUID?
    let name: String
    let coordinate: Coordinate?

    static let currentLocation = WatchLocationItem(id: nil, name: "Current Location", coordinate: nil)

    static func from(_ cached: CachedLocation) -> WatchLocationItem {
        WatchLocationItem(
            id: cached.id,
            name: cached.name,
            coordinate: cached.coordinate
        )
    }
    
    static func from(_ selected: SelectedLocation) -> WatchLocationItem {
        WatchLocationItem(
            id: selected.id,
            name: selected.name,
            coordinate: Coordinate(latitude: selected.latitude, longitude: selected.longitude)
        )
    }
    
    func toSelectedLocation() -> SelectedLocation {
        SelectedLocation(
            source: name == "Current Location" ? .currentGPS : .saved,
            id: id,
            name: name,
            latitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0
        )
    }
}
