import Foundation
import AstroEngine

public extension EquipmentFitLevel {
    var displayName: String { rawValue.capitalized }
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
        let ranked = EquipmentMatchingRules().ranked(
            isPlanet: target.type == .planet,
            requirement: target.equipmentRequirement,
            capabilities: selectedCapabilities.map {
                EquipmentMatchCapability(key: $0.stableSortKey, type: $0.type,
                    apertureMillimeters: $0.apertureMillimeters, magnification: $0.magnification)
            }
        )
        let candidates = ranked.map { row in
            Candidate(capability: selectedCapabilities.first { $0.stableSortKey == row.capability.key }!,
                      level: row.level, mode: row.mode, reason: row.reason)
        }
        guard let best = candidates.first else { return nil }
        let others = candidates.dropFirst().filter { $0.level == .excellent || $0.level == .good }.map(\.capability)
        return EquipmentFitResult(
            bestCapability: best.capability,
            otherSuitableCapabilities: others,
            level: best.level,
            observingMode: best.mode,
            reason: best.reason,
            explanation: explanation(for: best, isBestSelectedMatch: selectedCapabilities.count > 1)
        )
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

    }
}

extension EquipmentCapability {
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
