import Foundation

public enum EquipmentFitLevel: String, CaseIterable, Sendable, Hashable {
    case excellent
    case good
    case challenging
    case poor

    fileprivate var rank: Int {
        switch self { case .excellent: return 0; case .good: return 1; case .challenging: return 2; case .poor: return 3 }
    }
}

public enum EquipmentFitObservingMode: String, Codable, Sendable, Hashable {
    case nakedEye
    case visual
    case electronicallyAssisted
}

public enum EquipmentFitReason: String, Codable, Sendable, Hashable {
    case nakedEyePreferred
    case nakedEyeChallenging
    case nakedEyeUnsupported
    case wideField
    case preferredAperture
    case practicalAperture
    case magnification
    case binocularMagnificationInRange
    case binocularMagnificationTooLow
    case binocularMagnificationTooHigh
    case binocularMagnificationUnknown
    case apertureAndMagnificationLimited
    case electronicAssistance
    case electronicSupport
    case apertureLimited
    case framingLimited
    case modeMismatch
    case unknownRequirement
}

public struct EquipmentMatchCapability: Sendable {
    public let key: String
    public let type: EquipmentType?
    public let apertureMillimeters: Double?
    public let magnification: Double?
    public init(key: String, type: EquipmentType?, apertureMillimeters: Double?, magnification: Double?) {
        self.key = key
        self.type = type
        self.apertureMillimeters = apertureMillimeters
        self.magnification = magnification
    }
}

