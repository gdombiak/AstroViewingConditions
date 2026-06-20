import SharedCode
import SwiftUI
import MapKit
import CoreLocation

@MainActor
@Observable
public class BestSpotViewModel {
    // Services
    private let searcher: BestSpotSearcher
    private var searchTask: Task<Void, Never>?
    private var activeSearchID: UUID?
    
    // State
    public var result: BestSpotResult?
    public var isSearching = false
    public var error: (any Error)?
    public var searchProgress: Double = 0
    
    // Settings
    
    public var searchRadius: Double {
        BestSpotSettings.searchRadius
    }
    
    public var gridSpacing: Double {
        BestSpotSettings.gridSpacing
    }
    
    public init(fogScoreCalculator: @escaping @Sendable (HourlyForecast) -> FogScore = FogCalculator.calculate) {
        self.searcher = BestSpotSearcher(fogScoreCalculator: fogScoreCalculator)
    }

    public func startSearch(
        around center: SavedLocation,
        for date: Date,
        topN: Int = 5
    ) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.search(around: center, for: date, topN: topN)
        }
    }
    
    /// Starts a search for the best viewing conditions
    public func search(
        around center: SavedLocation,
        for date: Date,
        topN: Int = 5
    ) async {
        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        error = nil
        searchProgress = 0
        result = nil
        let cachedCenter = CachedLocation(from: center)
        
        do {
            let searchResult = try await searcher.findBestSpots(
                around: cachedCenter,
                radiusMiles: searchRadius,
                spacingMiles: gridSpacing,
                for: date,
                topN: topN
            ) { [weak self] progress in
                Task { @MainActor in
                    guard self?.activeSearchID == searchID,
                          self?.isSearching == true else { return }
                    self?.searchProgress = progress
                }
            }
            
            try Task.checkCancellation()
            guard activeSearchID == searchID else { return }
            self.result = searchResult
            
        } catch is CancellationError {
            if activeSearchID == searchID {
                result = nil
                error = nil
            }
        } catch {
            if !Task.isCancelled, activeSearchID == searchID {
                self.error = error
            }
        }
        
        if activeSearchID == searchID {
            isSearching = false
            activeSearchID = nil
            searchTask = nil
        }
    }
    
    /// Cancels the current search
    public func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeSearchID = nil
        result = nil
        error = nil
        isSearching = false
        searchProgress = 0
    }
    
    /// Opens a location in Apple Maps for navigation
    public func openInMaps(location: LocationScore, centerName: String) {
        let coordinate = location.point.coordinate
        let placemark = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: placemark.coordinate))
        mapItem.name = "Best Spot (\(location.score)/100) - \(location.fullLocationString) from \(centerName)"
        
        let launchOptions = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        mapItem.openInMaps(launchOptions: launchOptions)
    }
    
    /// Formats the search radius for display
    public var searchRadiusDisplay: String {
        String(format: "%.0f miles", searchRadius)
    }
    
    /// Formats the search duration
    public var searchDurationDisplay: String? {
        guard let duration = result?.searchDuration else { return nil }
        if duration < 1 {
            return String(format: "%.1fs", duration)
        } else {
            return String(format: "%.0f sec", duration)
        }
    }
}
