import SharedCode
import SwiftUI

struct ContentView: View {
    private enum FieldTabBarLayout {
        static let maxWidth: CGFloat = 300
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 0
        static let height: CGFloat = 56
        static let cornerRadius: CGFloat = 28
    }

    private enum AppTab: String, Hashable, CaseIterable {
        case dashboard
        case locations
        case settings

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .locations: "Locations"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard: "star.fill"
            case .locations: "mappin.and.ellipse"
            case .settings: "gear"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.appPalette) private var palette
    @SceneStorage("selectedAppTab") private var selectedTab: AppTab = .dashboard
    
    @ViewBuilder
    var body: some View {
        let isLandscape = verticalSizeClass == .compact
        let isRegular = horizontalSizeClass == .regular

        Group {
            if palette.appearance == .field {
                fieldModeRoot
            } else {
                normalTabView
            }
        }
        .dynamicTypeSize(isRegular ? .xxLarge : (isLandscape ? .large : .medium))
    }

    private var normalTabView: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "star.fill")
                }
                .tag(AppTab.dashboard)

            LocationsView()
                .tabItem {
                    Label("Locations", systemImage: "mappin.and.ellipse")
                }
                .tag(AppTab.locations)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
    }

    private var fieldModeRoot: some View {
        selectedFieldTabContent
        .safeAreaInset(edge: .bottom, spacing: 0) {
            fieldTabBar
        }
    }

    @ViewBuilder
    private var selectedFieldTabContent: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .locations:
            LocationsView()
        case .settings:
            SettingsView()
            }
    }

    private var fieldTabBar: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
                            .font(.caption2)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                    .foregroundStyle(
                        isSelected ? palette.selectedControlText : palette.unselectedControlText
                    )
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(isSelected ? palette.selectedControlBackground : Color.clear)
                    .clipShape(Capsule())
                    .overlay {
                        if isSelected {
                            Capsule().stroke(palette.accent.opacity(0.55), lineWidth: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(isSelected ? "Selected tab" : "Tab")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(maxWidth: FieldTabBarLayout.maxWidth)
        .frame(height: FieldTabBarLayout.height)
        .background(palette.tabBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: FieldTabBarLayout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: FieldTabBarLayout.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        .padding(.horizontal, FieldTabBarLayout.horizontalInset)
        .padding(.vertical, FieldTabBarLayout.verticalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab Bar")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
