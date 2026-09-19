import Foundation
import AstroEngine

#if os(iOS)
import SwiftData

@Model
public final class EquipmentItem {
    @Attribute(.unique) public var id: UUID
    public var name: String
    private var equipmentTypeRawValue: String
    public var magnification: Double?
    public var apertureMillimeters: Double
    private var apertureUnitRawValue: String = EquipmentApertureUnit.millimeters.rawValue

    public var type: EquipmentType? {
        get { EquipmentType(rawValue: equipmentTypeRawValue) }
        set {
            if let newValue {
                equipmentTypeRawValue = newValue.rawValue
            }
        }
    }

    public var apertureUnit: EquipmentApertureUnit? {
        get { EquipmentApertureUnit(rawValue: apertureUnitRawValue) }
        set {
            if let newValue {
                apertureUnitRawValue = newValue.rawValue
            }
        }
    }

    public init(draft: EquipmentDraft) {
        self.id = UUID()
        self.name = draft.name
        self.equipmentTypeRawValue = draft.type.rawValue
        self.magnification = draft.magnification
        self.apertureMillimeters = draft.apertureMillimeters
        self.apertureUnitRawValue = draft.apertureUnit.rawValue
    }

    public func apply(_ draft: EquipmentDraft) {
        name = draft.name
        type = draft.type
        magnification = draft.magnification
        apertureMillimeters = draft.apertureMillimeters
        apertureUnit = draft.apertureUnit
    }

    init(
        id: UUID = UUID(),
        name: String,
        equipmentTypeRawValue: String,
        magnification: Double?,
        apertureMillimeters: Double,
        apertureUnitRawValue: String
    ) {
        self.id = id
        self.name = name
        self.equipmentTypeRawValue = equipmentTypeRawValue
        self.magnification = magnification
        self.apertureMillimeters = apertureMillimeters
        self.apertureUnitRawValue = apertureUnitRawValue
    }
}

public extension EquipmentItem {
    var persistedSnapshot: EquipmentPersistedSnapshot {
        EquipmentPersistedSnapshot(
            name: name,
            equipmentTypeRawValue: equipmentTypeRawValue,
            magnification: magnification,
            apertureMillimeters: apertureMillimeters,
            apertureUnitRawValue: apertureUnitRawValue
        )
    }

    func restore(_ snapshot: EquipmentPersistedSnapshot) {
        name = snapshot.name
        equipmentTypeRawValue = snapshot.equipmentTypeRawValue
        magnification = snapshot.magnification
        apertureMillimeters = snapshot.apertureMillimeters
        apertureUnitRawValue = snapshot.apertureUnitRawValue
    }

    var persistedValidation: EquipmentPersistedValidation {
        var issues: [EquipmentPersistedIssue] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            issues.append(.blankName)
        }

        guard let type else {
            issues.append(.unknownType)
            if apertureUnit == nil { issues.append(.unknownApertureUnit) }
            if !apertureMillimeters.isFinite || apertureMillimeters <= 0 {
                issues.append(.invalidAperture)
            }
            return EquipmentPersistedValidation(issues: issues)
        }

        if apertureUnit == nil {
            issues.append(.unknownApertureUnit)
        }
        if !apertureMillimeters.isFinite || apertureMillimeters <= 0 {
            issues.append(.invalidAperture)
        } else if apertureMillimeters > EquipmentValidation.maximumApertureMillimeters(for: type) {
            issues.append(.apertureTooLarge)
        }

        if type == .binoculars {
            switch magnification {
            case nil:
                issues.append(.missingMagnification)
            case let value? where !value.isFinite || value <= 0:
                issues.append(.invalidMagnification)
            case let value? where value > EquipmentValidation.maximumBinocularMagnification:
                issues.append(.magnificationTooHigh)
            default:
                break
            }
        }
        return EquipmentPersistedValidation(issues: issues)
    }

    var inventoryDisplayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed Equipment" : trimmed
    }

    var detailText: String {
        guard persistedValidation.isAvailable, let type else { return "Unavailable — repair or delete" }
        switch type {
        case .binoculars:
            let magnificationText = magnification.map { "\(EquipmentFormatting.number($0))×" } ?? ""
            let apertureText = EquipmentFormatting.millimeters(apertureMillimeters)
            return "\(magnificationText)\(apertureText)"
        case .visualTelescope:
            return "\(EquipmentFormatting.millimeters(apertureMillimeters)) aperture"
        case .smartTelescope:
            return "\(EquipmentFormatting.millimeters(apertureMillimeters)) aperture"
        }
    }
}

private extension EquipmentFormatting {
    static func number(_ value: Double) -> String {
        guard value.isFinite,
              value > 0,
              abs(value) <= Double(Int.max) / 10 else {
            return "Unavailable"
        }
        let roundedToTenth = (value * 10).rounded() / 10
        if roundedToTenth.rounded() == roundedToTenth {
            return "\(Int(roundedToTenth))"
        }
        return "\(roundedToTenth)"
    }
}

public enum EquipmentPersistedIssue: Sendable, Hashable {
    case blankName
    case unknownType
    case unknownApertureUnit
    case missingMagnification
    case invalidMagnification
    case magnificationTooHigh
    case invalidAperture
    case apertureTooLarge
}

public struct EquipmentPersistedSnapshot: Sendable, Hashable {
    let name: String
    let equipmentTypeRawValue: String
    let magnification: Double?
    let apertureMillimeters: Double
    let apertureUnitRawValue: String
}

public struct EquipmentPersistedValidation: Sendable, Hashable {
    public let issues: [EquipmentPersistedIssue]

    public var isAvailable: Bool { issues.isEmpty }

    public init(issues: [EquipmentPersistedIssue]) {
        self.issues = issues
    }
}

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
