import SwiftUI
import MapKit
#if canImport(UIKit)
import UIKit
#endif

enum FieldModePreference {
    static let key = "fieldModeEnabled"
    static let defaultValue = false

    static func load(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    static func save(_ isEnabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: key)
    }
}

enum AppAppearance: Equatable {
    case normal
    case field

    static func resolve(fieldModeEnabled: Bool) -> AppAppearance {
        fieldModeEnabled ? .field : .normal
    }

    var palette: AppPalette {
        switch self {
        case .normal: .normal
        case .field: .field
        }
    }
}

enum AppStatusTone {
    case positive
    case informational
    case caution
    case negative
}

struct AppPalette {
    let appearance: AppAppearance
    let appBackground: Color
    let elevatedBackground: Color
    let primaryText: Color
    let displayTitleText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let disabledText: Color
    let accent: Color
    let primaryActionBackground: Color
    let primaryActionLabel: Color
    let secondaryActionBackground: Color
    let destructiveActionBackground: Color
    let border: Color
    let subduedFill: Color
    let controlBackground: Color
    let selectedControlBackground: Color
    let selectedControlText: Color
    let unselectedControlText: Color
    let tabBarBackground: Color
    let positive: Color
    let caution: Color
    let negative: Color

    static let normal = AppPalette(
        appearance: .normal,
        appBackground: Color(uiColor: .systemBackground),
        elevatedBackground: Color(uiColor: .systemGray6),
        primaryText: .primary,
        displayTitleText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(uiColor: .tertiaryLabel),
        disabledText: Color(uiColor: .quaternaryLabel),
        accent: .accentColor,
        primaryActionBackground: .accentColor,
        primaryActionLabel: .white,
        secondaryActionBackground: Color(uiColor: .secondarySystemFill),
        destructiveActionBackground: .red,
        border: Color(uiColor: .separator),
        subduedFill: Color(uiColor: .secondarySystemFill),
        controlBackground: Color(uiColor: .secondarySystemFill),
        selectedControlBackground: Color(uiColor: .secondarySystemBackground),
        selectedControlText: .primary,
        unselectedControlText: .secondary,
        tabBarBackground: Color(uiColor: .systemBackground),
        positive: .green,
        caution: .orange,
        negative: .red
    )

    static let field = AppPalette(
        appearance: .field,
        appBackground: Color(red: 0.018, green: 0.006, blue: 0.006),
        elevatedBackground: Color(red: 0.070, green: 0.016, blue: 0.016),
        primaryText: Color(red: 0.88, green: 0.34, blue: 0.28),
        displayTitleText: Color(red: 0.78, green: 0.27, blue: 0.22),
        secondaryText: Color(red: 0.76, green: 0.28, blue: 0.23),
        tertiaryText: Color(red: 0.65, green: 0.22, blue: 0.18),
        disabledText: Color(red: 0.48, green: 0.14, blue: 0.12),
        accent: Color(red: 0.90, green: 0.26, blue: 0.20),
        primaryActionBackground: Color(red: 0.43, green: 0.068, blue: 0.052),
        primaryActionLabel: Color(red: 0.94, green: 0.50, blue: 0.42),
        secondaryActionBackground: Color(red: 0.14, green: 0.028, blue: 0.026),
        destructiveActionBackground: Color(red: 0.25, green: 0.035, blue: 0.03),
        border: Color(red: 0.34, green: 0.08, blue: 0.065),
        subduedFill: Color(red: 0.13, green: 0.025, blue: 0.025),
        controlBackground: Color(red: 0.095, green: 0.018, blue: 0.018),
        selectedControlBackground: Color(red: 0.20, green: 0.045, blue: 0.038),
        selectedControlText: Color(red: 0.92, green: 0.38, blue: 0.30),
        unselectedControlText: Color(red: 0.68, green: 0.22, blue: 0.18),
        tabBarBackground: Color(red: 0.055, green: 0.012, blue: 0.012),
        positive: Color(red: 0.55, green: 0.42, blue: 0.16),
        caution: Color(red: 0.72, green: 0.31, blue: 0.12),
        negative: Color(red: 0.78, green: 0.16, blue: 0.12)
    )

    func statusColor(_ tone: AppStatusTone) -> Color {
        switch tone {
        case .positive: positive
        case .informational: appearance == .field ? secondaryText : .blue
        case .caution: caution
        case .negative: negative
        }
    }
}

private struct AppPaletteKey: EnvironmentKey {
    static let defaultValue = AppPalette.normal
}

