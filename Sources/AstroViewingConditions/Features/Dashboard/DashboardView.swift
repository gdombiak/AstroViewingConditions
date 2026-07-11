import SharedCode
import SwiftUI
import SwiftData
import WidgetKit

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appPalette) private var palette
    @AppStorage("n2yoApiKey") private var n2yoApiKey: String = ""
    @AppStorage(FieldModePreference.key) private var fieldModeEnabled = FieldModePreference.defaultValue
    @State private var selectedLocation: SelectedLocation?
    @Query(sort: \SavedLocation.dateAdded, order: .reverse) private var savedLocations: [SavedLocation]
    @State private var viewModel = DashboardViewModel(
        apiKey: UserDefaults.standard.string(forKey: "n2yoApiKey") ?? ""
    )
    @State private var locationManager = LocationManager()
    
    @State private var currentLocation: SavedLocation?
    @State private var showingLocationPicker = false
    @State private var showingBestSpotSearch = false
    @State private var showingAllBestTargets = false
    
    public init() {
        _selectedLocation = State(initialValue: LocationStorageService.shared.loadSelectedLocation())
    }
    
    private var unitConverter: AstroUnitConverter {
        AstroUnitConverter(unitSystem: UnitSystemStorage.loadSelectedUnitSystem())
    }
    
    private var activeSavedLocation: SavedLocation? {
        guard let selectedLocation else { return currentLocation }
        if selectedLocation.source == .currentGPS {
            return currentLocation
        }
        guard let id = selectedLocation.id else { return nil }
        return savedLocations.first { $0.id == id }
    }

    private var orderedSavedLocations: [SavedLocation] {
        SavedLocation.ordered(savedLocations)
    }
    
    private var selectedLocationName: String {
        activeSavedLocation?.name ?? "Astro Conditions"
    }
    
    private var searchDate: Date {
        let calendar = viewModel.locationCalendar
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: viewModel.selectedDay.rawValue, to: startOfToday) ?? Date()
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
            .safeAreaInset(edge: .top, spacing: 0) {
                if shouldShowNormalIPadLocationTitle {
                    normalIPadLocationTitle
                }
            }
            .appNavigationTitle(selectedLocationName)
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
                    Button {
                        fieldModeEnabled.toggle()
                    } label: {
                        Image(systemName: fieldModeEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                    .accessibilityLabel("Field Mode")
                    .accessibilityValue(fieldModeEnabled ? "On" : "Off")
                    .accessibilityHint("Toggles a dim red appearance for observing in darkness.")
                }

                ToolbarItem(placement: toolbarPlacement) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button(action: {
                            Task {
                                if let location = activeSavedLocation {
                                    await viewModel.refresh(for: location)
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
                    savedLocations: orderedSavedLocations
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
            .sheet(isPresented: $showingAllBestTargets) {
                BestTargetsListView(
                    presentation: viewModel.currentBestTargetsPresentation,
                    timeZone: viewModel.displayTimeZone
                )
                .adaptiveTargetSheet(horizontalSizeClass: horizontalSizeClass)
            }
        }
        .appScreenBackground()
        .task {
            viewModel.updateAPIKey(n2yoApiKey)
            await loadCurrentLocation()
            if let location = selectedLocation, location.source == .saved, location.latitude == 0, location.longitude == 0, location.name.isEmpty {
                if let id = location.id, let saved = savedLocations.first(where: { $0.id == id }) {
                    let restoredLocation = SelectedLocation(
                        source: .saved,
                        id: saved.id,
                        name: saved.name,
                        latitude: saved.latitude,
                        longitude: saved.longitude
                    )
                    selectedLocation = restoredLocation
                    LocationStorageService.shared.saveSelectedLocation(restoredLocation)
                }
            }
            await loadActiveLocationConditionsIfNeeded()
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            Task {
                await loadCurrentLocation()
                await loadActiveLocationConditionsIfNeeded()
            }
        }
        .onChange(of: n2yoApiKey) { _, newKey in
            viewModel.updateAPIKey(newKey)
            Task {
                if let location = activeSavedLocation {
                    await viewModel.refresh(for: location)
                }
            }
        }
        .onChange(of: selectedLocation) { _, newValue in
            if let location = newValue {
                LocationStorageService.shared.saveSelectedLocation(location)
                Task {
                    await loadActiveLocationConditionsIfNeeded()
                }
                WatchConnectivityService.shared.sendSelectedLocationToWatch(location)
            }
            let locations = LocationStorageService.shared.publishLocationsToWatch(context: modelContext)
            WatchConnectivityService.shared.sendLocationsToWatch(locations)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if viewModel.isDataStale, !viewModel.isLoading, let location = activeSavedLocation {
                Task {
                    await viewModel.refresh(for: location)
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
        let bestTargets = viewModel.currentBestTargetsPresentation

        return ScrollView {
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

                TonightsBestTargetsCard(
                    recommendations: bestTargets.dashboardRecommendations,
                    timeZone: viewModel.displayTimeZone,
                    nightQualityScore: viewModel.currentNightQuality?.calculatedScore,
                    hasAdditionalTargets: bestTargets.hasAdditionalTargets,
                    onViewAll: { showingAllBestTargets = true }
                )
                
                if viewModel.hasISSConfigured {
                    ISSCard(
                        passes: viewModel.currentISSPasses,
                        timeZone: viewModel.displayTimeZone,
                        errorMessage: viewModel.issError?.localizedDescription,
                        title: viewModel.issCardTitle,
                        emptyMessage: viewModel.issEmptyMessage
                    )
                }
                
                HourlyForecastView(
                    forecasts: viewModel.currentHourlyForecasts,
                    unitConverter: unitConverter,
                    timeZone: viewModel.displayTimeZone
                )
                
                if let sunEvents = viewModel.currentSunEvents,
                   let moonInfo = viewModel.currentMoonInfo {
                    SunMoonCard(
                        sunEvents: sunEvents,
                        tomorrowSunEvents: viewModel.nextSunEvents,
                        moonInfo: moonInfo,
                        timeZone: viewModel.displayTimeZone
                    )
                }
                
                if viewModel.selectedDay == .today {
                    CurrentConditionsCard(
                        forecast: viewModel.currentHourForecast,
                        unitConverter: unitConverter,
                        timeZone: viewModel.displayTimeZone
                    )
                }
                
                if let fetchedAt = viewModel.viewingConditions?.fetchedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text("Last updated: \(DateFormatters.timeAgo(from: fetchedAt, relativeTo: context.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top)
                    }
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
                .appPrimaryActionStyle()
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
        AppSegmentedPicker(
            selection: $viewModel.selectedDay,
            options: DashboardViewModel.DaySelection.allCases,
            pickerLabel: "Day"
        ) { day in
            Text(viewModel.titleForSelectedDay(day))
        }
        .scaleEffect(isIPad ? 1.2 : 1.0)
    }
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    private var shouldShowNormalIPadLocationTitle: Bool {
        horizontalSizeClass == .regular &&
        palette.appearance == .normal
    }

    private var normalIPadLocationTitle: some View {
        Text(selectedLocationName)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
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
        } catch {
            viewModel.error = error
        }
    }
    
    private func loadActiveLocationConditionsIfNeeded() async {
        guard let location = activeSavedLocation else { return }
        await viewModel.loadConditionsIfNeeded(for: location)
    }
}

#Preview {
    DashboardView()
        .appAppearance(fieldModeEnabled: false)
}

#Preview("Dashboard Dark") {
    DashboardView()
        .appAppearance(fieldModeEnabled: false)
        .preferredColorScheme(.dark)
}

#Preview("Dashboard Field Mode") {
    DashboardView()
        .appAppearance(fieldModeEnabled: true)
}
