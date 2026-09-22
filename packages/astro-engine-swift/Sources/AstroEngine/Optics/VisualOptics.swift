import Foundation
import CoreFoundation

/// Deterministic telescope/eyepiece ratios. Missing inputs stay null.
/// Approximate true field is apparent field divided by magnification.
public enum VisualOptics {
    public static let capabilityID = "optics.calculate"
    public static let maxApparentFieldDegrees = 180.0

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        let allowed: Set<String> = [
            "telescope_focal_length_mm",
            "eyepiece_focal_length_mm",
            "telescope_aperture_mm",
            "afov_degrees",
        ]
        guard Set(input.keys).isSubset(of: allowed) else {
            throw VisualOpticsError.invalidInput
        }
        let telescopeFocalLength = try positive(input["telescope_focal_length_mm"])
        let eyepieceFocalLength = try positive(input["eyepiece_focal_length_mm"])
        let aperture = try positive(input["telescope_aperture_mm"])
        let apparentField = try afov(input["afov_degrees"])
        let magnification: Double?
        if let telescopeFocalLength, let eyepieceFocalLength {
            magnification = telescopeFocalLength / eyepieceFocalLength
        } else {
            magnification = nil
        }
        let exitPupil: Double?
        if let magnification, let aperture {
            exitPupil = aperture / magnification
        } else {
            exitPupil = nil
        }
        let trueField: Double?
        if let magnification, let apparentField {
            trueField = apparentField / magnification
        } else {
            trueField = nil
        }
        return [
            "magnification": magnification as Any? ?? NSNull(),
            "exit_pupil_mm": exitPupil as Any? ?? NSNull(),
            "approximate_true_field_of_view_degrees": trueField as Any? ?? NSNull(),
        ]
    }

    private static func positive(_ value: Any?) throws -> Double? {
        if value == nil || value is NSNull {
            return nil
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue > 0 else {
            throw VisualOpticsError.invalidInput
        }
        return number.doubleValue
    }

    private static func afov(_ value: Any?) throws -> Double? {
        guard let number = try positive(value) else {
            return nil
        }
        guard number <= maxApparentFieldDegrees else {
            throw VisualOpticsError.invalidInput
        }
        return number
    }
}

public enum VisualOpticsError: Error {
    case invalidInput
}
