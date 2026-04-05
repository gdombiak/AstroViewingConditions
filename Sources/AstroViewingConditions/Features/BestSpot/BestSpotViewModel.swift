import SharedCode
import SwiftUI
import MapKit
import CoreLocation

@MainActor
@Observable
public class BestSpotViewModel {
    // Services
    private let searcher: BestSpotSearcher
    
    // State
    public var result: BestSpotResult?
    public var isSearching = false
    public var error: (any Error)?
    public var searchProgress: Double = 0
    
    // Settings
    private let userDefaults = UserDefaults.standard
    
    public var searchRadius: Double {
        userDefaults.bestSpotSearchRadius
    }
    
    public var gridSpacing: Double {
        userDefaults.bestSpotGridSpacing
    }
    
    public init(fogScoreCalculator: @escaping (HourlyForecast) -> FogScore = FogCalculator.calculate) {
        self.searcher = BestSpotSearcher(fogScoreCalculator: fogScoreCalculator)
    }
    
    /// Starts a search for the best viewing conditions
    public func search(
        around center: SavedLocation,
        for date: Date,
        topN: Int = 5
    ) async {
        isSearching = true
        error = nil
        searchProgress = 0
        result = nil
        
        do {
            let searchResult = try await searcher.findBestSpots(
                around: center,
                radiusMiles: searchRadius,
                spacingMiles: gridSpacing,
                for: date,
                topN: topN
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.searchProgress = progress
                }
            }
            
            self.result = searchResult
            
        } catch {
            self.error = error
        }
        
        isSearching = false
    }
    
    /// Cancels the current search
    public func cancelSearch() {
        // In a real implementation, we might want to add cancellation support
        // to BestSpotSearcher. For now, we'll just reset the state.
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
