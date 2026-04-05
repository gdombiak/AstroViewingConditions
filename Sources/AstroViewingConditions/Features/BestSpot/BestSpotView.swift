import SharedCode
import SwiftUI
import MapKit

struct BestSpotView: View {
    let centerLocation: SavedLocation
    let searchDate: Date
    let fogScoreCalculator: (HourlyForecast) -> FogScore
    
    public init(centerLocation: SavedLocation, searchDate: Date, fogScoreCalculator: @escaping (HourlyForecast) -> FogScore = FogCalculator.calculate) {
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
    @State private var selectedLocation: LocationScore?
    @State private var mapPosition: MapCameraPosition
    @State private var showingSettings = false
    
    @AppStorage(BestSpotSettings.searchRadiusKey) private var searchRadius: Double = BestSpotSettings.defaultSearchRadius
    @AppStorage(BestSpotSettings.gridSpacingKey) private var gridSpacing: Double = BestSpotSettings.defaultGridSpacing
    @State private var previousSearchRadius: Double = BestSpotSettings.defaultSearchRadius
    @State private var previousGridSpacing: Double = BestSpotSettings.defaultGridSpacing
    
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
            .navigationTitle("Find Best Spot")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelSearch()
                        dismiss()
                    }
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
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                // Only refresh if settings actually changed
                if searchRadius != previousSearchRadius || gridSpacing != previousGridSpacing {
                    Task {
                        await viewModel.search(around: centerLocation, for: searchDate, topN: 5)
                    }
                }
            }) {
                BestSpotSettingsView()
            }
        }
        .task {
            await viewModel.search(around: centerLocation, for: searchDate, topN: 5)
        }
    }
    
    // MARK: - Subviews
    
    private var initialView: some View {
        VStack(spacing: 20) {
            Image(systemName: "binoculars")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Searching \(viewModel.searchRadiusDisplay) around \(centerLocation.name)")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("For \(DateFormatters.formatShortDate(searchDate)) night")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button("Start Search") {
                Task {
                    await viewModel.search(around: centerLocation, for: searchDate, topN: 5)
                }
            }
            .buttonStyle(.borderedProminent)
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
                .foregroundStyle(.secondary)
            
            if viewModel.searchProgress > 0.5 {
                Text("Analyzing viewing conditions...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.orange)
            
            Text("Search Failed")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await viewModel.search(around: centerLocation, for: searchDate, topN: 5)
                }
            }
            .buttonStyle(.borderedProminent)
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
                    scoredLocations: result.scoredLocations,
                    selectedLocation: $selectedLocation,
                    position: $mapPosition
                )
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Results list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top Locations")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(Array(result.scoredLocations.enumerated()), id: \.element.id) { index, location in
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
                
                // Moon info
                moonInfoSection(moonInfo: result.moonInfo)
                
                // Search metadata
                if let duration = viewModel.searchDurationDisplay {
                    Text("Search completed in \(duration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.yellow)
                    
                    VStack(alignment: .leading) {
                        Text("Best Spot Found!")
                            .font(.headline)
                        Text("\(bestSpot.fullLocationString) from \(centerLocation.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(bestSpot.score)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(bestSpot.score))
                }
                
                Button("Navigate to Best Spot") {
                    if let best = result.bestSpot {
                        viewModel.openInMaps(location: best, centerName: centerLocation.name)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
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
                        .foregroundStyle(.secondary)
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
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
    
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
        #if os(iOS)
        return Color(uiColor: .systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
}

// MARK: - Map View

struct BestSpotMapView: View {
    let centerLocation: SavedLocation
    let scoredLocations: [LocationScore]
    @Binding var selectedLocation: LocationScore?
    @Binding var position: MapCameraPosition
    
    var body: some View {
        Map(position: $position) {
            // Center annotation
            Annotation(centerLocation.name, coordinate: centerCoordinate) {
                Image(systemName: "location.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
            
            // Grid point annotations
            ForEach(scoredLocations) { location in
                Annotation("\(location.score)", coordinate: coordinate(for: location)) {
                    BestSpotMapAnnotation(
                        score: location.score,
                        rank: rank(of: location),
                        isSelected: selectedLocation?.id == location.id
                    )
                }
            }
        }
        .mapStyle(.standard)
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
    
    private func rank(of location: LocationScore) -> Int {
        scoredLocations.firstIndex { $0.id == location.id }.map { $0 + 1 } ?? 0
    }
}

struct BestSpotMapAnnotation: View {
    let score: Int
    let rank: Int
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.white, lineWidth: isSelected ? 3 : 2)
                )
            
            if rank <= 3 {
                Text("\(rank)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            } else {
                Text("\(score)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
        }
    }
    
    private var backgroundColor: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
}

// MARK: - Settings View

struct BestSpotSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BestSpotSettings.searchRadiusKey) private var searchRadius: Double = BestSpotSettings.defaultSearchRadius
    @AppStorage(BestSpotSettings.gridSpacingKey) private var gridSpacing: Double = BestSpotSettings.defaultGridSpacing
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Search Area") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Radius")
                            Spacer()
                            Text("\(Int(searchRadius)) miles")
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(
                            value: $searchRadius,
                            in: BestSpotSettings.minSearchRadius...BestSpotSettings.maxSearchRadius,
                            step: 5
                        )
                        
                        Text("Searches up to \(Int(searchRadius)) miles from your location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Grid Spacing")
                            Spacer()
                            Text("\(Int(gridSpacing)) miles")
                                .foregroundStyle(.secondary)
                        }
                        
                        Slider(
                            value: $gridSpacing,
                            in: BestSpotSettings.minGridSpacing...BestSpotSettings.maxGridSpacing,
                            step: 1
                        )
                        
                        Text("Checks a point every \(Int(gridSpacing)) miles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Estimated Search Points") {
                    let estimatedPoints = calculateEstimatedPoints()
                    HStack {
                        Text("Points to check")
                        Spacer()
                        Text("~\(estimatedPoints)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Fewer points = faster search, more points = better coverage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Search Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func calculateEstimatedPoints() -> Int {
        let numRings = Int(ceil(searchRadius / gridSpacing))
        var total = 1 // Center point
        
        for ring in 1...numRings {
            let ringRadius = Double(ring) * gridSpacing
            let circumference = 2 * .pi * ringRadius
            let numPoints = max(6, Int(round(circumference / gridSpacing)))
            total += numPoints
        }
        
        return total
    }
}
