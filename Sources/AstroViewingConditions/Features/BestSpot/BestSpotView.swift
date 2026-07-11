import SharedCode
import SwiftUI
import MapKit

struct BestSpotView: View {
    let centerLocation: SavedLocation
    let searchDate: Date
    let fogScoreCalculator: @Sendable (HourlyForecast) -> FogScore
    
    public init(centerLocation: SavedLocation, searchDate: Date, fogScoreCalculator: @escaping @Sendable (HourlyForecast) -> FogScore = FogCalculator.calculate) {
        self.centerLocation = centerLocation
        self.searchDate = searchDate
        self.fogScoreCalculator = fogScoreCalculator
        _viewModel = State(initialValue: BestSpotViewModel(fogScoreCalculator: fogScoreCalculator))
        
        let coordinate = CLLocationCoordinate2D(
            latitude: centerLocation.latitude,
            longitude: centerLocation.longitude
        )
        let span = MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(center: coordinate, span: span)))
    }
    
    @State private var viewModel: BestSpotViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPalette) private var palette
    @State private var selectedLocation: LocationScore?
    @State private var mapPosition: MapCameraPosition
    @State private var showingSettings = false
    @State private var centerTimeZone: TimeZone?
    
    @State private var searchRadius: Double = BestSpotSettings.searchRadius
    @State private var gridSpacing: Double = BestSpotSettings.gridSpacing
    @State private var previousSearchRadius: Double = BestSpotSettings.searchRadius
    @State private var previousGridSpacing: Double = BestSpotSettings.gridSpacing
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isSearching {
                    searchProgressView
                } else if let error = viewModel.error {
                    errorView(error: error)
                } else if let result = viewModel.result {
                    resultsView(result: result)
                } else {
                    initialView
                }
            }
            .appNavigationTitle("Find Best Nearby Area", displayMode: .large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelSearch()
                        dismiss()
                    }
                    .appToolbarButtonStyle()
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        // Capture current settings before opening
                        previousSearchRadius = searchRadius
                        previousGridSpacing = gridSpacing
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Search Settings")
                    .accessibilityHint("Adjusts the nearby-area search radius and spacing.")
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                // Only refresh if settings actually changed
                if searchRadius != previousSearchRadius || gridSpacing != previousGridSpacing {
                    viewModel.startSearch(around: centerLocation, for: searchDate, topN: 5)
                }
            }) {
                BestSpotSettingsView()
            }
        }
        .appScreenBackground()
        .task {
            centerTimeZone = await LocationTimeZoneResolver.resolve(
                latitude: centerLocation.latitude,
                longitude: centerLocation.longitude
            )
            viewModel.startSearch(around: centerLocation, for: searchDate, topN: 5)
        }
        .onDisappear {
            viewModel.cancelSearch()
        }
    }
    
    // MARK: - Subviews
    
    private var initialView: some View {
        VStack(spacing: 20) {
            Image(systemName: "binoculars")
                .font(.system(size: 60))
                .foregroundStyle(palette.appearance == .field ? palette.accent : .blue)
            
            Text("Searching \(viewModel.searchRadiusDisplay) around \(centerLocation.name)")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("For \(DateFormatters.formatShortDate(searchDate, in: centerTimeZone)) night")
                .font(.subheadline)
                .appSecondaryForeground()
            
            Button("Start Search") {
                viewModel.startSearch(around: centerLocation, for: searchDate, topN: 5)
            }
            .appPrimaryActionStyle()
            .padding(.top)
        }
        .padding()
    }
    
    private var searchProgressView: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.searchProgress)
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
            
            Text("Scanning \(viewModel.searchRadiusDisplay) around \(centerLocation.name)...")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("Checking \(Int(viewModel.searchProgress * 100))% complete")
                .font(.subheadline)
                .appSecondaryForeground()
            
            if viewModel.searchProgress > 0.5 {
                Text("Analyzing viewing conditions...")
                    .font(.caption)
                    .appSecondaryForeground()
            }
            
            Button("Cancel") {
                viewModel.cancelSearch()
            }
            .buttonStyle(.bordered)
            .padding(.top)
        }
        .padding()
    }
    
    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                .foregroundStyle(palette.appearance == .field ? palette.statusColor(.caution) : .orange)
            
            Text("Search Failed")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .appSecondaryForeground()
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await viewModel.search(around: centerLocation, for: searchDate, topN: 5)
                }
            }
            .appPrimaryActionStyle()
            .padding(.top)
        }
        .padding()
    }
    
    private func resultsView(result: BestSpotResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                resultsHeader(result: result)
                
                // Map
                BestSpotMapView(
                    centerLocation: centerLocation,
                    scoredLocations: result.allScoredLocations,
                    topLocations: result.topLocations,
                    selectedLocation: $selectedLocation,
                    position: $mapPosition
                )
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.border, lineWidth: palette.appearance == .field ? 1 : 0)
                }

                if let selectedLocation {
                    BestSpotSelectedMapLocationView(
                        location: selectedLocation,
                        rank: result.rank(of: selectedLocation),
                        centerName: centerLocation.name,
                        openInMaps: {
                            viewModel.openInMaps(location: selectedLocation, centerName: centerLocation.name)
                        }
                    )
                    .padding(.horizontal)
                }
                
                // Results list
                if !result.topLocations.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Areas")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(Array(result.topLocations.enumerated()), id: \.element.id) { index, location in
                            BestSpotResultCard(
                                locationScore: location,
                                rank: index + 1,
                                isSelected: selectedLocation?.id == location.id,
                                onTap: {
                                    withAnimation {
                                        selectedLocation = location
                                        updateMapRegion(for: location)
                                    }
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                }

                if let suitabilityWarning = result.suitabilityWarning {
                    Text(suitabilityWarning)
                        .font(.caption)
                        .appSecondaryForeground()
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal)
                }
                
                // Moon info
                moonInfoSection(moonInfo: result.moonInfo)
                
                // Search metadata
                if let duration = viewModel.searchDurationDisplay {
                    Text("Search completed in \(duration)")
                        .font(.caption)
                        .appSecondaryForeground()
                }
            }
            .padding(.vertical)
        }
    }
    
    private func resultsHeader(result: BestSpotResult) -> some View {
        VStack(spacing: 8) {
            if let bestSpot = result.bestSpot {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundStyle(palette.appearance == .field ? palette.statusColor(.caution) : .yellow)
                    
                    VStack(alignment: .leading) {
                        Text("Best Nearby Area Found")
                            .font(.headline)
                        Text("\(bestSpot.fullLocationString) from \(centerLocation.name)")
                            .font(.subheadline)
                            .appSecondaryForeground()
                    }
                    
                    Spacer()
                    
                    Text("\(bestSpot.score)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(TargetScoreColorProvider.color(for: bestSpot.score, palette: palette))
                }
                
                if bestSpot.canOpenInMaps {
                    Button("Open Area in Maps") {
                        viewModel.openInMaps(location: bestSpot, centerName: centerLocation.name)
                    }
                    .appPrimaryActionStyle()
                }

                Text("This checks sky and weather conditions only. Verify access, safety, parking, local rules, and horizon obstructions before traveling.")
                    .font(.caption)
                    .appSecondaryForeground()
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .background(
            palette.appearance == .field
                ? palette.subduedFill
                : Color.blue.opacity(0.1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.border, lineWidth: palette.appearance == .field ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private func moonInfoSection(moonInfo: MoonInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Moon Conditions")
                .font(.headline)
            
            HStack {
                Text(moonInfo.emoji)
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(moonInfo.phaseName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(moonInfo.illumination)% illuminated")
                        .font(.caption)
                        .appSecondaryForeground()
                }
                
                Spacer()
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    // MARK: - Helper Methods
    
    private func updateMapRegion(for location: LocationScore) {
        let coordinate = CLLocationCoordinate2D(
            latitude: location.point.coordinate.latitude,
            longitude: location.point.coordinate.longitude
        )
        withAnimation {
            mapPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ))
        }
    }
    
    private var cardBackgroundColor: Color {
        palette.elevatedBackground
    }
}

// MARK: - Map View

struct BestSpotMapView: View {
    @Environment(\.appPalette) private var palette
    let centerLocation: SavedLocation
    let scoredLocations: [LocationScore]
    let topLocations: [LocationScore]
    let mode: BestSpotMapMode
    @Binding var selectedLocation: LocationScore?
    @Binding var position: MapCameraPosition

    init(
        centerLocation: SavedLocation,
        scoredLocations: [LocationScore],
        topLocations: [LocationScore],
        mode: BestSpotMapMode = .recommendedOnly,
        selectedLocation: Binding<LocationScore?>,
        position: Binding<MapCameraPosition>
    ) {
        self.centerLocation = centerLocation
        self.scoredLocations = scoredLocations
        self.topLocations = topLocations
        self.mode = mode
        _selectedLocation = selectedLocation
        _position = position
    }
    
    var body: some View {
        Map(position: $position) {
            // Center annotation
            Annotation(centerLocation.name, coordinate: centerCoordinate) {
                Image(systemName: "location.circle.fill")
                    .font(.title)
                    .foregroundStyle(palette.appearance == .field ? palette.accent : .blue)
            }
            
            // Grid point annotations
            ForEach(annotationItems) { item in
                Annotation(annotationTitle(for: item.location), coordinate: coordinate(for: item.location)) {
                    Button {
                        selectedLocation = item.location
                    } label: {
                        BestSpotMapAnnotation(
                            score: item.location.score,
                            role: item.role,
                            isSelected: selectedLocation?.id == item.location.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: item))
                }
            }
        }
        .appMapStyle()
    }
    
    private var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: centerLocation.latitude,
            longitude: centerLocation.longitude
        )
    }
    
    private func coordinate(for location: LocationScore) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: location.point.coordinate.latitude,
            longitude: location.point.coordinate.longitude
        )
    }
    
    private func rank(of location: LocationScore) -> Int? {
        topLocations.firstIndex { $0.id == location.id }.map { $0 + 1 }
    }

    private func annotationTitle(for _: LocationScore) -> String {
        ""
    }

    private func accessibilityLabel(for item: BestSpotMapAnnotationItem) -> String {
        if let rank = item.role.rank {
            let location = item.location
            return "Recommended area \(rank), score \(location.score)"
        }

        let location = item.location
        return "Weather estimate, score \(location.score). \(location.suitability.label)"
    }

    private var annotationItems: [BestSpotMapAnnotationItem] {
        Self.annotationItems(
            scoredLocations: scoredLocations,
            topLocations: topLocations,
            mode: mode
        )
    }

    static func annotationItems(
        scoredLocations: [LocationScore],
        topLocations: [LocationScore],
        mode: BestSpotMapMode = .recommendedOnly
    ) -> [BestSpotMapAnnotationItem] {
        switch mode {
        case .recommendedOnly:
            return topLocations.enumerated().map { index, location in
                BestSpotMapAnnotationItem(
                    location: location,
                    role: .recommendation(rank: index + 1)
                )
            }
        case .weatherField:
            return scoredLocations.map { location in
                BestSpotMapAnnotationItem(
                    location: location,
                    role: markerRole(for: location, topLocations: topLocations)
                )
            }
        }
    }

    static func markerRole(for location: LocationScore, topLocations: [LocationScore]) -> BestSpotMapMarkerRole {
        topLocations.firstIndex(where: { $0.id == location.id })
            .map { .recommendation(rank: $0 + 1) } ?? .context
    }
}

