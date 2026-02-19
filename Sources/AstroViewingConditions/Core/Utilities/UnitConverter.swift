import Foundation

public enum UnitSystem: String, CaseIterable, Identifiable {
    case metric = "Metric"
    case imperial = "Imperial"
    
    public var id: String { rawValue }
}

public struct UnitConverter {
    private let unitSystem: UnitSystem
    
    public init(unitSystem: UnitSystem) {
        self.unitSystem = unitSystem
    }
    
    // MARK: - Temperature
    
    public func formatTemperature(_ celsius: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.1f°C", celsius)
        case .imperial:
            let fahrenheit = (celsius * 9/5) + 32
            return String(format: "%.1f°F", fahrenheit)
        }
    }
    
    // MARK: - Wind Speed
    
    public func formatWindSpeed(_ kmh: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.1f km/h", kmh)
        case .imperial:
            let mph = kmh * 0.621371
            return String(format: "%.1f mph", mph)
        }
    }
    
    // MARK: - Visibility
    
    public func formatVisibility(_ meters: Double?) -> String {
        guard let meters = meters else { return "N/A" }
        
        switch unitSystem {
        case .metric:
            if meters >= 1000 {
                return String(format: "%.1f km", meters / 1000)
            } else {
                return String(format: "%.0f m", meters)
            }
        case .imperial:
            let miles = meters * 0.000621371
            if miles >= 1 {
                return String(format: "%.1f mi", miles)
            } else {
                let feet = meters * 3.28084
                return String(format: "%.0f ft", feet)
            }
        }
    }
    
    /// Short format for hourly forecast tables - uses compact notation like "10k" or "6m"
    public func formatShortVisibility(_ meters: Double?) -> String {
        guard let meters = meters else { return "—" }
        
        switch unitSystem {
        case .metric:
            if meters >= 1000 {
                return String(format: "%.0fk", meters / 1000)
            } else {
                return String(format: "%.0fm", meters)
            }
        case .imperial:
            let miles = meters * 0.000621371
            if miles >= 1 {
                return String(format: "%.0fmi", miles)
            } else {
                let feet = meters * 3.28084
                return String(format: "%.0fft", feet)
            }
        }
    }
    
    // MARK: - Distance
    
    public func formatDistance(_ kilometers: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.1f km", kilometers)
        case .imperial:
            let miles = kilometers * 0.621371
            return String(format: "%.1f mi", miles)
        }
    }
}

// MARK: - User Defaults

private let unitSystemKey = "selectedUnitSystem"

public extension UserDefaults {
    var selectedUnitSystem: UnitSystem {
        get {
            guard let rawValue = string(forKey: unitSystemKey),
                  let system = UnitSystem(rawValue: rawValue) else {
                return .metric
            }
            return system
        }
        set {
            set(newValue.rawValue, forKey: unitSystemKey)
        }
    }
}