public struct EquipmentMatchingRules: Sendable {
    private let p: EquipmentMatchingCalibration.Preferences
    public init(calibration: EquipmentMatchingCalibration = EngineCalibration.current.equipmentMatching) {
        p = calibration.preferences
    }
    public func ranked(isPlanet: Bool, requirement: TargetEquipmentRequirement, capabilities: [EquipmentMatchCapability]) -> [Candidate] {
        capabilities.map { candidate(for: $0, isPlanet: isPlanet, requirement: requirement) }.sorted {
            if $0.level.rank != $1.level.rank { return $0.level.rank < $1.level.rank }
            if $0.preference != $1.preference { return $0.preference > $1.preference }
            if $0.apertureMillimeters != $1.apertureMillimeters { return $0.apertureMillimeters > $1.apertureMillimeters }
            if $0.magnification != $1.magnification { return $0.magnification > $1.magnification }
            return $0.capability.key.utf8.lexicographicallyPrecedes($1.capability.key.utf8)
        }
    }
    public func candidate(
        for capability: EquipmentMatchCapability,
        isPlanet: Bool,
        requirement: TargetEquipmentRequirement
    ) -> Candidate {
        guard let type = capability.type else {
            switch requirement.nakedEyeSuitability {
            case .unsupported:
                return Candidate(capability: capability, level: .poor, mode: .nakedEye, reason: .nakedEyeUnsupported, preference: p.none)
            case .challenging:
                return Candidate(capability: capability, level: .challenging, mode: .nakedEye, reason: .nakedEyeChallenging, preference: p.naked_eye_challenging)
            case .preferred:
                let level: EquipmentFitLevel = isPlanet ? .good : .excellent
                return Candidate(capability: capability, level: level, mode: .nakedEye, reason: .nakedEyePreferred, preference: p.naked_eye_preferred)
            }
        }

        switch type {
        case .binoculars:
            guard requirement.binocularSuitability != .unsuitable else {
                return Candidate(capability: capability, level: .poor, mode: .visual, reason: .modeMismatch, preference: p.none)
            }
            guard let aperture = capability.apertureMillimeters, aperture.isFinite, aperture > 0,
                  let practicalAperture = requirement.practicalBinocularApertureMillimeters,
                  let preferredAperture = requirement.preferredBinocularApertureMillimeters else {
                return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .unknownRequirement, preference: p.unknown)
            }
            let magnificationFit = binocularMagnificationFit(
                capability.magnification,
                preferredRange: requirement.preferredBinocularMagnification
            )
            guard aperture >= practicalAperture else {
                let reason: EquipmentFitReason = magnificationFit == .inRange
                    ? .apertureLimited
                    : .apertureAndMagnificationLimited
                return Candidate(capability: capability, level: .challenging, mode: .visual, reason: reason, preference: p.binocular_aperture_limited)
            }
            guard magnificationFit == .inRange else {
                return Candidate(
                    capability: capability,
                    level: .challenging,
                    mode: .visual,
                    reason: reason(for: magnificationFit),
                    preference: p.binocular_magnification_limited
                )
            }
            let isPreferred = requirement.binocularSuitability == .preferred
                && aperture >= preferredAperture
            let level: EquipmentFitLevel = isPreferred ? .excellent : .good
            let reason: EquipmentFitReason
            if requirement.framing == .veryWide || requirement.framing == .wide {
                reason = .wideField
            } else if aperture >= preferredAperture {
                reason = .binocularMagnificationInRange
            } else {
                reason = .practicalAperture
            }
            return Candidate(capability: capability, level: level, mode: .visual, reason: reason, preference: isPreferred ? p.binocular_preferred : p.binocular_practical)

        case .visualTelescope:
            guard let aperture = capability.apertureMillimeters, aperture.isFinite, aperture > 0,
                  let practical = requirement.practicalVisualApertureMillimeters,
                  let preferred = requirement.preferredVisualApertureMillimeters else {
                return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .unknownRequirement, preference: p.unknown)
            }
            if requirement.framing == .veryWide {
                guard aperture >= practical else {
                    return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .apertureLimited, preference: p.aperture_limited)
                }
                // A generic telescope's actual field is unknown without focal
                // length and eyepiece data, so aperture alone cannot make it an
                // excellent very-wide-field fit.
                return Candidate(capability: capability, level: .good, mode: .visual, reason: .framingLimited, preference: p.very_wide_visual)
            }
            let framingPreferenceAdjustment = requirement.framing == .wide ? p.wide_visual_adjustment : 0
            if aperture >= preferred {
                return Candidate(capability: capability, level: .excellent, mode: .visual, reason: requirement.magnificationBenefit ? .magnification : .preferredAperture, preference: p.visual_preferred + framingPreferenceAdjustment)
            }
            if aperture >= practical {
                return Candidate(capability: capability, level: .good, mode: .visual, reason: .practicalAperture, preference: p.visual_practical + framingPreferenceAdjustment)
            }
            return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .apertureLimited, preference: p.aperture_limited)

        case .smartTelescope:
            guard let aperture = capability.apertureMillimeters,
                  aperture.isFinite,
                  aperture > 0 else {
                return Candidate(capability: capability, level: .poor, mode: .electronicallyAssisted, reason: .apertureLimited, preference: p.none)
            }
            switch requirement.smartEAASuitability {
            case .poorMatch:
                return Candidate(capability: capability, level: .poor, mode: .electronicallyAssisted, reason: .modeMismatch, preference: p.none)
            case .preferred, .supported:
                guard let practical = requirement.practicalSmartEAAApertureMillimeters,
                      let preferred = requirement.preferredSmartEAAApertureMillimeters else {
                    return Candidate(capability: capability, level: .challenging, mode: .electronicallyAssisted, reason: .unknownRequirement, preference: p.unknown)
                }
                guard aperture >= practical else {
                    return Candidate(capability: capability, level: .challenging, mode: .electronicallyAssisted, reason: .apertureLimited, preference: p.aperture_limited)
                }

                switch requirement.smartEAASuitability {
                case .preferred:
                    if aperture >= preferred {
                        let level: EquipmentFitLevel = isBroadFraming(requirement.framing) ? .good : .excellent
                        let reason: EquipmentFitReason = isBroadFraming(requirement.framing) ? .framingLimited : .electronicAssistance
                        return Candidate(capability: capability, level: level, mode: .electronicallyAssisted, reason: reason, preference: level == .excellent ? p.electronic_preferred : p.electronic_practical)
                    }
                    return Candidate(capability: capability, level: .good, mode: .electronicallyAssisted, reason: .electronicAssistance, preference: p.electronic_practical)
                case .supported:
                    return Candidate(capability: capability, level: .good, mode: .electronicallyAssisted, reason: .electronicSupport, preference: p.electronic_supported)
                case .poorMatch:
                    return Candidate(capability: capability, level: .poor, mode: .electronicallyAssisted, reason: .modeMismatch, preference: p.none)
                }
            }
        }
    }

    private func isBroadFraming(_ framing: TargetEquipmentFraming) -> Bool {
        framing == .veryWide || framing == .wide
    }

    private func binocularMagnificationFit(
        _ magnification: Double?,
        preferredRange: ClosedRange<Double>?
    ) -> BinocularMagnificationFit {
        guard let preferredRange else { return .unknown }
        guard let magnification, magnification.isFinite, magnification > 0 else { return .unknown }
        if magnification < preferredRange.lowerBound { return .tooLow }
        if magnification > preferredRange.upperBound { return .tooHigh }
        return .inRange
    }

    private func reason(for fit: BinocularMagnificationFit) -> EquipmentFitReason {
        switch fit {
        case .inRange: return .binocularMagnificationInRange
        case .tooLow: return .binocularMagnificationTooLow
        case .tooHigh: return .binocularMagnificationTooHigh
        case .unknown: return .binocularMagnificationUnknown
        }
    }

    public struct Candidate: Sendable {
        public let capability: EquipmentMatchCapability
        public let level: EquipmentFitLevel
        public let mode: EquipmentFitObservingMode
        public let reason: EquipmentFitReason
        public let preference: Int

        var apertureMillimeters: Double { capability.apertureMillimeters ?? 0 }
        var magnification: Double { capability.magnification ?? 0 }
    }

    private enum BinocularMagnificationFit: Equatable {
        case inRange
        case tooLow
        case tooHigh
        case unknown
    }
}
