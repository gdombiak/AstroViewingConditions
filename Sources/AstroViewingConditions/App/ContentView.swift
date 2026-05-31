import SharedCode
import SwiftUI
import WidgetKit

final class WidgetReloadListener: NSObject, ObservableObject {
    private var debounceWorkItem: DispatchWorkItem?
    private var observerTokens: [NSObjectProtocol] = []
    let debounceDelay: UInt64 = 500_000_000 // 0.5 seconds
    
    override init() {
        super.init()
        setupNotificationObservers()
    }

    deinit {
        debounceWorkItem?.cancel()
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }
    
    private func setupNotificationObservers() {
        let selectedLocationToken = NotificationCenter.default.addObserver(
            forName: .selectedLocationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onWidgetDataChanged()
        }
        
        let widgetConditionsToken = NotificationCenter.default.addObserver(
            forName: .widgetConditionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onWidgetDataChanged()
        }
        
        observerTokens = [selectedLocationToken, widgetConditionsToken]
    }

    private func onWidgetDataChanged() {
        debounceWorkItem?.cancel()
        debounceWorkItem = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "NightConditionsWidget")
        }
        if let workItem = debounceWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(debounceDelay)), execute: workItem)
        }
    }
}

struct ContentView: View {
    @StateObject private var widgetListener = WidgetReloadListener()
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
