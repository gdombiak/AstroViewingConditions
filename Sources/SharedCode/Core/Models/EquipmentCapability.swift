import Foundation

/// Identifies the built-in capability or a saved inventory item.
public enum EquipmentCapabilityID: Hashable, Codable, Sendable {
    case nakedEye
    case savedEquipment(UUID)
}

/// Immutable, SwiftData-free equipment information used by session matching.
public struct EquipmentCapability: Identifiable, Hashable, Sendable {
    public let id: EquipmentCapabilityID
    public let displayName: String
    public let type: EquipmentType?
    public let magnification: Double?
    public let apertureMillimeters: Double?

    public static let nakedEye = EquipmentCapability(
        id: .nakedEye,
        displayName: "Naked Eye",
        type: nil,
        magnification: nil,
        apertureMillimeters: nil
    )

    public init(
        id: EquipmentCapabilityID,
        displayName: String,
        type: EquipmentType?,
        magnification: Double?,
        apertureMillimeters: Double?
    ) {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.magnification = magnification
        self.apertureMillimeters = apertureMillimeters
    }
}

#if os(iOS)
public extension EquipmentItem {
    var matchingCapability: EquipmentCapability? {
        guard persistedValidation.isAvailable, let type else { return nil }
        return EquipmentCapability(
            id: .savedEquipment(id),
            displayName: inventoryDisplayName,
            type: type,
            magnification: magnification,
            apertureMillimeters: apertureMillimeters
        )
    }
}
#endif
