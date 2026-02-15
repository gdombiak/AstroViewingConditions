import SwiftUI
import SwiftData
import MapKit

public struct LocationSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var searchError: Error?
    @State private var showingMapPicker = false
    @State private var manualCoordinates = ""
    
    private let weatherService = WeatherService()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                // Search Section
                Section {
                    TextField("Search for a city...", text: $searchText)
                        .autocorrectionDisabled()
                        .onSubmit {
                            performSearch()
                        }
                    
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if !searchResults.isEmpty {
                        ForEach(searchResults) { result in
                            Button(action: { saveLocation(from: result) }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.name)
                                        .font(.headline)
                                    Text(result.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(String(format: "%.4f", result.latitude)), \(String(format: "%.4f", result.longitude))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else if let error = searchError {
                        Text("Error: \(error.localizedDescription)")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Search")
                } footer: {
                    Text("Powered by Open-Meteo Geocoding API")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Manual Coordinates Section
                Section {
                    TextField("Lat, Long (e.g., 40.7128, -74.0060)", text: $manualCoordinates)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    
                    Button("Add Coordinates") {
                        addManualCoordinates()
                    }
                    .disabled(!isValidCoordinateFormat(manualCoordinates))
                } header: {
                    Text("Manual Entry")
                }
                
                // Map Picker Section
                Section {
                    Button(action: { showingMapPicker = true }) {
                        HStack {
                            Image(systemName: "map")
                            Text("Select on Map")
                        }
                    }
                } header: {
                    Text("Map")
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMapPicker) {
                MapPickerView { coordinate in
                    saveLocation(from: coordinate)
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchError = nil
        searchResults = []
        
        Task {
            do {
                let results = try await weatherService.searchLocations(query: searchText)
                searchResults = results
            } catch {
                searchError = error
            }
            isSearching = false
        }
    }
    
    private func saveLocation(from result: GeocodingResult) {
        let location = SavedLocation(
            name: result.name,
            latitude: result.latitude,
            longitude: result.longitude,
            elevation: result.elevation
        )
        
        modelContext.insert(location)
        dismiss()
    }
    
    private func saveLocation(from coordinate: CLLocationCoordinate2D) {
        let location = SavedLocation(
            name: "Custom Location",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        
        modelContext.insert(location)
        dismiss()
    }
    
    private func addManualCoordinates() {
        let components = manualCoordinates
            .replacingOccurrences(of: " ", with: "")
            .split(separator: ",")
        
        guard components.count == 2,
              let lat = Double(components[0]),
              let lon = Double(components[1]),
              lat >= -90 && lat <= 90,
              lon >= -180 && lon <= 180 else {
            return
        }
        
        let location = SavedLocation(
            name: "\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))",
            latitude: lat,
            longitude: lon
        )
        
        modelContext.insert(location)
        dismiss()
    }
    
    private func isValidCoordinateFormat(_ text: String) -> Bool {
        let components = text
            .replacingOccurrences(of: " ", with: "")
            .split(separator: ",")
        
        guard components.count == 2,
              let lat = Double(components[0]),
              let lon = Double(components[1]) else {
            return false
        }
        
        return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
    }
}

#Preview {
    LocationSearchView()
        .modelContainer(for: SavedLocation.self, inMemory: true)
}
