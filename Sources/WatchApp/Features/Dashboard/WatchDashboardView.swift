import SwiftUI
import SharedCode

struct WatchDashboardView: View {
    @State private var weatherService = WeatherService()
    @State private var astronomyService = AstronomyService()
    
    @State private var error: String?
    @ObservedObject var locationManager = WatchLocationManager.shared
    
    var locationOptions: [LocationOption] {
        LocationOption.fromLocations(saved: locationManager.locations)
    }
    
    var body: some View {
        return NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LocationSelectorView(
                        locations: locationOptions,
                        selectedLocation: locationManager.selectedLocation,
                        onSelectionChanged: { handleSelection($0) }
                    )

                    if locationManager.isLoading {
                        ProgressView()
                            .padding()
                    }

                    if let errorMsg = error {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if let assessment = locationManager.nightQuality {
                        WatchNightQualityCard(assessment: assessment)
                    }

                    if let conditions = locationManager.conditions {
                        let now = Date()
                        let calendar = Calendar.current
                        
                        let todayForecasts = conditions.hourlyForecasts.filter { forecast in
                            calendar.isDate(forecast.time, inSameDayAs: now)
                        }
                        
                        let currentHourForecast = todayForecasts.first { forecast in
                            calendar.component(.hour, from: forecast.time) == calendar.component(.hour, from: now)
                        } ?? todayForecasts.first
                        
                        if let forecast = currentHourForecast {
                            WatchCurrentConditionsCard(forecast: forecast, unitSystem: locationManager.unitSystem)
                        }
                    }

                    if let sunEvents = locationManager.conditions?.dailySunEvents.first,
                       let moonInfo = locationManager.conditions?.dailyMoonInfo.first {
                        WatchAstronomicalNightCard(sunEvents: sunEvents, moonInfo: moonInfo)
                    }

                    Button(action: { Task { await refresh() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .task {
                await refresh()
            }
            .onChange(of: locationManager.conditions?.fetchedAt) { _, _ in
                Task {
                    guard let conditions = locationManager.conditions,
                          let sunEventsToday = conditions.dailySunEvents.first,
                          let sunEventsTomorrow = conditions.dailySunEvents.dropFirst().first,
                          let moonInfo = conditions.dailyMoonInfo.first else {
                        return
                    }
                    
                    let tz = await LocationTimeZoneResolver.resolve(latitude: conditions.location.latitude, longitude: conditions.location.longitude)
                    let calendar = LocationTimeZoneResolver.calendar(for: tz)
                    let today = calendar.startOfDay(for: Date())
                    
                    let assessment = NightQualityAnalyzer.analyzeNight(
                        forecasts: conditions.hourlyForecasts,
                        sunEventsToday: sunEventsToday,
                        sunEventsTomorrow: sunEventsTomorrow,
                        moonInfo: moonInfo,
                        latitude: conditions.location.latitude,
                        longitude: conditions.location.longitude,
                        for: today,
                        calendar: calendar
                    )
                    
                    locationManager.nightQuality = assessment
                }
            }
        }
    }
    
    private func handleSelection(_ option: LocationOption) {
        switch option {
        case .current:
            locationManager.selectCurrentLocation()
        case .saved(let location):
            locationManager.select(location)
        }
    }

    @MainActor
    private func refresh() async {
        error = nil

        await locationManager.refresh()
    }

}