enum BestSpotMapMode {
    case recommendedOnly
    case weatherField
}

struct BestSpotMapAnnotationItem: Identifiable, Equatable {
    let location: LocationScore
    let role: BestSpotMapMarkerRole

    var id: LocationScore.ID {
        location.id
    }
}

enum BestSpotMapMarkerRole: Equatable {
    case recommendation(rank: Int)
    case context

    var isRecommendation: Bool {
        if case .recommendation = self { return true }
        return false
    }

    var rank: Int? {
        if case .recommendation(let rank) = self { return rank }
        return nil
    }
}

struct BestSpotMapAnnotation: View {
    @Environment(\.appPalette) private var palette
    let score: Int
    let role: BestSpotMapMarkerRole
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: markerSize, height: markerSize)
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: isSelected ? 3 : borderWidth)
                )
            
            if let rank = role.rank {
                Text("\(rank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(palette.appearance == .field ? palette.primaryActionLabel : .white)
            }
        }
    }
    
    private var backgroundColor: Color {
        switch role {
        case .context:
            return scoreTint.opacity(isSelected ? 0.55 : 0.28)
        case .recommendation:
            return scoreTint
        }
    }

    private var scoreTint: Color {
        TargetScoreColorProvider.color(for: score, palette: palette)
    }

    private var markerSize: CGFloat {
        switch role {
        case .context:
            return isSelected ? 14 : 9
        case .recommendation:
            return isSelected ? 44 : 36
        }
    }

    private var borderColor: Color {
        if isSelected { return palette.appearance == .field ? palette.accent : .blue }
        return role.isRecommendation
            ? (palette.appearance == .field ? palette.primaryText : .white)
            : .clear
    }

    private var borderWidth: CGFloat {
        role.isRecommendation ? 2 : 0
    }
}

