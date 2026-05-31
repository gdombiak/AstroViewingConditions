import SwiftUI
import SharedCode

struct WatchDashboardView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var locationManager = WatchLocationManager.shared
    @ObservedObject var conditionsManager = WatchConditionsManager.shared
    @State private var isAutomaticRefreshInFlight = false
    @State private var lastActiveCheck = Date()
    
    var locationOptions: [LocationOption] {
        LocationOption.fromLocations(saved: locationManager.locations)
    }

    private var currentHourForecast: HourlyForecast? {
        guard let conditions = conditionsManager.conditions else { return nil }

        let now = Date()
        let calendar = conditionsManager.locationCalendar
        let todayForecasts = conditions.hourlyForecasts.filter { forecast in
            calendar.isDate(forecast.time, inSameDayAs: now)
        }

        return todayForecasts.first { forecast in
            calendar.component(.hour, from: forecast.time) == calendar.component(.hour, from: now)
        } ?? todayForecasts.first
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    LocationSelectorView(
                        locations: locationOptions,
                        selectedLocation: locationManager.selectedLocation,
                        isRefreshingLocations: locationManager.isLoading,
                        isRefreshingConditions: conditionsManager.isLoading,
                        onSelectionChanged: { handleSelection($0) },
                        onRefreshLocations: {
                            Task {
                                await locationManager.refresh()
                            }
                        },
                        onRefreshConditions: {
                            Task {
                                await refreshConditions()
                            }
                        }
                    )

                    if locationManager.isLoading || conditionsManager.isLoading {
                        ProgressView()
                            .padding()
                    }

                    if let refreshErrorMessage {
                        Text(refreshErrorMessage)
                            .font(.caption2)
                            .foregroundStyle(conditionsManager.conditions == nil ? .red : .orange)
                            .multilineTextAlignment(.center)
                    }

                    if let assessment = conditionsManager.nightQuality {
                        WatchNightQualityCard(assessment: assessment)
                    }

                    if let currentHourForecast {
                        WatchCurrentConditionsCard(forecast: currentHourForecast, unitSystem: locationManager.unitSystem)
                    }

                    if let sunEvents = conditionsManager.conditions?.dailySunEvents.first,
                       let moonInfo = conditionsManager.conditions?.dailyMoonInfo.first {
                        WatchAstronomicalNightCard(
                            sunEvents: sunEvents,
                            tomorrowSunEvents: conditionsManager.conditions?.dailySunEvents.dropFirst().first,
                            moonInfo: moonInfo,
                            timeZone: conditionsManager.displayTimeZone
                        )
                    }

                    if let fetchedAt = conditionsManager.conditions?.fetchedAt {
                        Text("Updated: \(DateFormatters.timeAgo(from: fetchedAt, relativeTo: lastActiveCheck))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding()
            }
            .task {
                if locationManager.selectedLocation == nil {
                    await locationManager.refresh()
                }

                await refreshConditionsIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    lastActiveCheck = Date()
                    Task {
                        await refreshConditionsIfNeeded()
                    }
                }
            }
            .onReceive(conditionsManager.$conditions) { _ in
                Task {
                    await updateNightQuality()
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

        Task {
            await refreshConditions()
        }
    }

    @MainActor
    private func refreshConditions() async {
        guard !conditionsManager.isLoading else { return }

        await conditionsManager.refresh()
    }

    @MainActor
    private func refreshConditionsIfNeeded() async {
        guard !isAutomaticRefreshInFlight else { return }
        await conditionsManager.loadNewerSharedCacheIfAvailable()
        guard conditionsManager.shouldRefresh else { return }

        isAutomaticRefreshInFlight = true
        defer { isAutomaticRefreshInFlight = false }

        await refreshConditions()
    }

    private var refreshErrorMessage: String? {
        guard conditionsManager.error != nil else { return nil }
        return conditionsManager.conditions == nil
            ? "Unable to load conditions."
            : "Refresh failed. Showing saved data."
    }

    private func updateNightQuality() async {
        guard let conditions = conditionsManager.conditions,
              let assessment = NightQualityAnalyzer.analyzeConditions(conditions) else {
            return
        }

        await MainActor.run {
            conditionsManager.nightQuality = assessment
        }
    }

}
