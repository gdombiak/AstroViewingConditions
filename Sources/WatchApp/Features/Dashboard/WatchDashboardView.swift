import SwiftUI
import SharedCode

struct WatchDashboardView: View {
    @State private var weatherService = WeatherService()
    @State private var astronomyService = AstronomyService()
    
    @State private var nightQuality: NightQualityAssessment?
    @State private var isLoading = false
    @State private var error: String?
    @ObservedObject var connectivityManager = WatchConnectivityManager.shared
    @ObservedObject var locationManager = WatchLocationManager.shared
    
    var body: some View {
        
        return NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LocationSelectorView(
                        locations: locationManager.locations,
                        selectedLocation: locationManager.selectedLocation,
                        onSelectionChanged: { locationManager.select($0) }
                    )

                    if isLoading {
                        ProgressView()
                            .padding()
                    }

                    if let errorMsg = error {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if let assessment = nightQuality {
                        WatchNightQualityCard(assessment: assessment)
                    }

                    if let conditions = connectivityManager.conditions {
                        let now = Date()
                        let calendar = Calendar.current
                        
                        let todayForecasts = conditions.hourlyForecasts.filter { forecast in
                            calendar.isDate(forecast.time, inSameDayAs: now)
                        }
                        
                        let currentHourForecast = todayForecasts.first { forecast in
                            calendar.component(.hour, from: forecast.time) == calendar.component(.hour, from: now)
                        } ?? todayForecasts.first
                        
                        if let forecast = currentHourForecast {
                            WatchCurrentConditionsCard(forecast: forecast)
                        }
                    }

                    if let sunEvents = connectivityManager.conditions?.dailySunEvents.first,
                       let moonInfo = connectivityManager.conditions?.dailyMoonInfo.first {
                        WatchAstronomicalNightCard(sunEvents: sunEvents, moonInfo: moonInfo)
                    }

                    Button(action: refresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .task {
                WatchLocationManager.shared.refresh()
            }
            .onAppear {
                refresh()
            }
            .onChange(of: connectivityManager.conditions?.fetchedAt) { _, newFetchedAt in
                guard let conditions = connectivityManager.conditions,
                      let sunEventsToday = conditions.dailySunEvents.first,
                      let sunEventsTomorrow = conditions.dailySunEvents.dropFirst().first,
                      let moonInfo = conditions.dailyMoonInfo.first else {
                    return
                }
                
                let assessment = NightQualityAnalyzer.analyzeNight(
                    forecasts: conditions.hourlyForecasts,
                    sunEventsToday: sunEventsToday,
                    sunEventsTomorrow: sunEventsTomorrow,
                    moonInfo: moonInfo,
                    latitude: conditions.location.latitude,
                    longitude: conditions.location.longitude,
                    for: Calendar.current.startOfDay(for: Date())
                )
                
                self.nightQuality = assessment
            }
        }
    }

    private func refresh() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task {
            do {
                let (latitude, longitude) = try await WatchLocationManager.shared.getCurrentCoordinate()
                
                let cachedLocation = try await reverseGeocode(latitude: latitude, longitude: longitude)
                
                AppGroupStorage.saveWidgetLocation(CachedLocation(
                    name: cachedLocation.name,
                    latitude: latitude,
                    longitude: longitude
                ))
                WidgetReloadService.shared.scheduleReload()

                let forecast = try await weatherService.fetchForecast(latitude: latitude, longitude: longitude, days: 3)
                
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
                
                let sunEventsToday = await astronomyService.calculateSunEvents(latitude: latitude, longitude: longitude, on: today)
                let sunEventsTomorrow = await astronomyService.calculateSunEvents(latitude: latitude, longitude: longitude, on: tomorrow)
                let moonInfo = await astronomyService.calculateMoonInfo(latitude: latitude, longitude: longitude, on: today)

                let assessment = NightQualityAnalyzer.analyzeNight(
                    forecasts: forecast,
                    sunEventsToday: sunEventsToday,
                    sunEventsTomorrow: sunEventsTomorrow,
                    moonInfo: moonInfo,
                    latitude: latitude,
                    longitude: longitude,
                    for: today
                )

                connectivityManager.conditions = ViewingConditions(
                    fetchedAt: Date(),
                    location: cachedLocation,
                    hourlyForecasts: forecast,
                    dailySunEvents: [sunEventsToday, sunEventsTomorrow],
                    dailyMoonInfo: [moonInfo],
                    issPasses: [],
                    fogScore: FogScore(score: 0, factors: [])
                )
                nightQuality = assessment
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func reverseGeocode(latitude: Double, longitude: Double) async throws -> CachedLocation {
        return CachedLocation(
            name: String(format: "%.4f, %.4f", latitude, longitude),
            latitude: latitude,
            longitude: longitude
        )
    }
}
