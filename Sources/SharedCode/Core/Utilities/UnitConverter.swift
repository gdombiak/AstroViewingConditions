import Foundation
import os

public enum UnitSystem: String, CaseIterable, Identifiable {
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

private let appGroupSuiteName = "group.com.astroviewing.conditions"

private var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)
}

private let unitLogger = Logger(subsystem: "com.astroviewing.conditions", category: "UnitSystemStorage")

public struct UnitSystemStorage {
    public static func loadSelectedUnitSystem() -> UnitSystem {
        if let system = loadFromAppGroup() { return system }
        if let rawValue = iCloudKeyValueStorage.shared.loadUnitSystem(),
           let system = UnitSystem(rawValue: rawValue) {
            saveSelectedUnitSystem(system)
            return system
        }
        return .metric
    }
    
    private static func loadFromAppGroup() -> UnitSystem? {
        guard let baseURL = containerURL else { return nil }
        let fileURL = baseURL.appendingPathComponent("unitSystem.json")
        let data = try? Data(contentsOf: fileURL)
        guard let data, let rawValue = try? JSONDecoder().decode(String.self, from: data),
              let system = UnitSystem(rawValue: rawValue) else { return nil }
        return system
    }
    
    public static func saveSelectedUnitSystem(_ system: UnitSystem) {
        guard let baseURL = containerURL else {
            unitLogger.error("App Group container not available")
            return
        }
        
        let fileURL = baseURL.appendingPathComponent("unitSystem.json")
        
        do {
            let data = try JSONEncoder().encode(system.rawValue)
            try data.write(to: fileURL)
            iCloudKeyValueStorage.shared.saveUnitSystem(system.rawValue)
        } catch {
            unitLogger.error("Failed to save unit system: \(error.localizedDescription)")
        }
    }
    
    public static func initializeIfNeeded() {
        guard let baseURL = containerURL else {
            unitLogger.error("App Group container not available")
            return
        }
        
        let fileURL = baseURL.appendingPathComponent("unitSystem.json")
        
        if FileManager.default.fileExists(atPath: fileURL.path) { return }
        
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
