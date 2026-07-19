import Foundation

/// The observing capability of an item in a user's equipment inventory.
/// This is intentionally separate from the catalog's broad target-equipment
/// guidance so future matching can use the user's actual instrument details.
public enum EquipmentType: String, CaseIterable, Codable, Sendable, Hashable {
    case binoculars
    case visualTelescope
    case smartTelescope

    public var displayName: String {
        switch self {
        case .binoculars: return "Binoculars"
        case .visualTelescope: return "Visual Telescope"
        case .smartTelescope: return "Smart / EAA Telescope"
        }
    }
}

public enum EquipmentApertureUnit: String, CaseIterable, Codable, Sendable, Hashable {
    case millimeters
    case inches

    public var displayName: String {
        switch self {
        case .millimeters: return "mm"
        case .inches: return "inches"
        }
    }
}

public struct EquipmentDraft: Equatable, Sendable {
    public let name: String
    public let type: EquipmentType
    public let magnification: Double?
    public let apertureMillimeters: Double?
    public let apertureUnit: EquipmentApertureUnit

    public init(
        name: String,
        type: EquipmentType,
        magnification: Double?,
        aperture: Double?,
        apertureUnit: EquipmentApertureUnit
    ) throws {
        self = try EquipmentValidation.validate(
            name: name,
            type: type,
            magnification: magnification,
            aperture: aperture,
            apertureUnit: apertureUnit
        )
    }
}

public enum EquipmentValidationError: Error, Equatable, Sendable {
    case blankName
    case missingMagnification
    case invalidMagnification
    case missingAperture
    case invalidAperture

    public var message: String {
        switch self {
        case .blankName:
            return "Enter a name for this equipment."
        case .missingMagnification:
            return "Enter the binocular magnification."
        case .invalidMagnification:
            return "Magnification must be a positive, finite number."
        case .missingAperture:
            return "Enter the aperture."
        case .invalidAperture:
            return "Aperture must be a positive, finite number."
        }
    }
}

public enum EquipmentValidation {
    public static let millimetersPerInch = 25.4

    public static func validate(
        name: String,
        type: EquipmentType,
        magnification: Double?,
        aperture: Double?,
        apertureUnit: EquipmentApertureUnit
    ) throws -> EquipmentDraft {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EquipmentValidationError.blankName
        }

        let normalizedAperture = try normalizedApertureMillimeters(
            aperture,
            unit: apertureUnit,
            isRequired: type != .smartTelescope
        )

        switch type {
        case .binoculars:
            guard let magnification else {
                throw EquipmentValidationError.missingMagnification
            }
            guard magnification.isFinite, magnification > 0 else {
                throw EquipmentValidationError.invalidMagnification
            }

            return EquipmentDraft(
                validatedName: trimmedName,
                type: type,
                magnification: magnification,
                apertureMillimeters: normalizedAperture,
                apertureUnit: apertureUnit
            )

        case .visualTelescope, .smartTelescope:
            return EquipmentDraft(
                validatedName: trimmedName,
                type: type,
                magnification: nil,
                apertureMillimeters: normalizedAperture,
                apertureUnit: apertureUnit
            )
        }
    }

    private static func normalizedApertureMillimeters(
        _ aperture: Double?,
        unit: EquipmentApertureUnit,
        isRequired: Bool
    ) throws -> Double? {
        guard let aperture else {
            if isRequired {
                throw EquipmentValidationError.missingAperture
            }
            return nil
        }

        guard aperture.isFinite, aperture > 0 else {
            throw EquipmentValidationError.invalidAperture
        }

        let millimeters = EquipmentFormatting.apertureMillimeters(from: aperture, unit: unit)
        guard millimeters.isFinite, millimeters > 0 else {
            throw EquipmentValidationError.invalidAperture
        }
        return millimeters
    }
}

private extension EquipmentDraft {
    init(
        validatedName: String,
        type: EquipmentType,
        magnification: Double?,
        apertureMillimeters: Double?,
        apertureUnit: EquipmentApertureUnit
    ) {
        self.name = validatedName
        self.type = type
        self.magnification = magnification
        self.apertureMillimeters = apertureMillimeters
        self.apertureUnit = apertureUnit
    }
}

