import Foundation

public final class CacheService: @unchecked Sendable {
    private let locationTolerance = 0.0001
    
    public init() {}
    
    public func save(_ conditions: ViewingConditions) {
        AppGroupStorage.saveConditions(conditions)
    }
    
    public func load() -> ViewingConditions? {
        AppGroupStorage.loadConditions()
    }
    
    public func cachedLocationMatches(_ location: CachedLocation) -> Bool {
        guard let conditions = load() else { return false }
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