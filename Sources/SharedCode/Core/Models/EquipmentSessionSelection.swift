import Foundation

public enum EquipmentSessionSelectionMode: Equatable, Sendable {
    case allEquipment
    case custom
}

public enum EquipmentFitThreshold: String, CaseIterable, Equatable, Sendable {
    case any
    case challengingOrBetter
    case goodOrBetter
    case excellentOnly

    public static let presentationOrder: [EquipmentFitThreshold] = [
        .excellentOnly,
        .goodOrBetter,
        .challengingOrBetter,
        .any
    ]

    public var displayName: String {
        switch self {
        case .any: return "Any"
        case .challengingOrBetter: return "Challenging"
        case .goodOrBetter: return "Good"
        case .excellentOnly: return "Excellent"
        }
    }

    public var dashboardSummary: String {
        switch self {
        case .any: return "Show targets: Any suitability"
        case .challengingOrBetter: return "Show targets: Challenging or better"
        case .goodOrBetter: return "Show targets: Good or better"
        case .excellentOnly: return "Show targets: Excellent only"
        }
    }

    public var dashboardAccessibilitySummary: String {
        switch self {
        case .any: return "Show targets with any equipment suitability."
        case .challengingOrBetter: return "Show targets with Challenging suitability or better."
        case .goodOrBetter: return "Show targets with Good suitability or better."
        case .excellentOnly: return "Show targets with Excellent suitability only."
        }
    }

    public func includes(_ level: EquipmentFitLevel) -> Bool {
        switch self {
        case .any: return true
        case .challengingOrBetter: return level != .poor
        case .goodOrBetter: return level == .excellent || level == .good
        case .excellentOnly: return level == .excellent
        }
    }
}

/// Lightweight, non-persistent session selection. All-equipment mode includes
/// newly added inventory; custom mode only contains explicitly chosen IDs.
public struct EquipmentSessionSelection: Equatable, Sendable {
    public private(set) var mode: EquipmentSessionSelectionMode
    private var customSelectedIDs: Set<EquipmentCapabilityID>

    public init() {
        mode = .allEquipment
        customSelectedIDs = []
    }

    public mutating func selectAllEquipment() {
        mode = .allEquipment
        customSelectedIDs = []
    }

    public mutating func selectNakedEyeOnly() {
        mode = .custom
        customSelectedIDs = [.nakedEye]
    }

    public func isSelected(_ id: EquipmentCapabilityID, inventory: [EquipmentCapability]) -> Bool {
        switch mode {
        case .allEquipment: return true
        case .custom: return customSelectedIDs.contains(id)
        }
    }

    public mutating func setSelected(
        _ isSelected: Bool,
        for id: EquipmentCapabilityID,
        inventory: [EquipmentCapability]
    ) {
        guard self.isSelected(id, inventory: inventory) != isSelected else { return }

        if mode == .allEquipment {
            mode = .custom
            customSelectedIDs = availableCapabilityIDs(from: inventory)
        }

        if isSelected {
            customSelectedIDs.insert(id)
        } else {
            customSelectedIDs.remove(id)
        }
        ensureAtLeastOneSelection()
    }

    public mutating func toggle(_ id: EquipmentCapabilityID, inventory: [EquipmentCapability]) {
        setSelected(
            !isSelected(id, inventory: inventory),
            for: id,
            inventory: inventory
        )
    }

    public mutating func reconcile(with inventory: [EquipmentCapability]) {
        guard mode == .custom else { return }
        customSelectedIDs.formIntersection(availableCapabilityIDs(from: inventory))
        ensureAtLeastOneSelection()
    }

    /// Resets a session's fit threshold only when its saved inventory becomes
    /// empty. Other inventory changes leave the user's current threshold alone.
    public static func minimumFitAfterInventoryTransition(
        currentMinimumFit: EquipmentFitThreshold,
        previousInventoryIDs: [EquipmentCapabilityID],
        currentInventoryIDs: [EquipmentCapabilityID]
    ) -> EquipmentFitThreshold {
        guard !previousInventoryIDs.isEmpty, currentInventoryIDs.isEmpty else {
            return currentMinimumFit
        }
        return .any
    }

    public func selectedCapabilities(from inventory: [EquipmentCapability]) -> [EquipmentCapability] {
        let allCapabilities = availableCapabilities(from: inventory)
        switch mode {
        case .allEquipment: return allCapabilities
        case .custom: return allCapabilities.filter { customSelectedIDs.contains($0.id) }
        }
    }

    /// Equipment guidance is available only when the user has saved inventory;
    /// otherwise callers retain their existing generic target guidance.
    public func equipmentFit(
        for target: ObservableTarget,
        inventory: [EquipmentCapability]
    ) -> EquipmentFitResult? {
        guard !inventory.isEmpty else { return nil }
        return EquipmentMatchingService().match(
            target: target,
            using: selectedCapabilities(from: inventory)
        )
    }

    /// Filters the conditions-ranked list without changing scores or relative
    /// order. Filtering is bypassed when no saved inventory exists.
    public func filteredRecommendations(
        _ recommendations: [TargetRecommendation],
        inventory: [EquipmentCapability],
        minimumFit: EquipmentFitThreshold
    ) -> [TargetRecommendation] {
        guard !inventory.isEmpty, minimumFit != .any else { return recommendations }
        return recommendations.filter { recommendation in
            guard let fit = equipmentFit(for: recommendation.target, inventory: inventory) else {
                return false
            }
            return minimumFit.includes(fit.level)
        }
    }

    private mutating func ensureAtLeastOneSelection() {
        if customSelectedIDs.isEmpty {
            customSelectedIDs = [.nakedEye]
        }
    }

    private func availableCapabilities(from inventory: [EquipmentCapability]) -> [EquipmentCapability] {
        [.nakedEye] + inventory
    }

    private func availableCapabilityIDs(from inventory: [EquipmentCapability]) -> Set<EquipmentCapabilityID> {
        Set(availableCapabilities(from: inventory).map(\.id))
    }
}
