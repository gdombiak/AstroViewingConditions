import SwiftUI

public struct SettingsView: View {
    @AppStorage("selectedUnitSystem") private var unitSystem: UnitSystem = .metric
    @AppStorage("n2yoApiKey") private var n2yoApiKey: String = ""
    
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
                        Text("N2YO (n2yo.com)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("ISS Tracking Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("N2YO API Key", text: $n2yoApiKey)
                        
                        if n2yoApiKey.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enter your N2YO API key to enable ISS pass predictions.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Link(destination: URL(string: "https://www.n2yo.com/")!) {
                                    Label("Get a free API key at n2yo.com", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                            }
                        } else {
                            Text("ISS tracking is enabled")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
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
                    
                    Link(destination: URL(string: "https://github.com/gdombiak/AstroViewingConditions")!) {
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
