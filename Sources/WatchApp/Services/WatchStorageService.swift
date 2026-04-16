import Foundation
import SharedCode

final class WatchStorageService: @unchecked Sendable {
    static let shared = WatchStorageService()
    
    private let defaults = UserDefaults.standard
    
    func saveLocations(_ locations: [CachedLocation]) {
        if let data = try? JSONEncoder().encode(locations) {
            defaults.set(data, forKey: "savedLocations")
        }
    }
    
    func loadLocations() -> [CachedLocation] {
        guard let data = defaults.data(forKey: "savedLocations"),
              let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) else {
            return []
        }
        return locations
    }
    
    func saveCurrentLocation(_ location: CachedLocation) {
        if let data = try? JSONEncoder().encode(location) {
            defaults.set(data, forKey: "currentLocation")
        }
    }
    
    func loadCurrentLocation() -> CachedLocation? {
        guard let data = defaults.data(forKey: "currentLocation"),
              let location = try? JSONDecoder().decode(CachedLocation.self, from: data) else {
            return nil
        }
        return location
    }
    
    func saveConditions(_ conditions: ViewingConditions) {
        if let data = try? JSONEncoder().encode(conditions) {
            defaults.set(data, forKey: "conditions")
            defaults.set(Date(), forKey: "conditionsTimestamp")
        }
    }
    
    func loadConditions() -> ViewingConditions? {
        guard let data = defaults.data(forKey: "conditions"),
              let conditions = try? JSONDecoder().decode(ViewingConditions.self, from: data) else {
            return nil
        }
        return conditions
    }
    
    func loadConditionsTimestamp() -> Date? {
        return defaults.object(forKey: "conditionsTimestamp") as? Date
    }
    
    func saveSelectedLocation(_ location: CachedLocation) {
        if let data = try? JSONEncoder().encode(location) {
            defaults.set(data, forKey: "selectedLocation")
        }
    }
    
    func loadSelectedLocation() -> CachedLocation? {
        guard let data = defaults.data(forKey: "selectedLocation"),
              let location = try? JSONDecoder().decode(CachedLocation.self, from: data) else {
            return nil
        }
        return location
    }
}