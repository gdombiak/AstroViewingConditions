import SharedCode
import SwiftUI
import SwiftData
import WidgetKit

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("n2yoApiKey") private var n2yoApiKey: String = ""
    @State private var selectedLocation: SelectedLocation?
    @Query(sort: \SavedLocation.dateAdded, order: .reverse) private var savedLocations: [SavedLocation]
    @State private var viewModel = DashboardViewModel(apiKey: "")
    @State private var locationManager = LocationManager()
    
    @State private var currentLocation: SavedLocation?
    @State private var showingLocationPicker = false
    @State private var showingBestSpotSearch = false
    @State private var lastActiveCheck = Date()
    
    public init() {
        _selectedLocation = State(initialValue: LocationStorageService.shared.loadSelectedLocation())
    }
    
    private var unitConverter: AstroUnitConverter {
        AstroUnitConverter(unitSystem: UnitSystemStorage.loadSelectedUnitSystem())
    }
    
    private var activeSavedLocation: SavedLocation? {
        guard let selectedLocation else { return nil }
        if selectedLocation.source == .currentGPS {
            return currentLocation
        }
        guard let id = selectedLocation.id else { return nil }
        return savedLocations.first { $0.id == id }
    }
    
    private var selectedLocationName: String {
        activeSavedLocation?.name ?? "Astro Conditions"
    }
    
    private var searchDate: Date {
        guard let conditions = viewModel.viewingConditions,
              let firstForecast = conditions.hourlyForecasts.first else { return Date() }
        let calendar = Calendar.current
        let startOfFirstDay = calendar.startOfDay(for: firstForecast.time)
        return calendar.date(byAdding: .day, value: viewModel.selectedDay.rawValue, to: startOfFirstDay) ?? Date()
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
                    if !viewModel.isLoading, activeSavedLocation != nil {
                        Button(action: { showingBestSpotSearch = true }) {
                            Image(systemName: "binoculars")
                        }
                    }
                }
                
                ToolbarItem(placement: toolbarPlacement) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button(action: {
                            Task {
                                if let location = activeSavedLocation {
                                    await viewModel.refresh(for: location)
                                    viewModel.saveToCache()
                                }
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(activeSavedLocation == nil)
                    }
                }
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView(
                    selectedLocation: $selectedLocation,
                    currentLocation: currentLocation,
                    savedLocations: savedLocations
                )
            }
            .sheet(isPresented: $showingBestSpotSearch) {
                if let location = activeSavedLocation {
                    BestSpotView(
                        centerLocation: location,
                        searchDate: searchDate,
                        fogScoreCalculator: FogCalculator.calculate
                    )
                }
            }
        }
        .task {
            viewModel.updateAPIKey(n2yoApiKey)
            await loadCurrentLocation()
            if let location = selectedLocation, location.source == .saved, location.latitude == 0, location.longitude == 0, location.name.isEmpty {
                if let id = location.id, let saved = savedLocations.first(where: { $0.id == id }) {
                    selectedLocation = SelectedLocation(
                        source: .saved,
                        id: saved.id,
                        name: saved.name,
                        latitude: saved.latitude,
                        longitude: saved.longitude
                    )
                    LocationStorageService.shared.saveSelectedLocation(selectedLocation!)
                }
            }
            if let location = activeSavedLocation {
                await viewModel.loadConditionsIfNeeded(for: location)
                viewModel.saveToCache()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            Task {
                await loadCurrentLocation()
                if let location = activeSavedLocation {
                    await viewModel.loadConditionsIfNeeded(for: location)
                    viewModel.saveToCache()
                }
            }
        }
        .onChange(of: n2yoApiKey) { _, newKey in
            viewModel.updateAPIKey(newKey)
            Task {
                if let location = activeSavedLocation {
                    await viewModel.refresh(for: location)
                    viewModel.saveToCache()
                }
            }
        }
        .onChange(of: selectedLocation) { _, newValue in
            if let location = newValue {
                LocationStorageService.shared.saveSelectedLocation(location)
                Task {
                    if let savedLocation = activeSavedLocation {
                        await viewModel.loadConditionsIfNeeded(for: savedLocation)
                        viewModel.saveToCache()
                    }
                }
                WatchConnectivityService.shared.sendSelectedLocationToWatch(location)
            }
            let locations = LocationStorageService.shared.publishLocationsToWatch(context: modelContext)
            WatchConnectivityService.shared.sendLocationsToWatch(locations)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            lastActiveCheck = Date()
            if viewModel.isDataStale, let location = activeSavedLocation {
                Task {
                    await viewModel.refresh(for: location)
                    viewModel.saveToCache()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchLocationSelected)) { notification in
            if let location = notification.object as? SelectedLocation {
                selectedLocation = location
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
    
    private func conditionsContent(conditions: ViewingConditions) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if viewModel.isDataStale {
                    staleDataBanner
                }
                
                daySelector
                
                if let nightQuality = viewModel.currentNightQuality {
                    NightQualityCard(
                        assessment: nightQuality
                    )
                }
                
                if viewModel.selectedDay == .today {
                    CurrentConditionsCard(
                        forecast: viewModel.currentHourForecast,
                        unitConverter: unitConverter
                    )
                }
                
                HourlyForecastView(
                    forecasts: viewModel.currentHourlyForecasts,
                    unitConverter: unitConverter
                )
                
                if let sunEvents = viewModel.currentSunEvents,
                   let moonInfo = viewModel.currentMoonInfo {
                    SunMoonCard(
                        sunEvents: sunEvents,
                        moonInfo: moonInfo
                    )
                }
                
                if viewModel.hasISSConfigured && !viewModel.currentISSPasses.isEmpty {
                    ISSCard(passes: viewModel.currentISSPasses)
                }
                
                if let fetchedAt = viewModel.viewingConditions?.fetchedAt {
                    Text("Last updated: \(DateFormatters.timeAgo(from: fetchedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                        .id(lastActiveCheck)
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
    
    private func loadCurrentLocation() async {
        guard locationManager.isAuthorized else {
            locationManager.requestAuthorization()
            return
        }
        
        do {
            let coordinate = try await locationManager.getCurrentLocation()
            
            let locationName: String
            if let placemark = try? await locationManager.reverseGeocode(coordinate: coordinate) {
                locationName = placemark.locality ?? placemark.administrativeArea ?? placemark.name ?? CoordinateFormatters.format(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
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

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLocation: SelectedLocation?
    let currentLocation: SavedLocation?
    let savedLocations: [SavedLocation]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Current Location") {
                    Button(action: {
                        if let currentLocation {
                            selectedLocation = SelectedLocation(
                                source: .currentGPS,
                                name: currentLocation.name,
                                latitude: currentLocation.latitude,
                                longitude: currentLocation.longitude
                            )
                        } else {
                            selectedLocation = SelectedLocation(
                                source: .currentGPS,
                                name: "My Current Location",
                                latitude: 0,
                                longitude: 0
                            )
                        }
                        LocationStorageService.shared.saveSelectedLocation(selectedLocation!)
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
                            
                            if selectedLocation?.source == .currentGPS {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                
                if !savedLocations.isEmpty {
                    Section("Saved Locations") {
                        ForEach(savedLocations) { location in
                            Button(action: {
                                selectedLocation = SelectedLocation(
                                    source: .saved,
                                    id: location.id,
                                    name: location.name,
                                    latitude: location.latitude,
                                    longitude: location.longitude
                                )
                                LocationStorageService.shared.saveSelectedLocation(selectedLocation!)
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
                                    
                                    if selectedLocation?.source == .saved, selectedLocation?.id == location.id {
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
