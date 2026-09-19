import Foundation
import AstroEngine

/// Host adapter: authoritative rules and data are shared by AstroEngine.
public enum TargetEquipmentRequirements {
    public static func requirement(for target: ObservableTarget) -> TargetEquipmentRequirement {
        TargetMetadata.requirement(id: target.id,
            type: FrozenTargetType(rawValue: target.type.rawValue)!,
            objectType: target.deepSkyObjectType)
    }
}

public extension ObservableTarget {
    var equipmentRequirement: TargetEquipmentRequirement {
        TargetEquipmentRequirements.requirement(for: self)
    }
}
