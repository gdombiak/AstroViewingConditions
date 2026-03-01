import Foundation
import SwiftUI

/// AppStorage keys and defaults for Best Spot feature
public enum BestSpotSettings {
    // MARK: - Keys
    public static let searchRadiusKey = "bestSpotSearchRadius"
    public static let gridSpacingKey = "bestSpotGridSpacing"
    
    // MARK: - Defaults
    public static let defaultSearchRadius: Double = 30  // miles
    public static let defaultGridSpacing: Double = 5    // miles
    public static let minSearchRadius: Double = 10      // miles
    public static let maxSearchRadius: Double = 50      // miles
    public static let minGridSpacing: Double = 3        // miles
    public static let maxGridSpacing: Double = 10       // miles
    
    // MARK: - Validation
    public static func validateSearchRadius(_ radius: Double) -> Double {
        min(max(radius, minSearchRadius), maxSearchRadius)
    }
    
    public static func validateGridSpacing(_ spacing: Double) -> Double {
        min(max(spacing, minGridSpacing), maxGridSpacing)
    }
}

// MARK: - AppStorage Extensions

extension UserDefaults {
    var bestSpotSearchRadius: Double {
        get {
            let value = double(forKey: BestSpotSettings.searchRadiusKey)
            return value > 0 ? BestSpotSettings.validateSearchRadius(value) : BestSpotSettings.defaultSearchRadius
        }
        set {
            set(BestSpotSettings.validateSearchRadius(newValue), forKey: BestSpotSettings.searchRadiusKey)
        }
    }
    
    var bestSpotGridSpacing: Double {
        get {
            let value = double(forKey: BestSpotSettings.gridSpacingKey)
            return value > 0 ? BestSpotSettings.validateGridSpacing(value) : BestSpotSettings.defaultGridSpacing
        }
        set {
            set(BestSpotSettings.validateGridSpacing(newValue), forKey: BestSpotSettings.gridSpacingKey)
        }
    }
}
