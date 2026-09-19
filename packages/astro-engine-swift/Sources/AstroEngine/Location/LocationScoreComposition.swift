import Foundation

public struct ObservingQualityCompositionInput: Sendable, Equatable {
    public let score: Int
    public let hasValidLightPollution: Bool

    public init(score: Int, hasValidLightPollution: Bool) {
        self.score = score
        self.hasValidLightPollution = hasValidLightPollution
    }
}

public struct LocationScoreCompositionCandidate: Sendable, Equatable {
    public let isCenter: Bool
    public let nightConditionsScore: Int
    public let hasNighttimeRows: Bool
    public let observingQuality: ObservingQualityCompositionInput

    public init(
        isCenter: Bool,
        nightConditionsScore: Int,
        hasNighttimeRows: Bool,
        observingQuality: ObservingQualityCompositionInput
    ) {
        self.isCenter = isCenter
        self.nightConditionsScore = nightConditionsScore
        self.hasNighttimeRows = hasNighttimeRows
        self.observingQuality = observingQuality
    }
}

public struct LocationScoreCompositionResult: Sendable, Equatable {
    public struct Candidate: Sendable, Equatable {
        public let inputIndex: Int
        public let publicScore: Int
        public let improvementOverCenter: Int?

        public init(inputIndex: Int, publicScore: Int, improvementOverCenter: Int?) {
            self.inputIndex = inputIndex
            self.publicScore = publicScore
            self.improvementOverCenter = improvementOverCenter
        }
    }

    public let scoringMode: BestSpotScoringMode
    public let candidates: [Candidate]

    public init(scoringMode: BestSpotScoringMode, candidates: [Candidate]) {
        self.scoringMode = scoringMode
        self.candidates = candidates
    }
}

public enum LocationScoreCompositionError: Error, Equatable, Sendable {
    case invalidInput
    case noScorableLocations
    case rowCap(maximum: Int)

    public var code: String {
        switch self {
        case .invalidInput:
            return "validation"
        case .noScorableLocations:
            return "no_scorable_locations"
        case .rowCap:
            return "sample_cap"
        }
    }

    public var message: String {
        switch self {
        case .invalidInput:
            return "invalid \(LocationScoreComposition.capabilityID) input"
        case .noScorableLocations:
            return "no scorable locations"
        case .rowCap(let maximum):
            return "\(LocationScoreComposition.capabilityID) exceeds the 1.0 candidate-row cap (\(maximum) rows)"
        }
    }
}

/// Coherent public-score selection and center-relative deltas for one ordered
/// set of already-analyzed Best Nearby candidates. No ranking or truncation.
public enum LocationScoreComposition {
    public static let capabilityID = "location.compose_scores"

    public static func compose(
        _ candidates: [LocationScoreCompositionCandidate]
    ) throws -> LocationScoreCompositionResult {
        guard candidates.filter(\.isCenter).count <= 1,
              candidates.allSatisfy({ candidate in
                  (0...100).contains(candidate.nightConditionsScore) &&
                  (0...100).contains(candidate.observingQuality.score)
              }) else {
            throw LocationScoreCompositionError.invalidInput
        }

        let scorable = candidates.enumerated().filter { $0.element.hasNighttimeRows }
        guard !scorable.isEmpty else {
            throw LocationScoreCompositionError.noScorableLocations
        }

        let scoringMode: BestSpotScoringMode = scorable.allSatisfy {
            $0.element.observingQuality.hasValidLightPollution
        } ? .observingQuality : .nightConditionsFallback

        func publicScore(_ candidate: LocationScoreCompositionCandidate) -> Int {
            switch scoringMode {
            case .observingQuality:
                return candidate.observingQuality.score
            case .nightConditionsFallback:
                return candidate.nightConditionsScore
            }
        }

        let centerScore = scorable.first { $0.element.isCenter }
            .map { publicScore($0.element) }
        let output = scorable.map { index, candidate in
            let score = publicScore(candidate)
            return LocationScoreCompositionResult.Candidate(
                inputIndex: index,
                publicScore: score,
                improvementOverCenter: centerScore.map { score - $0 }
            )
        }
        return LocationScoreCompositionResult(scoringMode: scoringMode, candidates: output)
    }
}
