import SwiftUI

public struct SettingsView: View {
    @AppStorage("selectedUnitSystem") private var unitSystem: UnitSystem = .metric
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                Section("Units") {
                    Picker("Unit System", selection: $unitSystem) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system.rawValue).tag(system)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Temperature", systemImage: "thermometer")
                            .font(.subheadline)
                        Text(unitSystem == .metric ? "Celsius (°C)" : "Fahrenheit (°F)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wind Speed", systemImage: "wind")
                            .font(.subheadline)
                        Text(unitSystem == .metric ? "Kilometers per hour (km/h)" : "Miles per hour (mph)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Distance", systemImage: "ruler")
                            .font(.subheadline)
                        Text(unitSystem == .metric ? "Kilometers (km)" : "Miles (mi)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Data Sources") {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Weather Data", systemImage: "cloud.sun")
                            .font(.subheadline)
                        Text("Open-Meteo (open-meteo.com)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Astronomical Data", systemImage: "moon.stars")
                            .font(.subheadline)
                        Text("SunCalc Swift Package")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("ISS Tracking", systemImage: "airplane")
                            .font(.subheadline)
                        Text("Open Notify (open-notify.org)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Astro Viewing Conditions")
                            .font(.headline)
                        Text("An open-source app for astronomy enthusiasts to check stargazing conditions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Link(destination: URL(string: "https://github.com/yourusername/AstroViewingConditions")!) {
                        Label("View on GitHub", systemImage: "link")
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("License")
                            .font(.subheadline)
                        Text("GNU Affero General Public License v3.0 (AGPL-3.0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("This ensures the app remains open source and free for the astronomy community.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
