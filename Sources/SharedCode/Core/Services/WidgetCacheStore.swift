import Foundation

public struct WidgetCacheStore: Sendable {
    nonisolated(unsafe) private static let sharedDefaults = UserDefaults(suiteName: "group.com.astroviewing.conditions") ?? .standard
    private static let cacheKey = "widgetCachedViewingConditions"

    public static func save(_ conditions: ViewingConditions) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(conditions)
            sharedDefaults.set(data, forKey: cacheKey)
        } catch {
            print("WidgetCacheStore: Failed to save conditions: \(error)")
        }
    }

    public static func load() -> ViewingConditions? {
        guard let data = sharedDefaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(ViewingConditions.self, from: data)
    }
}
