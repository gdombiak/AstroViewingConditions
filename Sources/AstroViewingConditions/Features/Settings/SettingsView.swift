import SharedCode
import SwiftUI

public struct SettingsView: View {
    @Environment(\.appPalette) private var palette
    @State private var unitSystem: UnitSystem
    @AppStorage("n2yoApiKey") private var n2yoApiKey: String = ""
    @AppStorage(FieldModePreference.key) private var fieldModeEnabled = FieldModePreference.defaultValue
    
    public init() {
        _unitSystem = State(initialValue: UnitSystemStorage.loadSelectedUnitSystem())
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Toggle(isOn: fieldModeBinding) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Field Mode", systemImage: "flashlight.off.fill")
                                .font(.subheadline)
                            Text("Uses a dim red appearance to reduce glare while observing. Affects this iPhone or iPad app only.")
                                .font(.caption)
                                .appSecondaryForeground()
                        }
                    }
                    .accessibilityHint("Reduces screen glare while observing and does not affect widgets or Apple Watch.")
                }
                .appListRowSurface()

                Section("Units") {
                    AppSegmentedPicker(
                        selection: $unitSystem,
                        options: UnitSystem.allCases,
                        pickerLabel: "Unit System"
                    ) { system in
                        Text(system.rawValue)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Temperature", systemImage: "thermometer")
                            .font(.subheadline)
                        Text(unitSystem == .metric ? "Celsius (°C)" : "Fahrenheit (°F)")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wind Speed", systemImage: "wind")
                            .font(.subheadline)
                        Text(unitSystem == .metric ? "Kilometers per hour (km/h)" : "Miles per hour (mph)")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Distance", systemImage: "ruler")
                            .font(.subheadline)
                        Text(unitSystem == .metric ? "Kilometers (km)" : "Miles (mi)")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                }
                .appListRowSurface()
                
                Section("Data Sources") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Weather Data", systemImage: "cloud.sun")
                            .font(.subheadline)
                        Text("Open-Meteo (open-meteo.com)")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Astronomical Data", systemImage: "moon.stars")
                            .font(.subheadline)
                        Text("SunCalc Swift Package")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("ISS Tracking", systemImage: "airplane")
                            .font(.subheadline)
                        Text("N2YO (n2yo.com)")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                }
                .appListRowSurface()
                
                Section("ISS Tracking Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("N2YO API Key", text: $n2yoApiKey)
                        
                        if n2yoApiKey.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enter your N2YO API key to enable ISS pass predictions.")
                                    .font(.caption)
                                    .appSecondaryForeground()
                                
                                if let n2yoURL = URL(string: "https://www.n2yo.com/") {
                                    Link(destination: n2yoURL) {
                                        Label("Get a free API key at n2yo.com", systemImage: "arrow.up.right.square")
                                            .font(.caption)
                                    }
                                }
                            }
                        } else {
                            Text("ISS tracking is enabled")
                                .font(.caption)
                                .foregroundStyle(
                                    palette.appearance == .field ? palette.statusColor(.positive) : .green
                                )
                        }
                    }
                }
                .appListRowSurface()
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                            .appSecondaryForeground()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Astro Viewing Conditions")
                            .font(.headline)
                        Text("An open-source app for astronomy enthusiasts to check stargazing conditions.")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                    .padding(.vertical, 4)
                    
                    if let repositoryURL = URL(string: "https://github.com/gdombiak/AstroViewingConditions") {
                        Link(destination: repositoryURL) {
                            Label("View on GitHub", systemImage: "link")
                        }
                    }
                }
                .appListRowSurface()
                
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("License")
                            .font(.subheadline)
                        Text("GNU Affero General Public License v3.0 (AGPL-3.0)")
                            .font(.caption)
                            .appSecondaryForeground()
                        Text("This ensures the app remains open source and free for the astronomy community.")
                            .font(.caption2)
                            .appSecondaryForeground()
                            .padding(.top, 2)
                    }
                }
                .appListRowSurface()
            }
            .appListBackground()
            .onChange(of: unitSystem) { _, newValue in
                UnitSystemStorage.saveSelectedUnitSystem(newValue)
                WatchConnectivityService.shared.sendUnitSystemToWatch(newValue)
            }
            .appNavigationTitle("Settings")
        }
    }

    private var fieldModeBinding: Binding<Bool> {
        Binding(
            get: { fieldModeEnabled },
            set: { newValue in
                NotificationCenter.default.post(
                    name: .dashboardWillToggleFieldMode,
                    object: newValue
                )
                fieldModeEnabled = newValue
            }
        )
    }
}

#Preview {
    SettingsView()
        .appAppearance(fieldModeEnabled: false)
}

#Preview("Settings Field Mode") {
    SettingsView()
        .appAppearance(fieldModeEnabled: true)
}
