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
    @Environment(\.appPalette) private var palette
    @SceneStorage("selectedAppTab") private var selectedTab: AppTab = .dashboard
    @State private var dashboardLocationSession = DashboardLocationSession()
    /// Process composition: owns LPATLAS1 readiness for this app process (not a feature view).
    @State private var observingQualitySession: ObservingQualitySession
    @State private var dashboardViewModel: DashboardViewModel
    @State private var didStartObservingQualityBootstrap = false

    init() {
        let session = ObservingQualitySession()
        _observingQualitySession = State(initialValue: session)
        _dashboardViewModel = State(
            initialValue: DashboardViewModel(
                apiKey: UserDefaults.standard.string(forKey: "n2yoApiKey") ?? "",
                observingQualityEnvironment: session
            )
        )
    }
    
    var body: some View {
        sharedRoot
            .task {
                // Composition-root bootstrap: parallel to user navigation; not owned by DashboardView.
                guard !didStartObservingQualityBootstrap else { return }
                didStartObservingQualityBootstrap = true
                await observingQualitySession.bootstrap(preferredBundles: [Bundle.main])
                dashboardViewModel.syncLightPollutionReadinessFromEnvironment()

                // Phase 2: backfill durable saved-location modeled-brightness metadata.
                // Stamp revision before awaiting provider so a concurrent CRUD publication
                // (higher revision) is never overwritten by this backfill.
                // Provider already loaded by bootstrap — do not start another atlas load.
                let cached = LocationStorageService.shared.getSavedLocations(context: modelContext)
                let anchors = cached.compactMap(SavedLocationBrightnessAnchor.init(cachedLocation:))
                let publication = SavedLocationBrightnessPublication.makeAuthoritative(
                    locations: anchors
                )
                let provider = await LightPollutionProviderBootstrap.shared.currentProvider()
                await SavedLocationModeledBrightnessCoordinator.shared.synchronize(
                    publication: publication,
                    provider: provider
                )
            }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let tabs: [Tab]
    @Binding var selection: Tab
    let palette: AppPalette

    private var metrics: AppTabBarMetrics {
        horizontalSizeClass == .regular ? .regularWidth : .compactWidth
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.requiresExpandedCompactLayout
    }

    private var maximumWidth: CGFloat {
        usesAccessibilityLayout ? metrics.accessibilityMaxWidth : metrics.maxWidth
    }

    private var horizontalInset: CGFloat {
        usesAccessibilityLayout ? metrics.accessibilityHorizontalInset : metrics.horizontalInset
    }

    private var itemSpacing: CGFloat {
        usesAccessibilityLayout ? metrics.accessibilityItemSpacing : metrics.itemSpacing
    }

    var body: some View {
        HStack(spacing: itemSpacing) {
            ForEach(tabs, id: \.self) { tab in
                let isSelected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: metrics.labelSpacing) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: metrics.iconSize, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
                            .font(.caption)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .multilineTextAlignment(.center)
                            .lineLimit(usesAccessibilityLayout ? 2 : nil)
                    }
                    .foregroundStyle(
                        foregroundStyle(isSelected: isSelected)
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: metrics.itemMinHeight
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: usesAccessibilityLayout
                    )
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
        .frame(maxWidth: maximumWidth)
        .frame(minHeight: metrics.minHeight)
        .background(containerBackground)
        .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        }
        .shadow(color: shadowColor, radius: 12, y: 5)
        .padding(.horizontal, horizontalInset)
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
    let accessibilityMaxWidth: CGFloat
    let horizontalInset: CGFloat
    let accessibilityHorizontalInset: CGFloat
    let verticalInset: CGFloat
    let minHeight: CGFloat
    let cornerRadius: CGFloat
    let itemSpacing: CGFloat
    let accessibilityItemSpacing: CGFloat
    let itemMinHeight: CGFloat
    let iconSize: CGFloat
    let labelSpacing: CGFloat

    static let compactWidth = AppTabBarMetrics(
        maxWidth: 300,
        accessibilityMaxWidth: 380,
        horizontalInset: 16,
        accessibilityHorizontalInset: 8,
        verticalInset: 0,
        minHeight: 56,
        cornerRadius: 28,
        itemSpacing: 8,
        accessibilityItemSpacing: 4,
        itemMinHeight: 52,
        iconSize: 18,
        labelSpacing: 3
    )

    static let regularWidth = AppTabBarMetrics(
        maxWidth: 420,
        accessibilityMaxWidth: 560,
        horizontalInset: 24,
        accessibilityHorizontalInset: 16,
        verticalInset: 0,
        minHeight: 68,
        cornerRadius: 34,
        itemSpacing: 12,
        accessibilityItemSpacing: 8,
        itemMinHeight: 64,
        iconSize: 22,
        labelSpacing: 4
    )
}

extension ContentView.AppTab: AppTabItem {}

extension DynamicTypeSize {
    /// Layouts that need more room before accessibility categories begin.
    var requiresExpandedCompactLayout: Bool {
        self >= .xxxLarge
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