public enum EquipmentFormatting {
    /// Parses a decimal-pad value without accepting partial or unrelated text.
    /// Blank input remains distinct so optional fields can omit a value.
    public static func decimalInput(from text: String, locale: Locale) -> EquipmentDecimalInput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .blank }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        formatter.usesGroupingSeparator = false
        formatter.generatesDecimalNumbers = true

        guard isStrictDecimalText(
            trimmed,
            decimalSeparator: formatter.decimalSeparator ?? ".",
            plusSign: formatter.plusSign ?? "+",
            minusSign: formatter.minusSign ?? "-"
        ), let number = formatter.number(from: trimmed) else {
            return .invalid
        }

        let value = number.doubleValue
        return value.isFinite ? .value(value) : .invalid
    }

    public static func apertureValue(
        fromMillimeters millimeters: Double,
        unit: EquipmentApertureUnit
    ) -> Double {
        unit == .inches ? millimeters / EquipmentValidation.millimetersPerInch : millimeters
    }

    public static func apertureMillimeters(
        from value: Double,
        unit: EquipmentApertureUnit
    ) -> Double {
        unit == .inches ? value * EquipmentValidation.millimetersPerInch : value
    }

    public static func apertureInputText(
        fromMillimeters millimeters: Double,
        unit: EquipmentApertureUnit,
        locale: Locale
    ) -> String {
        decimalText(apertureValue(fromMillimeters: millimeters, unit: unit), locale: locale)
    }

    /// Returns converted text only for a complete, finite numeric input. Callers
    /// leave blank or partially entered invalid input untouched.
    public static func convertedApertureInputText(
        _ text: String,
        from sourceUnit: EquipmentApertureUnit,
        to destinationUnit: EquipmentApertureUnit,
        locale: Locale
    ) -> String? {
        guard sourceUnit != destinationUnit else { return text }
        guard case let .value(value) = decimalInput(from: text, locale: locale) else {
            return nil
        }

        let millimeters = apertureMillimeters(from: value, unit: sourceUnit)
        guard millimeters.isFinite else { return nil }
        return apertureInputText(
            fromMillimeters: millimeters,
            unit: destinationUnit,
            locale: locale
        )
    }

    public static func decimalText(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 15
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func millimeters(_ value: Double) -> String {
        let roundedToTenth = (value * 10).rounded() / 10
        if roundedToTenth.rounded() == roundedToTenth {
            return "\(Int(roundedToTenth)) mm"
        }
        return "\(roundedToTenth) mm"
    }

    private static func isStrictDecimalText(
        _ text: String,
        decimalSeparator: String,
        plusSign: String,
        minusSign: String
    ) -> Bool {
        var unsignedText = text
        if unsignedText.hasPrefix(plusSign) {
            unsignedText.removeFirst(plusSign.count)
        } else if unsignedText.hasPrefix(minusSign) {
            unsignedText.removeFirst(minusSign.count)
        }

        guard !unsignedText.isEmpty else { return false }
        let parts = unsignedText.components(separatedBy: decimalSeparator)
        guard parts.count <= 2 else { return false }
        guard parts.last?.isEmpty == false else { return false }

        let digits = CharacterSet.decimalDigits
        return parts.allSatisfy { part in
            part.unicodeScalars.allSatisfy(digits.contains)
        } && parts.contains { !$0.isEmpty }
    }
}

public enum EquipmentDecimalInput: Equatable, Sendable {
    case blank
    case value(Double)
    case invalid
}

#if os(iOS)
import SwiftData

@Model
public final class EquipmentItem {
    @Attribute(.unique) public var id: UUID
    public var name: String
    private var equipmentTypeRawValue: String
    public var magnification: Double?
    public var apertureMillimeters: Double?
    private var apertureUnitRawValue: String = EquipmentApertureUnit.millimeters.rawValue

    public var type: EquipmentType {
        get { EquipmentType(rawValue: equipmentTypeRawValue) ?? .binoculars }
        set { equipmentTypeRawValue = newValue.rawValue }
    }

    public var apertureUnit: EquipmentApertureUnit {
        get { EquipmentApertureUnit(rawValue: apertureUnitRawValue) ?? .millimeters }
        set { apertureUnitRawValue = newValue.rawValue }
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
        apertureMillimeters: Double?,
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
    var detailText: String {
        switch type {
        case .binoculars:
            let magnificationText = magnification.map { "\(EquipmentFormatting.number($0))×" } ?? ""
            let apertureText = apertureMillimeters.map(EquipmentFormatting.millimeters) ?? ""
            return "\(magnificationText)\(apertureText)"
        case .visualTelescope:
            return apertureMillimeters.map { "\(EquipmentFormatting.millimeters($0)) aperture" } ?? ""
        case .smartTelescope:
            return apertureMillimeters.map { "\(EquipmentFormatting.millimeters($0)) aperture" } ?? "Aperture not specified"
        }
    }
}

private extension EquipmentFormatting {
    static func number(_ value: Double) -> String {
        let roundedToTenth = (value * 10).rounded() / 10
        if roundedToTenth.rounded() == roundedToTenth {
            return "\(Int(roundedToTenth))"
        }
        return "\(roundedToTenth)"
    }
}
#endif
