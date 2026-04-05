import Foundation

public struct WidgetLocationStore: Sendable {
    nonisolated(unsafe) private static let sharedDefaults = UserDefaults(suiteName: "group.com.astroviewing.conditions") ?? .standard

    private enum Keys {
        static let latitude = "widgetLocationLatitude"
        static let longitude = "widgetLocationLongitude"
        static let name = "widgetLocationName"
    }

    public static func save(_ location: CachedLocation) {
        sharedDefaults.set(location.latitude, forKey: Keys.latitude)
        sharedDefaults.set(location.longitude, forKey: Keys.longitude)
        sharedDefaults.set(location.name, forKey: Keys.name)
    }

    public static func load() -> (latitude: Double, longitude: Double, name: String)? {
        let lat = sharedDefaults.double(forKey: Keys.latitude)
        let lon = sharedDefaults.double(forKey: Keys.longitude)
        let name = sharedDefaults.string(forKey: Keys.name) ?? "Current Location"
        guard lat != 0, lon != 0 else { return nil }
        return (lat, lon, name)
    }
}