extension EnvironmentValues {
    var appPalette: AppPalette {
        get { self[AppPaletteKey.self] }
        set { self[AppPaletteKey.self] = newValue }
    }
}

private struct AppAppearanceModifier: ViewModifier {
    let fieldModeEnabled: Bool

    private var appearance: AppAppearance {
        AppAppearance.resolve(fieldModeEnabled: fieldModeEnabled)
    }

    func body(content: Content) -> some View {
        let palette = appearance.palette

        // Keep `content` in one structural position. Branching around it here causes
        // SwiftUI to replace the wrapped subtree when Field Mode changes.
        content
            .environment(\.appPalette, palette)
            .preferredColorScheme(fieldModeEnabled ? .dark : nil)
            .tint(fieldModeEnabled ? palette.accent : nil)
            .foregroundStyle(
                fieldModeEnabled ? palette.primaryText : .primary,
                fieldModeEnabled ? palette.secondaryText : .secondary,
                fieldModeEnabled ? palette.tertiaryText : Color(uiColor: .tertiaryLabel)
            )
            .background(
                (fieldModeEnabled ? palette.appBackground : .clear)
                    .ignoresSafeArea()
            )
    }
}

private struct AppScreenBackgroundModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            content.background(palette.appBackground.ignoresSafeArea())
        } else {
            content
        }
    }
}

private struct AppListBackgroundModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            content
                .scrollContentBackground(.hidden)
                .background(palette.appBackground.ignoresSafeArea())
        } else {
            content
        }
    }
}

private struct AppListRowSurfaceModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            content.listRowBackground(palette.elevatedBackground)
        } else {
            content
        }
    }
}

private struct AppSecondaryForegroundModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    func body(content: Content) -> some View {
        content.foregroundStyle(palette.secondaryText)
    }
}

private struct AppPrimaryForegroundModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    func body(content: Content) -> some View {
        content.foregroundStyle(palette.primaryText)
    }
}

private struct AppTertiaryForegroundModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    func body(content: Content) -> some View {
        content.foregroundStyle(palette.tertiaryText)
    }
}

struct AppSegmentedPicker<Option: Hashable, Label: View>: View {
    @Environment(\.appPalette) private var palette
    @Binding private var selection: Option
    private let options: [Option]
    private let pickerLabel: String
    private let label: (Option) -> Label

    init(
        selection: Binding<Option>,
        options: [Option],
        pickerLabel: String,
        @ViewBuilder label: @escaping (Option) -> Label
    ) {
        _selection = selection
        self.options = options
        self.pickerLabel = pickerLabel
        self.label = label
    }

    var body: some View {
        HStack(spacing: AppSegmentedPickerLayout.itemSpacing) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                Button {
                    selection = option
                } label: {
                    label(option)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(textColor(isSelected: isSelected))
                        .frame(maxWidth: .infinity, minHeight: AppSegmentedPickerLayout.itemMinHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selectedBackground(isSelected: isSelected))
                .clipShape(RoundedRectangle(cornerRadius: AppSegmentedPickerLayout.itemCornerRadius))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: AppSegmentedPickerLayout.itemCornerRadius)
                            .stroke(selectedBorder, lineWidth: 1)
                    }
                }
                .accessibilityLabel(accessibilityLabel(for: option))
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(AppSegmentedPickerLayout.containerPadding)
        .background(palette.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSegmentedPickerLayout.containerCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppSegmentedPickerLayout.containerCornerRadius)
                .stroke(containerBorder, lineWidth: 1)
        }
    }

    private var selectedBorder: Color {
        palette.appearance == .field ? palette.accent.opacity(0.65) : Color(uiColor: .separator).opacity(0.2)
    }

    private var containerBorder: Color {
        palette.appearance == .field ? palette.border : Color(uiColor: .separator).opacity(0.35)
    }

    private func textColor(isSelected: Bool) -> Color {
        if palette.appearance == .field {
            return isSelected ? palette.selectedControlText : palette.unselectedControlText
        }
        return isSelected ? palette.selectedControlText : palette.unselectedControlText
    }

    private func selectedBackground(isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return palette.selectedControlBackground
    }

    private func accessibilityLabel(for option: Option) -> String {
        String(describing: option)
    }
}

private struct AppNavigationTitleModifier: ViewModifier {
    @Environment(\.appPalette) private var palette
    let title: String
    let displayMode: NavigationBarItem.TitleDisplayMode

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(displayMode)
            .background {
                NavigationBarTitleColorConfigurator(palette: palette)
            }
    }
}

