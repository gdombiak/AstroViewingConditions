import Foundation
import WidgetKit
import SwiftUI

@MainActor
public final class WidgetReloadService {
    public static let shared = WidgetReloadService()
    
    private var reloadTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 1_000_000_000
    
    private init() {}
    
    public func scheduleReload() {
        reloadTask?.cancel()
        
        reloadTask = Task { [debounceDelay] in
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
            } catch {
                return
            }
            
            WidgetCenter.shared.reloadTimelines(ofKind: "NightConditionsWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "NightConditionsWatchWidget")
        }
    }
}
