import SharedCode
import SwiftUI
import SwiftData
import MapKit

public struct LocationSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var isSearching = false
    @State private var isSavingSearchResult = false
    @State private var searchError: Error?
    @State private var showingMapPicker = false
    @State private var manualLocationName = ""
    @State private var manualCoordinates = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = UUID()
    @State private var saveTask: Task<Void, Never>?
    
    private let placeSearch = PlaceSearchService()
    private let elevationService = TerrainElevationService()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                // Search Section
                Section {
                    TextField("Search for a place or address...", text: $searchText)
                        .autocorrectionDisabled()
                        .disabled(isSavingSearchResult)
                        .onChange(of: searchText) { _, _ in
                            scheduleSearch()
                        }
                        .onSubmit {
                            scheduleSearch(debounce: false)
                        }
                    
                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if isSavingSearchResult {
                        ProgressView("Adding location...")
                    } else if !searchResults.isEmpty {
                        ForEach(searchResults) { result in
                            Button(action: { selectSearchResult(result) }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.name)
                                        .font(.headline)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(String(format: "%.4f", result.latitude)), \(String(format: "%.4f", result.longitude))")
                                        .font(.footnote)
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
                    Text("Place search by Apple Maps. Elevation data: Open-Meteo / Copernicus Programme.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                // Manual Coordinates Section
                Section {
                    TextField("Location name", text: $manualLocationName)
                    
                    TextField("Lat, Long (e.g., 40.7128, -74.0060)", text: $manualCoordinates)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    
                    Button("Add Coordinates") {
                        addManualCoordinates()
                    }
                    .disabled(isSavingSearchResult || manualLocationName.isEmpty || !isValidCoordinateFormat(manualCoordinates))
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
                    .disabled(isSavingSearchResult)
                } header: {
                    Text("Map")
                }
            }
            .appListBackground()
            .appNavigationTitle("Add Location", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMapPicker) {
                MapPickerView { name, coordinate in
                    saveLocation(name: name, from: coordinate)
                }
            }
        }
        .onDisappear {
            searchTask?.cancel()
            saveTask?.cancel()
        }
    }
    
    private func scheduleSearch(debounce: Bool = true) {
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }
        
        searchError = nil
        isSearching = true
        
        searchTask = Task { @MainActor in
            do {
                if debounce {
                    try await Task.sleep(nanoseconds: 350_000_000)
                }
                
                let results = try await placeSearch.search(query: query)
                
                guard !Task.isCancelled, generation == searchGeneration,
                      query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return
                }
                
                searchResults = results
                isSearching = false
            } catch is CancellationError {
                if generation == searchGeneration,
                   query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) {
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled, generation == searchGeneration,
                      query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return
                }
                
                searchResults = []
                searchError = error
                isSearching = false
            }
        }
    }
    
    private func selectSearchResult(_ result: PlaceSearchResult) {
        guard !isSavingSearchResult else { return }
        searchTask?.cancel()
        searchGeneration = UUID()
        isSearching = false
        isSavingSearchResult = true
        saveTask = Task { @MainActor in
            // Terrain elevation is optional; a failed lookup must not block saving.
            let elevation = await elevationService.elevationIfAvailable(
                latitude: result.latitude,
                longitude: result.longitude
            )
            guard !Task.isCancelled else { return }
            let location = result.savedLocation(elevation: elevation)
            modelContext.insert(location)
            do {
                try modelContext.save()
                publishLocationsToWatch()
                dismiss()
            } catch {
                print("Failed to save location: \(error)")
                dismiss()
            }
            isSavingSearchResult = false
        }
    }
    
    private func saveLocation(name: String, from coordinate: CLLocationCoordinate2D) {
        let location = SavedLocation(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        
        modelContext.insert(location)
        do {
            try modelContext.save()
            publishLocationsToWatch()
            dismiss()
        } catch {
            print("Failed to save location: \(error)")
            dismiss()
        }
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
            name: manualLocationName.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: lat,
            longitude: lon
        )
        
        modelContext.insert(location)
        do {
            try modelContext.save()
            publishLocationsToWatch()
            dismiss()
        } catch {
            print("Failed to save location: \(error)")
            dismiss()
        }
    }
    
    private func publishLocationsToWatch() {
        let locations = LocationStorageService.shared.publishLocationsToWatch(context: modelContext)
        WatchConnectivityService.shared.sendLocationsToWatch(locations)
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
