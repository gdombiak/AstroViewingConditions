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
            explanation: explanation(for: best, isBestSelectedMatch: selectedCapabilities.count > 1)
        )
    }

    private func candidate(
        for capability: EquipmentCapability,
        target: ObservableTarget,
        requirement: TargetEquipmentRequirement
    ) -> Candidate {
        guard let type = capability.type else {
            switch requirement.nakedEyeSuitability {
            case .unsupported:
                return Candidate(capability: capability, level: .poor, mode: .nakedEye, reason: .nakedEyeUnsupported, preference: 0)
            case .challenging:
                return Candidate(capability: capability, level: .challenging, mode: .nakedEye, reason: .nakedEyeChallenging, preference: 30)
            case .preferred:
                let level: EquipmentFitLevel = target.type == .planet ? .good : .excellent
                return Candidate(capability: capability, level: level, mode: .nakedEye, reason: .nakedEyePreferred, preference: 60)
            }
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
            let magnificationFit = binocularMagnificationFit(
                capability.magnification,
                preferredRange: requirement.preferredBinocularMagnification
            )
            guard aperture >= practicalAperture else {
                let reason: EquipmentFitReason = magnificationFit == .inRange
                    ? .apertureLimited
                    : .apertureAndMagnificationLimited
                return Candidate(capability: capability, level: .challenging, mode: .visual, reason: reason, preference: 30)
            }
            guard magnificationFit == .inRange else {
                return Candidate(
                    capability: capability,
                    level: .challenging,
                    mode: .visual,
                    reason: reason(for: magnificationFit),
                    preference: 40
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

    private func explanation(for candidate: Candidate, isBestSelectedMatch: Bool) -> String {
        let bestPrefix = isBestSelectedMatch ? "Best selected match — " : ""
        let prefix: String
        if candidate.mode == .nakedEye {
            prefix = "\(bestPrefix)\(candidate.level.displayName) for naked-eye observing."
        } else {
            let mode = candidate.mode == .visual ? "visual observing" : "electronically assisted observing"
            prefix = "\(bestPrefix)Using “\(candidate.capability.displayName)”: \(candidate.level.displayName) for \(mode)."
        }
        switch candidate.reason {
        case .nakedEyeChallenging:
            return "\(prefix) Detection requires favorable darkness and does not provide a detailed view."
        case .nakedEyeUnsupported:
            return "\(prefix) Optical equipment is needed for a useful view."
        case .wideField:
            return "\(prefix) Its magnification is within the preferred range, and the binocular view suits this broad target."
        case .preferredAperture:
            return "\(prefix) Its aperture meets the preferred requirement."
        case .practicalAperture:
            return candidate.capability.type == .binoculars
                ? "\(prefix) Its aperture is sufficient and its magnification is within the preferred range."
                : "\(prefix) Its aperture meets the practical requirement."
        case .apertureLimited:
            return candidate.mode == .electronicallyAssisted
                ? "\(prefix) More aperture may improve the result."
                : "\(prefix) More aperture may make the visual view easier."
        case .apertureAndMagnificationLimited:
            return "\(prefix) More aperture and a magnification within the target's preferred range would make detection easier."
        case .framingLimited:
            return candidate.mode == .electronicallyAssisted
                ? "\(prefix) This broad target may require a wider field than the equipment provides."
                : "\(prefix) A telescope may not provide the field needed to frame this target."
        case .electronicAssistance: return "\(prefix) Electronic capture can reveal faint structure that is difficult to see visually."
        case .electronicSupport: return "\(prefix) Electronic capture can build a clearer view of this target."
        case .unknownRequirement: return "\(prefix) Equipment requirements are not yet cataloged for this target."
        case .magnification: return "\(prefix) Useful magnification can reveal more detail."
        case .binocularMagnificationInRange:
            return "\(prefix) Its magnification is within the preferred range."
        case .binocularMagnificationTooLow:
            return "\(prefix) Its magnification is below the target's preferred range."
        case .binocularMagnificationTooHigh:
            return "\(prefix) Its magnification is above the target's preferred range and may make the view harder to hold or frame."
        case .binocularMagnificationUnknown:
            return "\(prefix) Add a valid binocular magnification to assess the view accurately."
        case .modeMismatch:
            return "\(prefix) This observing mode is not suitable for the target."
        case .nakedEyePreferred:
            return prefix
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

    private enum BinocularMagnificationFit: Equatable {
        case inRange
        case tooLow
        case tooHigh
        case unknown
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