#if canImport(UIKit)
private struct NavigationBarTitleColorConfigurator: UIViewControllerRepresentable {
    let palette: AppPalette

    func makeUIViewController(context: Context) -> NavigationBarTitleColorViewController {
        NavigationBarTitleColorViewController()
    }

    func updateUIViewController(
        _ viewController: NavigationBarTitleColorViewController,
        context: Context
    ) {
        viewController.update(palette: palette)
    }
}

private final class NavigationBarTitleColorViewController: UIViewController {
    private var palette: AppPalette = .normal
    private var isRetryScheduled = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyCurrentPalette()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyCurrentPalette()
    }

    func update(palette: AppPalette) {
        self.palette = palette
        applyCurrentPalette()
    }

    private func applyCurrentPalette() {
        guard let navigationBar = navigationController?.navigationBar else {
            guard !isRetryScheduled else { return }
            isRetryScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.isRetryScheduled = false
                self?.applyCurrentPalette()
            }
            return
        }

        isRetryScheduled = false
        let navigationItem = navigationController?.topViewController?.navigationItem

        if palette.appearance == .field {
            applyFieldAppearances(to: navigationBar)
            if let navigationItem {
                applyFieldAppearances(to: navigationItem, using: navigationBar)
            }
        } else {
            clearTitleColorOverrides(from: navigationBar)
            if let navigationItem {
                clearTitleColorOverrides(from: navigationItem)
            }
        }
    }

    private func applyFieldAppearances(to navigationBar: UINavigationBar) {
        let inlineTitleColor = UIColor(palette.primaryText)
        let largeTitleColor = UIColor(palette.displayTitleText)

        navigationBar.standardAppearance = fieldAppearance(
            from: navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
        navigationBar.scrollEdgeAppearance = fieldAppearance(
            from: navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
        navigationBar.compactAppearance = fieldAppearance(
            from: navigationBar.compactAppearance ?? navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
        navigationBar.compactScrollEdgeAppearance = fieldAppearance(
            from: navigationBar.compactScrollEdgeAppearance ?? navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
    }

    private func applyFieldAppearances(
        to navigationItem: UINavigationItem,
        using navigationBar: UINavigationBar
    ) {
        let inlineTitleColor = UIColor(palette.primaryText)
        let largeTitleColor = UIColor(palette.displayTitleText)

        navigationItem.standardAppearance = fieldAppearance(
            from: navigationItem.standardAppearance ?? navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
        navigationItem.scrollEdgeAppearance = fieldAppearance(
            from: navigationItem.scrollEdgeAppearance ?? navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
        navigationItem.compactAppearance = fieldAppearance(
            from: navigationItem.compactAppearance ?? navigationBar.compactAppearance ?? navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
        navigationItem.compactScrollEdgeAppearance = fieldAppearance(
            from: navigationItem.compactScrollEdgeAppearance ?? navigationBar.compactScrollEdgeAppearance ?? navigationBar.scrollEdgeAppearance ?? navigationBar.standardAppearance,
            inlineTitleColor: inlineTitleColor,
            largeTitleColor: largeTitleColor
        )
    }

    private func fieldAppearance(
        from source: UINavigationBarAppearance,
        inlineTitleColor: UIColor,
        largeTitleColor: UIColor
    ) -> UINavigationBarAppearance {
        let appearance = source.copy()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear

        var titleAttributes = appearance.titleTextAttributes
        titleAttributes[.foregroundColor] = inlineTitleColor
        appearance.titleTextAttributes = titleAttributes

        var largeTitleAttributes = appearance.largeTitleTextAttributes
        largeTitleAttributes[.foregroundColor] = largeTitleColor
        appearance.largeTitleTextAttributes = largeTitleAttributes

        return appearance
    }

    private func clearTitleColorOverrides(from navigationBar: UINavigationBar) {
        navigationBar.standardAppearance = appearanceWithoutTitleColors(
            from: navigationBar.standardAppearance
        )

        if let scrollEdgeAppearance = navigationBar.scrollEdgeAppearance {
            navigationBar.scrollEdgeAppearance = appearanceWithoutTitleColors(
                from: scrollEdgeAppearance
            )
        }

        if let compactAppearance = navigationBar.compactAppearance {
            navigationBar.compactAppearance = appearanceWithoutTitleColors(
                from: compactAppearance
            )
        }

        if let compactScrollEdgeAppearance = navigationBar.compactScrollEdgeAppearance {
            navigationBar.compactScrollEdgeAppearance = appearanceWithoutTitleColors(
                from: compactScrollEdgeAppearance
            )
        }
    }

    private func clearTitleColorOverrides(from navigationItem: UINavigationItem) {
        navigationItem.standardAppearance = nil
        navigationItem.scrollEdgeAppearance = nil
        navigationItem.compactAppearance = nil
        navigationItem.compactScrollEdgeAppearance = nil
    }

    private func appearanceWithoutTitleColors(
        from source: UINavigationBarAppearance
    ) -> UINavigationBarAppearance {
        let appearance = source.copy()

        var titleAttributes = appearance.titleTextAttributes
        titleAttributes.removeValue(forKey: .foregroundColor)
        appearance.titleTextAttributes = titleAttributes

        var largeTitleAttributes = appearance.largeTitleTextAttributes
        largeTitleAttributes.removeValue(forKey: .foregroundColor)
        appearance.largeTitleTextAttributes = largeTitleAttributes

        return appearance
    }
}
#else
private struct NavigationBarTitleColorConfigurator: View {
    let palette: AppPalette

    var body: some View {
        EmptyView()
    }
}
#endif

private enum AppSegmentedPickerLayout {
    static let itemSpacing: CGFloat = 2
    static let containerPadding: CGFloat = 2
    static let itemMinHeight: CGFloat = 32
    static let itemCornerRadius: CGFloat = 7
    static let containerCornerRadius: CGFloat = 9
}

private struct FieldPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(isEnabled ? palette.primaryActionLabel : palette.secondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(isEnabled ? palette.primaryActionBackground : palette.subduedFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isEnabled ? palette.accent.opacity(0.9) : palette.border, lineWidth: 2)
            }
            .brightness(configuration.isPressed && isEnabled ? -0.12 : 0)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
    }
}

private struct AppPrimaryActionModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            content.buttonStyle(FieldPrimaryActionButtonStyle())
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private struct FieldSecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(palette.secondaryActionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.border, lineWidth: 1)
            }
            .brightness(configuration.isPressed ? -0.1 : 0)
    }
}

private struct AppSecondaryActionModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            content.buttonStyle(FieldSecondaryActionButtonStyle())
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct FieldToolbarButtonStyle: ButtonStyle {
    @Environment(\.appPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 8)
            .background(palette.controlBackground)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(palette.border, lineWidth: 1) }
            .brightness(configuration.isPressed ? -0.1 : 0)
    }
}

