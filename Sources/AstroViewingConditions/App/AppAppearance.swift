import SwiftUI
import MapKit

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

        if fieldModeEnabled {
            content
                .environment(\.appPalette, palette)
                .preferredColorScheme(.dark)
                .tint(palette.accent)
                .foregroundStyle(palette.primaryText, palette.secondaryText, palette.tertiaryText)
                .background(palette.appBackground.ignoresSafeArea())
        } else {
            content.environment(\.appPalette, palette)
        }
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

    @ViewBuilder
    var body: some View {
        if palette.appearance == .field {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    Button {
                        selection = option
                    } label: {
                        label(option)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(
                                isSelected ? palette.selectedControlText : palette.unselectedControlText
                            )
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(isSelected ? palette.selectedControlBackground : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(palette.accent.opacity(0.65), lineWidth: 1)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(palette.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(palette.border, lineWidth: 1)
            }
        } else {
            Picker(pickerLabel, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    label(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct AppNavigationTitleModifier: ViewModifier {
    @Environment(\.appPalette) private var palette
    let title: String
    let displayMode: NavigationBarItem.TitleDisplayMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if palette.appearance == .field {
            if displayMode == .large {
                content
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(palette.displayTitleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                            .background(palette.appBackground)
                            .accessibilityAddTraits(.isHeader)
                    }
            } else {
                content
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.85)
                                .accessibilityLabel(title)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
            }
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(displayMode)
        }
    }
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
