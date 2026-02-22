import SwiftUI
import SwiftData

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("n2yoApiKey") private var n2yoApiKey: String = ""
    @AppStorage("selectedLocationID") private var selectedLocationID: String = "current"
    @Query(sort: \SavedLocation.dateAdded, order: .reverse) private var savedLocations: [SavedLocation]
    @State private var viewModel = DashboardViewModel(apiKey: "")
    @State private var locationManager = LocationManager()
    
    // Current location (not persisted)
    @State private var currentLocation: SavedLocation?
    @State private var showingLocationPicker = false
    @State private var lastActiveCheck = Date()
    
    private var unitConverter: UnitConverter {
        UnitConverter(unitSystem: UserDefaults.standard.selectedUnitSystem)
    }
    
    private var selectedLocation: SavedLocation? {
        if selectedLocationID == "current" {
            return currentLocation
        }
        return savedLocations.first { $0.id.uuidString == selectedLocationID }
    }
    
    private var selectedLocationName: String {
        selectedLocation?.name ?? "Astro Conditions"
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if let conditions = viewModel.viewingConditions {
                    conditionsContent(conditions: conditions)
                } else if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error: error)
                } else {
                    initialView
                }
            }
            .navigationTitle(selectedLocationName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingLocationPicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "location.circle")
                            Text("Location")
                                .font(.caption)
                        }
                    }
                }
                
                ToolbarItem(placement: toolbarPlacement) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button(action: {
                            Task {
                                if let location = selectedLocation {
                                    await viewModel.refresh(for: location)
                                    viewModel.saveToCache()
                                }
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(selectedLocation == nil)
                    }
                }
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView(
                    selectedLocationID: $selectedLocationID,
                    currentLocation: currentLocation,
                    savedLocations: savedLocations
                )
            }
        }
        .task {
            viewModel.updateAPIKey(n2yoApiKey)
            await loadCurrentLocation()
            if selectedLocationID != "current" {
                if let location = selectedLocation {
                    await viewModel.loadConditionsIfNeeded(for: location)
                    viewModel.saveToCache()
                }
            } else if let location = currentLocation {
                await viewModel.loadConditionsIfNeeded(for: location)
                viewModel.saveToCache()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            Task {
                await loadCurrentLocation()
                if selectedLocationID != "current" {
                    if let location = selectedLocation {
                        await viewModel.loadConditionsIfNeeded(for: location)
                        viewModel.saveToCache()
                    }
                } else if let location = currentLocation {
                    await viewModel.loadConditionsIfNeeded(for: location)
                    viewModel.saveToCache()
                }
            }
        }
        .onChange(of: n2yoApiKey) { _, newKey in
            viewModel.updateAPIKey(newKey)
            Task {
                if let location = selectedLocation {
                    await viewModel.refresh(for: location)
                    viewModel.saveToCache()
                }
            }
        }
        .onChange(of: selectedLocationID) { _, _ in
            Task {
                if let location = selectedLocation {
                    await viewModel.loadConditionsIfNeeded(for: location)
                    viewModel.saveToCache()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            lastActiveCheck = Date()
            // Check if we need to refresh due to staleness
            if viewModel.isDataStale, let location = selectedLocation {
                Task {
                    await viewModel.refresh(for: location)
                    viewModel.saveToCache()
                }
            }
        }
    }
    
    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .automatic
        #endif
    }
    
    // MARK: - Content Views
    
    private func conditionsContent(conditions: ViewingConditions) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Data freshness warning
                if viewModel.isDataStale {
                    staleDataBanner
                }
                
                // Day selector
                daySelector
                
                // Current conditions summary (only for today)
                if viewModel.selectedDay == .today {
                    CurrentConditionsCard(
                        forecast: viewModel.currentHourForecast,
                        unitConverter: unitConverter
                    )
                }
                
                // Hourly forecast chart
                HourlyForecastView(
                    forecasts: viewModel.currentHourlyForecasts,
                    unitConverter: unitConverter
                )
                
                // Sun and Moon
                if let sunEvents = viewModel.currentSunEvents,
                   let moonInfo = viewModel.currentMoonInfo {
                    SunMoonCard(
                        sunEvents: sunEvents,
                        moonInfo: moonInfo
                    )
                }
                
                // ISS passes (only show if API key is configured)
                if viewModel.hasISSConfigured && !viewModel.currentISSPasses.isEmpty {
                    ISSCard(passes: viewModel.currentISSPasses)
                }
                
                // Last updated
                if let fetchedAt = viewModel.viewingConditions?.fetchedAt {
                    Text("Last updated: \(DateFormatters.timeAgo(from: fetchedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                        .id(lastActiveCheck) // Force re-render when app becomes active
                }
            }
            .padding()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading conditions...")
                .foregroundStyle(.secondary)
        }
    }
    
    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            
            Text("Unable to load conditions")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await loadCurrentLocation()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private var initialView: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            if !locationManager.isAuthorized {
                Text("Location Access Required")
                    .font(.headline)
                
                Text("Please enable location services to see viewing conditions for your current location.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Enable Location") {
                    locationManager.requestAuthorization()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Loading location...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private var staleDataBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Data may be outdated. Tap refresh button.")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var daySelector: some View {
        Picker("Day", selection: $viewModel.selectedDay) {
            ForEach(DashboardViewModel.DaySelection.allCases, id: \.self) { day in
                Text(viewModel.titleForSelectedDay(day)).tag(day)
            }
        }
        .pickerStyle(.segmented)
        .scaleEffect(isIPad ? 1.2 : 1.0)
    }
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentLocation() async {
        guard locationManager.isAuthorized else {
            locationManager.requestAuthorization()
            return
        }
        
        do {
            let coordinate = try await locationManager.getCurrentLocation()
            
            // Try to get a readable name for the location
            let locationName: String
            if let placemark = try? await locationManager.reverseGeocode(coordinate: coordinate) {
                locationName = placemark.formattedName
            } else {
                locationName = CoordinateFormatters.format(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }
            
            currentLocation = SavedLocation(
                name: locationName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            
            if let location = currentLocation {
                await viewModel.loadConditionsIfNeeded(for: location)
                viewModel.saveToCache()
            }
        } catch {
            viewModel.error = error
        }
    }
}

// MARK: - Location Picker View

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLocationID: String
    let currentLocation: SavedLocation?
    let savedLocations: [SavedLocation]
    
    var body: some View {
        NavigationStack {
            List {
                // Current Location Section
                Section("Current Location") {
                    Button(action: {
                        selectedLocationID = "current"
                        dismiss()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("My Current Location")
                                    .font(.headline)
                                
                                if let location = currentLocation {
                                    Text(CoordinateFormatters.format(location.coordinate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Using device location")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedLocationID == "current" {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                
                // Saved Locations Section
                if !savedLocations.isEmpty {
                    Section("Saved Locations") {
                        ForEach(savedLocations) { location in
                            Button(action: {
                                selectedLocationID = location.id.uuidString
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(location.name)
                                            .font(.headline)
                                        
                                        Text(CoordinateFormatters.format(location.coordinate))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        if let elevation = location.elevation {
                                            Text("Elevation: \(Int(elevation))m")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if location.id.uuidString == selectedLocationID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                    
                                    if location.isFavorite {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
