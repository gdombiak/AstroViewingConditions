import Foundation

/// The user's minimum acceptable best-equipment fit for a recommendation.
///
/// This is deliberately separate from presentation labels and session controls.
/// The raw values are the public transport values shared with Python.
public enum RecommendationEquipmentFitThreshold: String, CaseIterable, Sendable, Hashable {
    case any
    case challengingOrBetter
    case goodOrBetter
    case excellentOnly

    public func includes(_ level: EquipmentFitLevel) -> Bool {
        switch self {
        case .any:
            return true
        case .challengingOrBetter:
            return level != .poor
        case .goodOrBetter:
            return level == .excellent || level == .good
        case .excellentOnly:
            return level == .excellent
        }
    }
}

/// Stable equipment filtering over an already conditions-ranked recommendation
/// list. It makes no scoring or ordering decision and returns caller identities
/// so hosts can reuse their original recommendation objects.
public enum RecommendationEquipmentFilter {
    public static let capabilityID = "targets.filter_recommendations_by_equipment"

    public struct Candidate: Sendable, Hashable {
        public let key: String
        public let isPlanet: Bool
        public let requirement: TargetEquipmentRequirement

        public init(key: String, isPlanet: Bool, requirement: TargetEquipmentRequirement) {
            self.key = key
            self.isPlanet = isPlanet
            self.requirement = requirement
        }
    }

    public struct Selection: Sendable, Equatable {
        public let index: Int
        public let key: String

        public init(index: Int, key: String) {
            self.index = index
            self.key = key
        }
    }

    /// Returns an ordered subset of `candidates` without sorting or
    /// deduplicating. Empty saved inventory and `.any` bypass matching exactly
    /// as production does. Otherwise a missing best match is rejected.
    public static func selected(
        candidates: [Candidate],
        capabilities: [EquipmentMatchCapability],
        hasSavedInventory: Bool,
        minimumFit: RecommendationEquipmentFitThreshold,
        matchingRules: EquipmentMatchingRules = EquipmentMatchingRules()
    ) -> [Selection] {
        guard hasSavedInventory, minimumFit != .any else {
            return candidates.enumerated().map { Selection(index: $0.offset, key: $0.element.key) }
        }

        return candidates.enumerated().compactMap { index, candidate in
            guard let best = matchingRules.ranked(
                isPlanet: candidate.isPlanet,
                requirement: candidate.requirement,
                capabilities: capabilities
            ).first, minimumFit.includes(best.level) else {
                return nil
            }
            return Selection(index: index, key: candidate.key)
        }
    }
}
