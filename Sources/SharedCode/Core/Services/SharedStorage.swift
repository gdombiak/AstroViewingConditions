import Foundation
import os

private let logger = Logger(subsystem: "com.astroviewing.conditions", category: "SharedStorage")

extension Notification.Name {
    public static let watchLocationSelected = Notification.Name("watchLocationSelected")
}

public struct SharedStorage: Sendable {
    private static let suiteName = "group.com.astroviewing.conditions"
    
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }
    
    public static func saveWidgetLocation(_ location: CachedLocation) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        let data: [String: Any] = [
            "latitude": location.latitude,
            "longitude": location.longitude,
            "name": location.name
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let fileURL = baseURL.appendingPathComponent("widgetLocation.json")
            try jsonData.write(to: fileURL)
        } catch {
            logger.error("Failed to save widget location: \(error.localizedDescription)")
        }
    }

    public static func loadWidgetLocation() -> (latitude: Double, longitude: Double, name: String)? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("widgetLocation.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let lat = json?["latitude"] as? Double,
                  let lon = json?["longitude"] as? Double,
                  let name = json?["name"] as? String else {
                logger.warning("Widget location data is incomplete")
                return nil
            }
            return (lat, lon, name)
        } catch {
            logger.warning("Failed to load widget location: \(error.localizedDescription)")
            return nil
        }
    }

    public static func saveWidgetConditions(_ conditions: ViewingConditions) {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(conditions)
            let fileURL = baseURL.appendingPathComponent("widgetConditions.json")
            try data.write(to: fileURL)
        } catch {
            logger.error("Failed to save widget conditions: \(error.localizedDescription)")
        }
    }

    public static func loadWidgetConditions() -> ViewingConditions? {
        guard let baseURL = containerURL else {
            logger.error("App Group container not available")
            return nil
        }
        
        let fileURL = baseURL.appendingPathComponent("widgetConditions.json")
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(ViewingConditions.self, from: data)
        } catch {
            logger.warning("Failed to load widget conditions: \(error.localizedDescription)")
            return nil
        }
    }
}