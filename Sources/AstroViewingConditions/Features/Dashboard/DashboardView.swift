import SharedCode
import SwiftUI
import SwiftData
import WidgetKit

public struct DashboardView: View {
    private enum DashboardSection: String {
        case top
        case nightQuality
        case bestTargets
        case iss
        case hourlyForecast
        case sunMoon
        case currentConditions
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appPalette) private var palette
    @AppStorage("n2yoApiKey") private var n2yoApiKey: String = ""
    @AppStorage(FieldModePreference.key) private var fieldModeEnabled = FieldModePreference.defaultValue
    @SceneStorage("dashboardSelectedDay") private var storedSelectedDayRawValue: Int = DashboardViewModel.DaySelection.today.rawValue
    @Query(sort: \SavedLocation.dateAdded, order: .reverse) private var savedLocations: [SavedLocation]
    @Query(sort: \EquipmentItem.name) private var equipmentItems: [EquipmentItem]
    private let viewModel: DashboardViewModel
    @State private var locationLoader: DashboardLocationLoader
    @State private var showingLocationPicker = false
    @State private var showingBestSpotSearch = false
    @State private var showingAllBestTargets = false
    @State private var equipmentSessionSelection = EquipmentSessionSelection()
    @State private var minimumEquipmentFit: EquipmentFitThreshold = .any
    @State private var hasRestoredSelectedDay = false
    @State private var dashboardScrollPosition = ScrollPosition(edge: .top)
    @State private var dashboardScrollCoordinator = DashboardScrollCoordinator()
    private let locationSession: DashboardLocationSession
    
    init(
        viewModel: DashboardViewModel = DashboardViewModel(
            apiKey: UserDefaults.standard.string(forKey: "n2yoApiKey") ?? ""
        ),
        locationSession: DashboardLocationSession = DashboardLocationSession()
    ) {
        self.viewModel = viewModel
        self.locationSession = locationSession
        _locationLoader = State(initialValue: DashboardLocationLoader(
            persistedSelection: LocationStorageService.shared.loadSelectedLocation(),
            provider: LocationManager(),
            saveSelection: { LocationStorageService.shared.saveSelectedLocation($0) },
            locationSession: locationSession
        ))
    }
    
    private var unitConverter: AstroUnitConverter {
        AstroUnitConverter(unitSystem: UnitSystemStorage.loadSelectedUnitSystem())
    }
    
    private var selectedLocation: SelectedLocation {
        locationLoader.selectedLocation
    }

    private var currentLocation: CachedLocation? {
        locationLoader.currentLocation
    }

    private var activeLocation: CachedLocation? {
        locationLoader.activeLocation
    }

    private var activeSavedLocation: SavedLocation? {
        if selectedLocation.source == .currentGPS {
            guard let currentLocation else { return nil }
            return SavedLocation(
                name: currentLocation.name,
                latitude: currentLocation.latitude,
                longitude: currentLocation.longitude
            )
        }
        guard let id = selectedLocation.id else { return nil }
        return savedLocations.first { $0.id == id }
    }

    private var orderedSavedLocations: [SavedLocation] {
        SavedLocation.ordered(savedLocations)
    }

    private var equipmentCapabilities: [EquipmentCapability] {
        equipmentItems.map(\.matchingCapability)
    }