struct BestSpotSelectedMapLocationView: View {
    @Environment(\.appPalette) private var palette
    let location: LocationScore
    let rank: Int?
    let centerName: String
    let openInMaps: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: rank == nil ? "circle.grid.cross" : "mappin.circle.fill")
                .foregroundStyle(
                    rank == nil
                        ? palette.secondaryText
                        : TargetScoreColorProvider.color(for: location.score, palette: palette)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(detail)
                    .font(.caption2)
                    .appSecondaryForeground()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if Self.canOpenInMaps(location: location, rank: rank) {
                Button("Open Area in Maps", action: openInMaps)
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        if let rank {
            return "Recommended area #\(rank) - \(location.score)/100"
        }

        return "Weather estimate - \(location.score)/100"
    }

    private var detail: String {
        if rank == nil {
            return location.suitability.label
        }

        return "\(location.fullLocationString) from \(centerName) - \(location.suitability.label)"
    }

    static func canOpenInMaps(location: LocationScore, rank: Int?) -> Bool {
        location.canOpenInMaps && rank != nil
    }

    private var cardBackgroundColor: Color {
        palette.elevatedBackground
    }
}

// MARK: - Settings View

struct BestSpotSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchRadius: Double = BestSpotSettings.searchRadius
    @State private var gridSpacing: Double = BestSpotSettings.gridSpacing
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Search Area") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Radius")
                            Spacer()
                            Text("\(Int(searchRadius)) miles")
                                .appSecondaryForeground()
                        }
                        
                        Slider(
                            value: $searchRadius,
                            in: BestSpotSettings.minSearchRadius...BestSpotSettings.maxSearchRadius,
                            step: 5
                        )
                        .onChange(of: searchRadius) { _, newValue in
                            BestSpotSettings.searchRadius = newValue
                        }
                        
                        Text("Searches up to \(Int(searchRadius)) miles from your location")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Grid Spacing")
                            Spacer()
                            Text("\(Int(gridSpacing)) miles")
                                .appSecondaryForeground()
                        }
                        
                        Slider(
                            value: $gridSpacing,
                            in: BestSpotSettings.minGridSpacing...BestSpotSettings.maxGridSpacing,
                            step: 1
                        )
                        .onChange(of: gridSpacing) { _, newValue in
                            BestSpotSettings.gridSpacing = newValue
                        }
                        
                        Text("Checks a point every \(Int(gridSpacing)) miles")
                            .font(.caption)
                            .appSecondaryForeground()
                    }
                }
                
                Section("Estimated Search Points") {
                    let estimatedPoints = GeographicGridGenerator.estimatedPointCount(
                        radiusMiles: searchRadius,
                        spacingMiles: gridSpacing
                    )
                    HStack {
                        Text("Points to check")
                        Spacer()
                        Text("~\(estimatedPoints)")
                            .appSecondaryForeground()
                    }
                    
                    Text("Fewer points = faster search, more points = better coverage")
                        .font(.caption)
                        .appSecondaryForeground()
                }
            }
            .appListBackground()
            .appNavigationTitle("Search Settings", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
}

#Preview("Best Nearby Area Field Mode") {
    BestSpotView(
        centerLocation: SavedLocation(
            name: "Mount Diablo",
            latitude: 37.8816,
            longitude: -121.9142,
            elevation: 1_173
        ),
        searchDate: Date()
    )
    .appAppearance(fieldModeEnabled: true)
}
