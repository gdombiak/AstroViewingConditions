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
    /// All saved optical instruments have a normalized aperture for matching.
    public let apertureMillimeters: Double
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
    case magnificationTooHigh
    case missingAperture
    case invalidAperture
    case apertureTooLarge

    public var field: EquipmentFormField {
        switch self {
        case .blankName:
            return .name
        case .missingMagnification, .invalidMagnification, .magnificationTooHigh:
            return .magnification
        case .missingAperture, .invalidAperture, .apertureTooLarge:
            return .aperture
        }
    }

    public var message: String {
        switch self {
        case .blankName:
            return "Enter a name for this equipment."
        case .missingMagnification:
            return "Enter the magnification, such as 10 for 10×50 binoculars."
        case .invalidMagnification:
            return "Enter a number greater than zero."
        case .magnificationTooHigh:
            return "Magnification looks too high. Enter the first number shown on the binoculars."
        case .missingAperture:
            return "Enter the aperture."
        case .invalidAperture:
            return "Enter a number greater than zero."
        case .apertureTooLarge:
            return "Aperture looks too large. Check the value and selected unit."
        }
    }

    public func inlineMessage(for type: EquipmentType) -> String {
        guard self == .missingAperture, type == .binoculars else { return message }
        return "Enter the aperture, such as 50 for 10×50 binoculars."
    }
}

public enum EquipmentValidation {
    public static let millimetersPerInch = 25.4
    public static let maximumBinocularMagnification = 100.0
    public static let maximumBinocularApertureMillimeters = 300.0
    public static let maximumTelescopeApertureMillimeters = 2_000.0

    public static func validationErrors(
        name: String,
        type: EquipmentType,
        magnification: Double?,
        aperture: Double?,
        apertureUnit: EquipmentApertureUnit
    ) -> [EquipmentValidationError] {
        var errors: [EquipmentValidationError] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.blankName)
        }

        if type == .binoculars {
            switch magnification {
            case nil:
                errors.append(.missingMagnification)
            case let value? where !value.isFinite || value <= 0:
                errors.append(.invalidMagnification)
            case let value? where value > maximumBinocularMagnification:
                errors.append(.magnificationTooHigh)
            default:
                break
            }
        }

        switch normalizedApertureMillimeters(aperture, unit: apertureUnit) {
        case nil:
            errors.append(.missingAperture)
        case let value? where value <= 0 || !value.isFinite:
            errors.append(.invalidAperture)
        case let value? where value > maximumApertureMillimeters(for: type):
            errors.append(.apertureTooLarge)
        default:
            break
        }

        return errors
    }

    public static func validate(
        name: String,
        type: EquipmentType,
        magnification: Double?,
        aperture: Double?,
        apertureUnit: EquipmentApertureUnit
    ) throws -> EquipmentDraft {
        if let error = validationErrors(
            name: name,
            type: type,
            magnification: magnification,
            aperture: aperture,
            apertureUnit: apertureUnit
        ).first {
            throw error
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let aperture else { throw EquipmentValidationError.missingAperture }
        let normalizedAperture = EquipmentFormatting.apertureMillimeters(from: aperture, unit: apertureUnit)

        switch type {
        case .binoculars:
            guard let magnification else { throw EquipmentValidationError.missingMagnification }

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
        unit: EquipmentApertureUnit
    ) -> Double? {
        guard let aperture else { return nil }
        let millimeters = EquipmentFormatting.apertureMillimeters(from: aperture, unit: unit)
        return millimeters
    }

    private static func maximumApertureMillimeters(for type: EquipmentType) -> Double {
        type == .binoculars
            ? maximumBinocularApertureMillimeters
            : maximumTelescopeApertureMillimeters
    }
}

public enum EquipmentFormField: Hashable, Sendable {
    case name
    case magnification
    case aperture
}

public enum EquipmentFormPresentation {
    public static let nameAccessibilityLabel = "Equipment name"

    public static func opticsFields(for type: EquipmentType) -> [EquipmentFormField] {
        switch type {
        case .binoculars: return [.magnification, .aperture]
        case .visualTelescope, .smartTelescope: return [.aperture]
        }
    }

    public static func label(for field: EquipmentFormField) -> String {
        switch field {
        case .name: return "Name"
        case .magnification: return "Magnification"
        case .aperture: return "Aperture"
        }
    }

    public static func binocularSizeSummary(
        magnificationText: String,
        apertureText: String,
        apertureUnit: EquipmentApertureUnit,
        locale: Locale
    ) -> String? {
        guard case let .value(magnification) = EquipmentFormatting.decimalInput(from: magnificationText, locale: locale),
              case let .value(aperture) = EquipmentFormatting.decimalInput(from: apertureText, locale: locale),
              magnification > 0,
              aperture > 0,
              magnification <= EquipmentValidation.maximumBinocularMagnification else {
            return nil
        }
        let apertureMillimeters = EquipmentFormatting.apertureMillimeters(from: aperture, unit: apertureUnit)
        guard apertureMillimeters.isFinite,
              apertureMillimeters > 0,
              apertureMillimeters <= EquipmentValidation.maximumBinocularApertureMillimeters else {
            return nil
        }
        return "Binocular size: \(EquipmentFormatting.decimalText(magnification, locale: locale))×\(EquipmentFormatting.decimalText(apertureMillimeters, locale: locale))"
    }

    public static func binocularApertureHelperText(for unit: EquipmentApertureUnit) -> String {
        switch unit {
        case .millimeters:
            return "Enter the second number in 10×50 binoculars."
        case .inches:
            return "Enter the objective aperture in inches. It will be shown in standard millimeter notation below."
        }
    }

    public static func magnificationText(afterChangingTo type: EquipmentType, currentText: String) -> String {
        type == .binoculars ? currentText : ""
    }
}

private extension EquipmentDraft {
    init(
        validatedName: String,
        type: EquipmentType,
        magnification: Double?,
        apertureMillimeters: Double,
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

    public static func isCombinedBinocularInput(_ text: String) -> Bool {
        let pattern = #"^\s*\d+(?:[\.,]\d+)?\s*[xX×]\s*\d+(?:[\.,]\d+)?\s*$"#
        return text.range(of: pattern, options: .regularExpression) != nil
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
    public var apertureMillimeters: Double
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
    var detailText: String {
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
        let roundedToTenth = (value * 10).rounded() / 10
        if roundedToTenth.rounded() == roundedToTenth {
            return "\(Int(roundedToTenth))"
        }
        return "\(roundedToTenth)"
    }
}
#endif