    private var bestTargetsPresentation: BestTargetsListPresentation {
        let completePresentation = viewModel.currentBestTargetsPresentation
        let filteredRecommendations = equipmentSessionSelection.filteredRecommendations(
            completePresentation.recommendations,
            inventory: equipmentCapabilities,
            minimumFit: minimumEquipmentFit
        )
        return BestTargetsListPresentation(recommendations: filteredRecommendations)
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
                        freezeDashboardScrollOffsetForFieldModeToggle()
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
                                if let location = activeLocation {
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
                    selectedLocation: selectedLocation,
                    onSelect: locationLoader.select,
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
                    presentation: bestTargetsPresentation,
                    timeZone: viewModel.displayTimeZone,
                    equipmentCapabilities: equipmentCapabilities,
                    sessionSelection: $equipmentSessionSelection,
                    minimumFit: $minimumEquipmentFit,
                    unfilteredPresentation: viewModel.currentBestTargetsPresentation
                )
                .adaptiveTargetSheet(horizontalSizeClass: horizontalSizeClass)
            }
        }
        .appScreenBackground()
        .task {
            restoreSelectedDay()
            hasRestoredSelectedDay = true
            viewModel.updateAPIKey(n2yoApiKey)
            locationLoader.restoreSelection(using: savedLocations.map(CachedLocation.init))
            await resolveCurrentLocationIfNeeded()
            await loadActiveLocationConditionsIfNeeded()
        }
        .onChange(of: locationLoader.authorizationStatus) { _, _ in
            guard selectedLocation.source == .currentGPS else { return }
            Task {
                await resolveCurrentLocationIfNeeded()
                await loadActiveLocationConditionsIfNeeded()
            }
        }
        .onChange(of: n2yoApiKey) { _, newKey in
            viewModel.updateAPIKey(newKey)
            Task {
                if let location = activeLocation {
                    await viewModel.refresh(for: location)
                }
            }
        }
        .onChange(of: viewModel.selectedDay) { _, newDay in
            guard hasRestoredSelectedDay else { return }
            storedSelectedDayRawValue = newDay.rawValue
        }
        .onChange(of: selectedLocation) { _, newValue in
            locationLoader.repairSelectionIfNeeded(using: savedLocations.map(CachedLocation.init))
            guard locationLoader.selectedLocation == newValue else { return }

            let internallyResolved = locationLoader.consumeInternallyResolvedSelectionUpdate(
                matching: newValue
            )
            if !internallyResolved {
                LocationStorageService.shared.saveSelectedLocation(newValue)
                Task {
                    await resolveCurrentLocationIfNeeded()
                    await loadActiveLocationConditionsIfNeeded()
                }
            }
            WatchConnectivityService.shared.sendSelectedLocationToWatch(newValue)
            let locations = LocationStorageService.shared.publishLocationsToWatch(context: modelContext)
            WatchConnectivityService.shared.sendLocationsToWatch(locations)
        }
        .onChange(of: savedLocations.map(\.id)) { _, _ in
            locationLoader.repairSelectionIfNeeded(using: savedLocations.map(CachedLocation.init))
        }
        .onChange(of: equipmentCapabilities.map(\.id)) { previousIDs, currentIDs in
            equipmentSessionSelection.reconcile(with: equipmentCapabilities)
            minimumEquipmentFit = EquipmentSessionSelection.minimumFitAfterInventoryTransition(
                currentMinimumFit: minimumEquipmentFit,
                previousInventoryIDs: previousIDs,
                currentInventoryIDs: currentIDs
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if viewModel.isDataStale, !viewModel.isLoading, let location = activeLocation {
                Task {
                    await viewModel.refresh(for: location)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchLocationSelected)) { notification in
            if let location = notification.object as? SelectedLocation {
                locationLoader.select(location)
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
        let bestTargets = bestTargetsPresentation

        return ScrollView {
            VStack(spacing: 16) {
                if viewModel.isDataStale {
                    staleDataBanner
                }

                daySelector
                    .id(DashboardSection.top)

                if let nightQuality = viewModel.currentNightQuality {
                    NightQualityCard(
                        assessment: nightQuality
                    )
                    .id(DashboardSection.nightQuality)
                }

                TonightsBestTargetsCard(
                    recommendations: bestTargets.dashboardRecommendations,
                    timeZone: viewModel.displayTimeZone,
                    nightQualityScore: viewModel.currentNightQuality?.calculatedScore,
                    hasAdditionalTargets: bestTargets.hasAdditionalTargets,
                    equipmentCapabilities: equipmentCapabilities,
                    sessionSelection: $equipmentSessionSelection,
                    minimumFit: $minimumEquipmentFit,
                    hasUnfilteredVisibleTargets: !viewModel.currentBestTargetsPresentation.sections(for: .all).isEmpty,
                    onViewAll: { showingAllBestTargets = true }
                )
                .id(DashboardSection.bestTargets)

                if viewModel.hasISSConfigured {
                    ISSCard(
                        passes: viewModel.currentISSPasses,
                        timeZone: viewModel.displayTimeZone,
                        errorMessage: viewModel.issError?.localizedDescription,
                        title: viewModel.issCardTitle,
                        emptyMessage: viewModel.issEmptyMessage
                    )
                    .id(DashboardSection.iss)
                }

                HourlyForecastView(
                    forecasts: viewModel.currentHourlyForecasts,
                    unitConverter: unitConverter,
                    timeZone: viewModel.displayTimeZone
                )
                .id(DashboardSection.hourlyForecast)

                if let sunEvents = viewModel.currentSunEvents,
                   let moonInfo = viewModel.currentMoonInfo {
                    SunMoonCard(
                        sunEvents: sunEvents,
                        tomorrowSunEvents: viewModel.nextSunEvents,
                        moonInfo: moonInfo,
                        timeZone: viewModel.displayTimeZone
                    )
                    .id(DashboardSection.sunMoon)
                }

                if viewModel.selectedDay == .today {
                    CurrentConditionsCard(
                        forecast: viewModel.currentHourForecast,
                        unitConverter: unitConverter,
                        timeZone: viewModel.displayTimeZone
                    )
                    .id(DashboardSection.currentConditions)
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
        .scrollPosition($dashboardScrollPosition)
        .onScrollGeometryChange(
            for: DashboardScrollOffset.self,
            of: { DashboardScrollOffset($0.contentOffset) }
        ) { _, offset in
            dashboardScrollCoordinator.receive(offset)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardWillToggleFieldMode)) { _ in
            dashboardScrollCoordinator.freezeCurrentOffset()
        }
        .task(id: dashboardScrollCoordinator.restoreRequestID) {
            guard let target = dashboardScrollCoordinator.restoreTarget else { return }

            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dashboardScrollPosition.scrollTo(point: target)
            }
        }
    }

    private func freezeDashboardScrollOffsetForFieldModeToggle() {
        dashboardScrollCoordinator.freezeCurrentOffset()
    }

    fileprivate struct DashboardScrollOffset: Equatable {
        var point: CGPoint = .zero

        init() {}

        init(_ point: CGPoint) {
            self.point = CGPoint(
                x: point.x.roundedToHalfPoint,
                y: point.y.roundedToHalfPoint
            )
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
                    await resolveCurrentLocationIfNeeded()
                    await loadActiveLocationConditionsIfNeeded()
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
            
            if selectedLocation.source == .currentGPS, !locationLoader.isAuthorized {
                Text("Location Access Required")
                    .font(.headline)
                
                Text("Please enable location services to see viewing conditions for your current location.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Enable Location") {
                    locationLoader.requestAuthorization()
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
            selection: Binding(
                get: { viewModel.selectedDay },
                set: { viewModel.selectedDay = $0 }
            ),
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

    private func restoreSelectedDay() {
        guard let storedDay = DashboardViewModel.DaySelection(
            rawValue: storedSelectedDayRawValue
        ) else {
            storedSelectedDayRawValue = DashboardViewModel.DaySelection.today.rawValue
            viewModel.selectedDay = .today
            return
        }

        if viewModel.selectedDay != storedDay {
            viewModel.selectedDay = storedDay
        }
    }

    private func resolveCurrentLocationIfNeeded() async {
        do {
            _ = try await locationLoader.resolveCurrentLocationIfNeeded()
        } catch {
            viewModel.error = error
        }
    }
    
    private func loadActiveLocationConditionsIfNeeded() async {
        guard let location = activeLocation else { return }
        await viewModel.loadConditionsIfNeeded(for: location)
    }
}

@MainActor
@Observable
private final class DashboardScrollCoordinator {
    private static let layoutResetOffsetThreshold: CGFloat = 24

    @ObservationIgnored
    private var stableOffset = DashboardView.DashboardScrollOffset()
    @ObservationIgnored
    private var pendingOffset: DashboardView.DashboardScrollOffset?
    @ObservationIgnored
    private var geometryTask: Task<Void, Never>?
    @ObservationIgnored
    private var frozenOffset: CGPoint?
    @ObservationIgnored
    private var lastRestoreTarget: CGPoint?
    private(set) var restoreTarget: CGPoint?
    private(set) var restoreRequestID = UUID()

    func receive(_ offset: DashboardView.DashboardScrollOffset) {
        guard !offset.isApproximatelyEqual(to: pendingOffset ?? stableOffset) else {
            return
        }

        pendingOffset = offset
        guard geometryTask == nil else { return }

        geometryTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            processPendingGeometry()
        }
    }

    func freezeCurrentOffset() {
        if let pendingOffset {
            stableOffset = pendingOffset
            self.pendingOffset = nil
            geometryTask?.cancel()
            geometryTask = nil
        }

        frozenOffset = stableOffset.point
        lastRestoreTarget = nil
        restoreTarget = nil
    }

    private func processPendingGeometry() {
        guard let offset = pendingOffset else {
            geometryTask = nil
            return
        }

        pendingOffset = nil
        geometryTask = nil
        stableOffset = offset

        if let frozenOffset,
           offset.point.isMateriallyDisplaced(from: frozenOffset, threshold: Self.layoutResetOffsetThreshold) {
            scheduleRestoreIfNeeded()
        }

        if let frozenOffset,
           offset.point.isApproximatelyEqual(to: frozenOffset) {
            self.frozenOffset = nil
            lastRestoreTarget = nil
            restoreTarget = nil
        }
    }

    private func scheduleRestoreIfNeeded() {
        guard let target = frozenOffset else { return }

        guard lastRestoreTarget.map({ !target.isApproximatelyEqual(to: $0) }) ?? true else { return }
        lastRestoreTarget = target
        restoreTarget = target
        restoreRequestID = UUID()
    }
}

private extension DashboardView.DashboardScrollOffset {
    func isApproximatelyEqual(to other: DashboardView.DashboardScrollOffset) -> Bool {
        point.isApproximatelyEqual(to: other.point)
    }
}

private extension CGPoint {
    func isApproximatelyEqual(to other: CGPoint) -> Bool {
        abs(x - other.x) < 0.5 && abs(y - other.y) < 0.5
    }

    func isMateriallyDisplaced(from other: CGPoint, threshold: CGFloat) -> Bool {
        abs(x - other.x) >= threshold || abs(y - other.y) >= threshold
    }
}

private extension CGFloat {
    var roundedToHalfPoint: CGFloat {
        (self * 2).rounded() / 2
    }
}

extension Notification.Name {
    static let dashboardWillToggleFieldMode = Notification.Name("dashboardWillToggleFieldMode")
}

extension LocationManager: DashboardCurrentLocationProviding {
    func resolveCurrentLocation() async throws -> CachedLocation {
        let coordinate = try await getCurrentLocation()
        let fallbackName = CoordinateFormatters.format(
            Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
        let placemark = try? await reverseGeocode(coordinate: coordinate)
        let name = placemark?.locality ?? placemark?.administrativeArea ?? placemark?.name ?? fallbackName

        return CachedLocation(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
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
