import Foundation

public final class CacheService: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let locationTolerance = 0.0001
    
    private enum StorageKeys {
        static let cachedConditions = "cachedViewingConditions"
        static let cachedLocationLat = "cachedLocationLatitude"
        static let cachedLocationLon = "cachedLocationLongitude"
    }
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func save(_ conditions: ViewingConditions) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(conditions)
            userDefaults.set(data, forKey: StorageKeys.cachedConditions)
            userDefaults.set(conditions.location.latitude, forKey: StorageKeys.cachedLocationLat)
            userDefaults.set(conditions.location.longitude, forKey: StorageKeys.cachedLocationLon)
        } catch {
            print("Failed to cache conditions: \(error)")
        }
    }
    
    public func load() -> ViewingConditions? {
        guard let data = userDefaults.data(forKey: StorageKeys.cachedConditions) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(ViewingConditions.self, from: data)
        } catch {
            return nil
        }
    }
    
#if os(iOS)
    public func cachedLocationMatches(_ location: SavedLocation) -> Bool {
        let cachedLat = userDefaults.double(forKey: StorageKeys.cachedLocationLat)
        let cachedLon = userDefaults.double(forKey: StorageKeys.cachedLocationLon)
        
        guard cachedLat != 0, cachedLon != 0 else { return false }
        
        return abs(cachedLat - location.latitude) < locationTolerance && 
               abs(cachedLon - location.longitude) < locationTolerance
    }
#endif

    public func cachedLocationMatches(_ location: CachedLocation) -> Bool {
        let cachedLat = userDefaults.double(forKey: StorageKeys.cachedLocationLat)
        let cachedLon = userDefaults.double(forKey: StorageKeys.cachedLocationLon)
        
        guard cachedLat != 0, cachedLon != 0 else { return false }
        
        return abs(cachedLat - location.latitude) < locationTolerance &&
               abs(cachedLon - location.longitude) < locationTolerance
    }
    
    public func clear() {
        userDefaults.removeObject(forKey: StorageKeys.cachedConditions)
        userDefaults.removeObject(forKey: StorageKeys.cachedLocationLat)
        userDefaults.removeObject(forKey: StorageKeys.cachedLocationLon)
    }
}
