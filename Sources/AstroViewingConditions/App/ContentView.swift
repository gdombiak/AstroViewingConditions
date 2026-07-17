import SharedCode
import SwiftUI

struct ContentView: View {
    fileprivate enum AppTab: String, Hashable, CaseIterable {
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
    @State private var dashboardLocationSession = DashboardLocationSession()
    @State private var dashboardViewModel = DashboardViewModel(
        apiKey: UserDefaults.standard.string(forKey: "n2yoApiKey") ?? ""
    )
    
    @ViewBuilder
    var body: some View {
        let isLandscape = verticalSizeClass == .compact
        let isRegular = horizontalSizeClass == .regular

        sharedRoot
        .dynamicTypeSize(isRegular ? .xxLarge : (isLandscape ? .large : .medium))
    }

    private var sharedRoot: some View {
        ZStack {
            tabContent(.dashboard) {
                DashboardView(
                    viewModel: dashboardViewModel,
                    locationSession: dashboardLocationSession
                )
            }

            tabContent(.locations) {
                LocationsView()
            }

            tabContent(.settings) {
                SettingsView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(
                tabs: AppTab.allCases,
                selection: $selectedTab,
                palette: palette
            )
        }
    }

    private func tabContent<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
    }
}

private struct AppTabBar<Tab: AppTabItem>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let tabs: [Tab]
    @Binding var selection: Tab
    let palette: AppPalette

    private var metrics: AppTabBarMetrics {
        horizontalSizeClass == .regular ? .regularWidth : .compactWidth
    }

    var body: some View {
        HStack(spacing: metrics.itemSpacing) {
            ForEach(tabs, id: \.self) { tab in
                let isSelected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: metrics.labelSpacing) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: metrics.iconSize, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
                            .font(metrics.labelFont)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                    .foregroundStyle(
                        foregroundStyle(isSelected: isSelected)
                    )
                    .frame(maxWidth: .infinity, minHeight: metrics.itemMinHeight)
                    .background(selectedBackground(isSelected: isSelected))
                    .clipShape(Capsule())
                    .overlay {
                        if isSelected {
                            Capsule().stroke(selectedBorder, lineWidth: 1)
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
        .frame(maxWidth: metrics.maxWidth)
        .frame(height: metrics.height)
        .background(containerBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: 12, y: 5)
        .padding(.horizontal, metrics.horizontalInset)
        .padding(.vertical, metrics.verticalInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab Bar")
    }

    private var containerBackground: some ShapeStyle {
        if palette.appearance == .field {
            return AnyShapeStyle(palette.tabBarBackground)
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var selectedBorder: Color {
        palette.appearance == .field ? palette.accent.opacity(0.55) : .clear
    }

    private var shadowColor: Color {
        palette.appearance == .field ? .black.opacity(0.28) : .black.opacity(0.16)
    }

    private func foregroundStyle(isSelected: Bool) -> Color {
        if palette.appearance == .field {
            return isSelected ? palette.selectedControlText : palette.unselectedControlText
        }
        return isSelected ? palette.accent : palette.unselectedControlText
    }

    private func selectedBackground(isSelected: Bool) -> Color {
        guard isSelected, palette.appearance == .field else { return .clear }
        return palette.selectedControlBackground
    }
}

private protocol AppTabItem: Hashable {
    var title: String { get }
    var systemImage: String { get }
}

private struct AppTabBarMetrics {
    let maxWidth: CGFloat
    let horizontalInset: CGFloat
    let verticalInset: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let itemSpacing: CGFloat
    let itemMinHeight: CGFloat
    let iconSize: CGFloat
    let labelSpacing: CGFloat
    let labelFont: Font

    static let compactWidth = AppTabBarMetrics(
        maxWidth: 300,
        horizontalInset: 16,
        verticalInset: 0,
        height: 56,
        cornerRadius: 28,
        itemSpacing: 8,
        itemMinHeight: 52,
        iconSize: 18,
        labelSpacing: 3,
        labelFont: .caption2
    )

    static let regularWidth = AppTabBarMetrics(
        maxWidth: 420,
        horizontalInset: 24,
        verticalInset: 0,
        height: 68,
        cornerRadius: 34,
        itemSpacing: 12,
        itemMinHeight: 64,
        iconSize: 22,
        labelSpacing: 4,
        labelFont: .caption
    )
}

extension ContentView.AppTab: AppTabItem {}

#Preview {
    ContentView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
