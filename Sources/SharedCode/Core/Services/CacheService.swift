import Foundation

public final class CacheService: Sendable {
    private let locationTolerance = 0.0001
    
    public init() {}
    
    public func save(_ conditions: ViewingConditions) {
        AppGroupStorage.saveConditions(conditions)
    }

    public func saveAsync(_ conditions: ViewingConditions) async {
        await AppGroupStorage.saveConditionsAsync(conditions)
    }
    
    public func load() -> ViewingConditions? {
        AppGroupStorage.loadConditions()
    }

    public func loadAsync() async -> ViewingConditions? {
        await AppGroupStorage.loadConditionsAsync()
    }
    
    public func cachedLocationMatches(_ location: CachedLocation) -> Bool {
        guard let conditions = load() else { return false }
        return cachedLocationMatches(location, conditions: conditions)
    }

    public func cachedLocationMatchesAsync(_ location: CachedLocation) async -> Bool {
        guard let conditions = await loadAsync() else { return false }
        return cachedLocationMatches(location, conditions: conditions)
    }

    private func cachedLocationMatches(_ location: CachedLocation, conditions: ViewingConditions) -> Bool {
        let cachedLat = conditions.location.latitude
        let cachedLon = conditions.location.longitude
        
        guard cachedLat != 0, cachedLon != 0 else { return false }
        
        return abs(cachedLat - location.latitude) < locationTolerance &&
               abs(cachedLon - location.longitude) < locationTolerance
    }
    
    public func clear() {
        AppGroupStorage.clearConditions()
    }
}
