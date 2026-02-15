import SwiftUI
import SwiftData

public struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = DashboardViewModel()
    @State private var locationManager = LocationManager()
    
    // Current location (not persisted)
    @State private var currentLocation: SavedLocation?
    
    private var unitConverter: UnitConverter {
        UnitConverter(unitSystem: UserDefaults.standard.selectedUnitSystem)
    }
    
    public init() {}
    
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
            .navigationTitle(currentLocation?.name ?? "Astro Conditions")
            .toolbar {
                ToolbarItem(placement: toolbarPlacement) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button(action: {
                            Task {
                                if let location = currentLocation {
                                    await viewModel.refresh(for: location)
                                }
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(currentLocation == nil)
                    }
                }
            }
        }
        .task {
            await loadCurrentLocation()
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            Task {
                await loadCurrentLocation()
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
                
                // Current conditions summary
                CurrentConditionsCard(
                    forecast: viewModel.currentHourlyForecasts.first,
                    unitConverter: unitConverter
                )
                
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
                
                // Fog score
                if let fogScore = viewModel.fogScore, fogScore.percentage > 0 {
                    FogScoreView(fogScore: fogScore)
                }
                
                // ISS passes
                if !viewModel.currentISSPasses.isEmpty {
                    ISSCard(passes: viewModel.currentISSPasses)
                }
                
                // Last updated
                Text("Last updated: \(DateFormatters.timeAgo(from: conditions.fetchedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }
            .padding()
        }
        .refreshable {
            if let location = currentLocation {
                await viewModel.refresh(for: location)
            }
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
            Text("Data may be outdated. Pull to refresh.")
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
                Text(day.title).tag(day)
            }
        }
        .pickerStyle(.segmented)
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
                await viewModel.loadConditions(for: location)
            }
        } catch {
            viewModel.error = error
        }
    }
}

#Preview {
    DashboardView()
}
