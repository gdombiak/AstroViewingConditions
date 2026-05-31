import Foundation
import os

public enum UnitSystem: String, CaseIterable, Identifiable, Sendable {
    case metric = "Metric"
    case imperial = "Imperial"
    
    public var id: String { rawValue }
}

public struct AstroUnitConverter {
    private let unitSystem: UnitSystem
    
    public init(unitSystem: UnitSystem) {
        self.unitSystem = unitSystem
    }
    
    public func formatTemperature(_ celsius: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.1f°C", celsius)
        case .imperial:
            let fahrenheit = (celsius * 9/5) + 32
            return String(format: "%.1f°F", fahrenheit)
        }
    }
    
    public func formatWindSpeed(_ kmh: Double) -> String {
        switch unitSystem {
        case .metric:
            return String(format: "%.1f km/h", kmh)
        case .imperial:
            let mph = kmh * 0.621371
            return String(format: "%.1f mph", mph)
        }
    }
    
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

private let unitLogger = Logger(subsystem: "com.astroviewing.conditions", category: "UnitSystemStorage")

public struct UnitSystemStorage {
    public static func loadSelectedUnitSystem() -> UnitSystem {
        if let rawValue = AppGroupStorage.loadUnitSystem(),
           let system = UnitSystem(rawValue: rawValue) {
            return system
        }
        if let rawValue = iCloudKeyValueStorage.shared.loadUnitSystem(),
           let system = UnitSystem(rawValue: rawValue) {
            saveSelectedUnitSystem(system)
            return system
        }
        return .metric
    }
    
    public static func saveSelectedUnitSystem(_ system: UnitSystem) {
        AppGroupStorage.saveUnitSystem(system.rawValue)
        iCloudKeyValueStorage.shared.saveUnitSystem(system.rawValue)
    }
    
    public static func initializeIfNeeded() {
        if AppGroupStorage.loadUnitSystem() != nil { return }
        
        if let rawValue = iCloudKeyValueStorage.shared.loadUnitSystem(),
           let system = UnitSystem(rawValue: rawValue) {
            saveSelectedUnitSystem(system)
            return
        }
        
        let defaultSystem: UnitSystem = if #available(iOS 16, *) {
            Locale.current.measurementSystem == .metric ? .metric : .imperial
        } else {
            Locale.current.usesMetricSystem ? .metric : .imperial
        }
        
        unitLogger.info("Initializing unit system from locale: \(defaultSystem.rawValue)")
        saveSelectedUnitSystem(defaultSystem)
    }
}
