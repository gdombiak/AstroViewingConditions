import Foundation

public enum EquipmentFitLevel: String, CaseIterable, Sendable, Hashable {
    case excellent
    case good
    case challenging
    case poor

    public var displayName: String { rawValue.capitalized }
    fileprivate var rank: Int {
        switch self { case .excellent: return 0; case .good: return 1; case .challenging: return 2; case .poor: return 3 }
    }
}

public enum EquipmentFitObservingMode: Sendable, Hashable {
    case nakedEye
    case visual
    case electronicallyAssisted
}

public enum EquipmentFitReason: Sendable, Hashable {
    case nakedEye
    case wideField
    case preferredAperture
    case practicalAperture
    case magnification
    case electronicAssistance
    case electronicSupport
    case apertureLimited
    case framingLimited
    case modeMismatch
    case unknownRequirement
}

public struct EquipmentFitResult: Sendable, Hashable {
    public let bestCapability: EquipmentCapability
    public let otherSuitableCapabilities: [EquipmentCapability]
    public let level: EquipmentFitLevel
    public let observingMode: EquipmentFitObservingMode
    public let reason: EquipmentFitReason
    public let explanation: String
}

public struct EquipmentMatchingService: Sendable {
    public init() {}

    public func match(target: ObservableTarget, using selectedCapabilities: [EquipmentCapability]) -> EquipmentFitResult? {
        guard !selectedCapabilities.isEmpty else { return nil }
        let requirement = target.equipmentRequirement
        let candidates = selectedCapabilities.map { candidate(for: $0, target: target, requirement: requirement) }
            .sorted { lhs, rhs in
                if lhs.level.rank != rhs.level.rank { return lhs.level.rank < rhs.level.rank }
                if lhs.preference != rhs.preference { return lhs.preference > rhs.preference }
                if lhs.apertureMillimeters != rhs.apertureMillimeters {
                    return lhs.apertureMillimeters > rhs.apertureMillimeters
                }
                if lhs.magnification != rhs.magnification {
                    return lhs.magnification > rhs.magnification
                }
                return lhs.capability.stableSortKey < rhs.capability.stableSortKey
            }
        guard let best = candidates.first else { return nil }
        let others = candidates.dropFirst().filter { $0.level.rank <= EquipmentFitLevel.good.rank }.map(\.capability)
        return EquipmentFitResult(
            bestCapability: best.capability,
            otherSuitableCapabilities: others,
            level: best.level,
            observingMode: best.mode,
            reason: best.reason,
            explanation: explanation(for: best)
        )
    }

    private func candidate(
        for capability: EquipmentCapability,
        target: ObservableTarget,
        requirement: TargetEquipmentRequirement
    ) -> Candidate {
        guard let type = capability.type else {
            let supportsNakedEye = requirement.nakedEyeSuitable
            let level: EquipmentFitLevel = supportsNakedEye
                ? (target.type == .planet ? .good : .excellent)
                : .poor
            return Candidate(capability: capability, level: level, mode: .nakedEye, reason: .nakedEye, preference: supportsNakedEye ? 60 : 0)
        }

        switch type {
        case .binoculars:
            guard requirement.binocularSuitability != .unsuitable else {
                return Candidate(capability: capability, level: .poor, mode: .visual, reason: .modeMismatch, preference: 0)
            }
            guard let aperture = capability.apertureMillimeters, aperture.isFinite, aperture > 0,
                  let practicalAperture = requirement.practicalBinocularApertureMillimeters,
                  let preferredAperture = requirement.preferredBinocularApertureMillimeters else {
                return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .unknownRequirement, preference: 20)
            }
            let magnificationFits = requirement.preferredBinocularMagnification.map { range in
                guard let magnification = capability.magnification, magnification.isFinite, magnification > 0 else { return false }
                return range.contains(magnification)
            } ?? false
            guard aperture >= practicalAperture else {
                return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .apertureLimited, preference: 30)
            }
            let isPreferred = requirement.binocularSuitability == .preferred
                && magnificationFits
                && aperture >= preferredAperture
            let level: EquipmentFitLevel = isPreferred ? .excellent : .good
            let reason: EquipmentFitReason = requirement.framing == .veryWide || requirement.framing == .wide ? .wideField : .magnification
            return Candidate(capability: capability, level: level, mode: .visual, reason: reason, preference: isPreferred ? 90 : 65)

