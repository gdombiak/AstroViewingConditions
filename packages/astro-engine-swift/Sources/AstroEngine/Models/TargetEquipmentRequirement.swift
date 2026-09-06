import Foundation

public enum TargetEquipmentFraming: String, Codable, Sendable, Hashable {
    case veryWide
    case wide
    case medium
    case compact
}

public enum BinocularSuitability: String, Codable, Sendable, Hashable {
    case unsuitable
    case practical
    case preferred
}

/// Whether electronically assisted observing is a poor fit, supported, or a
/// particularly helpful way to observe the target.
public enum SmartEAASuitability: String, Codable, Sendable, Hashable {
    case poorMatch
    case supported
    case preferred
}

public enum NakedEyeSuitability: String, Codable, Sendable, Hashable {
    case unsupported
    case challenging
    case preferred
}

public struct TargetEquipmentRequirement: Sendable, Hashable, Codable {
    public let nakedEyeSuitability: NakedEyeSuitability
    public let binocularSuitability: BinocularSuitability
    public let preferredBinocularMagnification: ClosedRange<Double>?
    public let practicalBinocularApertureMillimeters: Double?
    public let preferredBinocularApertureMillimeters: Double?
    public let practicalVisualApertureMillimeters: Double?
    public let preferredVisualApertureMillimeters: Double?
    public let practicalSmartEAAApertureMillimeters: Double?
    public let preferredSmartEAAApertureMillimeters: Double?
    public let framing: TargetEquipmentFraming
    public let magnificationBenefit: Bool
    public let smartEAASuitability: SmartEAASuitability

    public init(
        nakedEyeSuitability: NakedEyeSuitability = .unsupported,
        binocularSuitability: BinocularSuitability = .unsuitable,
        preferredBinocularMagnification: ClosedRange<Double>? = nil,
        practicalBinocularApertureMillimeters: Double? = nil,
        preferredBinocularApertureMillimeters: Double? = nil,
        practicalVisualApertureMillimeters: Double? = nil,
        preferredVisualApertureMillimeters: Double? = nil,
        practicalSmartEAAApertureMillimeters: Double? = nil,
        preferredSmartEAAApertureMillimeters: Double? = nil,
        framing: TargetEquipmentFraming = .medium,
        magnificationBenefit: Bool = false,
        smartEAASuitability: SmartEAASuitability = .poorMatch
    ) {
        self.nakedEyeSuitability = nakedEyeSuitability
        self.binocularSuitability = binocularSuitability
        self.preferredBinocularMagnification = preferredBinocularMagnification
        self.practicalBinocularApertureMillimeters = practicalBinocularApertureMillimeters
        self.preferredBinocularApertureMillimeters = preferredBinocularApertureMillimeters
        self.practicalVisualApertureMillimeters = practicalVisualApertureMillimeters
        self.preferredVisualApertureMillimeters = preferredVisualApertureMillimeters
        precondition(
            (practicalSmartEAAApertureMillimeters != nil) == (preferredSmartEAAApertureMillimeters != nil),
            "Smart/EAA practical and preferred aperture thresholds must be provided together."
        )
        precondition(
            Self.hasValidSmartEAAApertureThresholds(
                practical: practicalSmartEAAApertureMillimeters,
                preferred: preferredSmartEAAApertureMillimeters
            ),
            "Smart/EAA aperture thresholds must be finite, positive, and ordered from practical to preferred."
        )
        self.practicalSmartEAAApertureMillimeters = practicalSmartEAAApertureMillimeters
        self.preferredSmartEAAApertureMillimeters = preferredSmartEAAApertureMillimeters
        self.framing = framing
        self.magnificationBenefit = magnificationBenefit
        self.smartEAASuitability = smartEAASuitability
    }

    public static func hasValidSmartEAAApertureThresholds(
        practical: Double?,
        preferred: Double?
    ) -> Bool {
        switch (practical, preferred) {
        case (nil, nil):
            return true
        case let (practical?, preferred?):
            return practical.isFinite
                && practical > 0
                && preferred.isFinite
                && preferred > 0
                && preferred >= practical
        default:
            return false
        }
    }
}