private struct AppToolbarButtonModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            content.buttonStyle(FieldToolbarButtonStyle())
        } else {
            content
        }
    }
}

private struct AppMapStyleModifier: ViewModifier {
    @Environment(\.appPalette) private var palette

    func body(content: Content) -> some View {
        content.mapStyle(
            palette.appearance == .field
                ? .standard(elevation: .flat, emphasis: .muted)
                : .standard
        )
    }
}

extension View {
    func appAppearance(fieldModeEnabled: Bool) -> some View {
        modifier(AppAppearanceModifier(fieldModeEnabled: fieldModeEnabled))
    }

    func appScreenBackground() -> some View {
        modifier(AppScreenBackgroundModifier())
    }

    func appListBackground() -> some View {
        modifier(AppListBackgroundModifier())
    }

    func appListRowSurface() -> some View {
        modifier(AppListRowSurfaceModifier())
    }

    func appSecondaryForeground() -> some View {
        modifier(AppSecondaryForegroundModifier())
    }

    func appPrimaryForeground() -> some View {
        modifier(AppPrimaryForegroundModifier())
    }

    func appTertiaryForeground() -> some View {
        modifier(AppTertiaryForegroundModifier())
    }

    func appNavigationTitle(
        _ title: String,
        displayMode: NavigationBarItem.TitleDisplayMode = .automatic
    ) -> some View {
        modifier(AppNavigationTitleModifier(title: title, displayMode: displayMode))
    }

    func appPrimaryActionStyle() -> some View {
        modifier(AppPrimaryActionModifier())
    }

    func appSecondaryActionStyle() -> some View {
        modifier(AppSecondaryActionModifier())
    }

    func appToolbarButtonStyle() -> some View {
        modifier(AppToolbarButtonModifier())
    }

    func appMapStyle() -> some View {
        modifier(AppMapStyleModifier())
    }
}
