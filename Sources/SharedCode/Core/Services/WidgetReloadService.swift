import Foundation
import WidgetKit
import SwiftUI

public final class WidgetReloadService: @unchecked Sendable {
    public static let shared = WidgetReloadService()
    
    private var workItem: DispatchWorkItem?
    private let debounceDelay: UInt64 = 1_000_000_000
    private let reloadQueue = DispatchQueue(label: "com.astroviewing.widget.reload", qos: .utility)
    
    private init() {}
    
    public func scheduleReload() {
        workItem?.cancel()
        
        let newWorkItem = DispatchWorkItem { [weak self] in
            self?.performReload()
        }
        
        workItem = newWorkItem
        reloadQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(debounceDelay)), execute: newWorkItem)
    }
    
    private func performReload() {
//        WidgetCenter.shared.reloadAllTimelines()
        
        WidgetCenter.shared.reloadTimelines(ofKind: "NightConditionsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "NightConditionsWatchWidget")
    }
}