        case .visualTelescope:
            guard let aperture = capability.apertureMillimeters, aperture.isFinite, aperture > 0,
                  let practical = requirement.practicalVisualApertureMillimeters,
                  let preferred = requirement.preferredVisualApertureMillimeters else {
                return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .unknownRequirement, preference: 20)
            }
            if requirement.framing == .veryWide {
                guard aperture >= practical else {
                    return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .apertureLimited, preference: 35)
                }
                // A generic telescope's actual field is unknown without focal
                // length and eyepiece data, so aperture alone cannot make it an
                // excellent very-wide-field fit.
                return Candidate(capability: capability, level: .good, mode: .visual, reason: .framingLimited, preference: 45)
            }
            let framingPreferenceAdjustment = requirement.framing == .wide ? -5 : 0
            if aperture >= preferred {
                return Candidate(capability: capability, level: .excellent, mode: .visual, reason: requirement.magnificationBenefit ? .magnification : .preferredAperture, preference: 85 + framingPreferenceAdjustment)
            }
            if aperture >= practical {
                return Candidate(capability: capability, level: .good, mode: .visual, reason: .practicalAperture, preference: 70 + framingPreferenceAdjustment)
            }
            return Candidate(capability: capability, level: .challenging, mode: .visual, reason: .apertureLimited, preference: 35)

        case .smartTelescope:
            guard let aperture = capability.apertureMillimeters,
                  aperture.isFinite,
                  aperture > 0 else {
                return Candidate(capability: capability, level: .poor, mode: .electronicallyAssisted, reason: .apertureLimited, preference: 0)
            }
            switch requirement.smartEAASuitability {
            case .poorMatch:
                return Candidate(capability: capability, level: .poor, mode: .electronicallyAssisted, reason: .modeMismatch, preference: 0)
            case .preferred, .supported:
                guard let practical = requirement.practicalSmartEAAApertureMillimeters,
                      let preferred = requirement.preferredSmartEAAApertureMillimeters else {
                    return Candidate(capability: capability, level: .challenging, mode: .electronicallyAssisted, reason: .unknownRequirement, preference: 20)
                }
                guard aperture >= practical else {
                    return Candidate(capability: capability, level: .challenging, mode: .electronicallyAssisted, reason: .apertureLimited, preference: 35)
                }

                switch requirement.smartEAASuitability {
                case .preferred:
                    if aperture >= preferred {
                        let level: EquipmentFitLevel = isBroadFraming(requirement.framing) ? .good : .excellent
                        let reason: EquipmentFitReason = isBroadFraming(requirement.framing) ? .framingLimited : .electronicAssistance
                        return Candidate(capability: capability, level: level, mode: .electronicallyAssisted, reason: reason, preference: level == .excellent ? 95 : 80)
                    }
                    return Candidate(capability: capability, level: .good, mode: .electronicallyAssisted, reason: .electronicAssistance, preference: 80)
                case .supported:
                    return Candidate(capability: capability, level: .good, mode: .electronicallyAssisted, reason: .electronicSupport, preference: 65)
                case .poorMatch:
                    return Candidate(capability: capability, level: .poor, mode: .electronicallyAssisted, reason: .modeMismatch, preference: 0)
                }
            }
        }
    }

    private func isBroadFraming(_ framing: TargetEquipmentFraming) -> Bool {
        framing == .veryWide || framing == .wide
    }

    private func explanation(for candidate: Candidate) -> String {
        let capabilityName = "your \(candidate.capability.displayName)"
        let prefix: String
        switch candidate.mode {
        case .nakedEye: prefix = "\(candidate.level.displayName) for naked-eye observing."
        case .visual: prefix = "\(candidate.level.displayName) for visual observing with \(capabilityName)."
        case .electronicallyAssisted: prefix = "\(candidate.level.displayName) for electronically assisted observing with \(capabilityName)."
        }
        switch candidate.reason {
        case .wideField: return "\(prefix) A wide field frames this target well."
        case .apertureLimited:
            return candidate.mode == .electronicallyAssisted
                ? "\(prefix) More aperture may improve the result."
                : "\(prefix) More aperture may make the visual view easier."
        case .framingLimited:
            return candidate.mode == .electronicallyAssisted
                ? "\(prefix) This broad target may require a wider field than the equipment provides."
                : "\(prefix) A telescope may not provide the field needed to frame this target."
        case .electronicAssistance: return "\(prefix) Electronic assistance is especially well suited to this target."
        case .electronicSupport: return "\(prefix) Electronic assistance supports this target."
        case .unknownRequirement: return "\(prefix) Equipment requirements are not yet cataloged for this target."
        case .magnification: return "\(prefix) Useful magnification can reveal more detail."
        default: return prefix
        }
    }

    private struct Candidate {
        let capability: EquipmentCapability
        let level: EquipmentFitLevel
        let mode: EquipmentFitObservingMode
        let reason: EquipmentFitReason
        let preference: Int

        var apertureMillimeters: Double { capability.apertureMillimeters ?? 0 }
        var magnification: Double { capability.magnification ?? 0 }
    }
}

private extension EquipmentCapability {
    /// A saved item keeps this identifier when its user-visible name changes.
    var stableSortKey: String {
        switch id {
        case .nakedEye:
            return "0"
        case let .savedEquipment(id):
            return "1\(id.uuidString)"
        }
    }
}
