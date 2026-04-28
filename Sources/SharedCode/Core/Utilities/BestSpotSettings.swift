import Foundation
import SwiftUI

public enum BestSpotSettings {
    public static let searchRadiusKey = "bestSpotSearchRadius"
    public static let gridSpacingKey = "bestSpotGridSpacing"
    
    public static let defaultSearchRadius: Double = 30
    public static let defaultGridSpacing: Double = 5
    public static let minSearchRadius: Double = 10
    public static let maxSearchRadius: Double = 50
    public static let minGridSpacing: Double = 3
    public static let maxGridSpacing: Double = 10
    
    public static func validateSearchRadius(_ radius: Double) -> Double {
        min(max(radius, minSearchRadius), maxSearchRadius)
    }
    
    public static func validateGridSpacing(_ spacing: Double) -> Double {
        min(max(spacing, minGridSpacing), maxGridSpacing)
    }
    
    public static var searchRadius: Double {
        get {
            AppGroupStorage.loadBestSpotSettings()?.searchRadius ?? defaultSearchRadius
        }
        set {
            AppGroupStorage.saveBestSpotSettings(
                searchRadius: validateSearchRadius(newValue),
                gridSpacing: gridSpacing
            )
        }
    }
    
    public static var gridSpacing: Double {
        get {
            AppGroupStorage.loadBestSpotSettings()?.gridSpacing ?? defaultGridSpacing
        }
        set {
            AppGroupStorage.saveBestSpotSettings(
                searchRadius: searchRadius,
                gridSpacing: validateGridSpacing(newValue)
            )
        }
    }
}