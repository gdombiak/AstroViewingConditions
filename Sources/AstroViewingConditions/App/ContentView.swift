import SharedCode
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    var body: some View {
        let isLandscape = verticalSizeClass == .compact
        let isRegular = horizontalSizeClass == .regular
        
        return TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "star.fill")
                }
            
            LocationsView()
                .tabItem {
                    Label("Locations", systemImage: "mappin.and.ellipse")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .dynamicTypeSize(isRegular ? .xxLarge : (isLandscape ? .large : .medium))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
