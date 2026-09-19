import Foundation
import CoreFoundation

public enum LocationScoreCompositionContract {
    public static let capabilityID = LocationScoreComposition.capabilityID
    /// Transport/resource bound equal to the largest public `location.grid` result.
    public static let maxCandidateCount = GeographicGridGenerator.contractPointCapCount

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys) == ["candidates"],
              let rows = input["candidates"] as? [Any] else {
            throw LocationScoreCompositionError.invalidInput
        }
        guard rows.count <= maxCandidateCount else {
            throw LocationScoreCompositionError.rowCap(maximum: maxCandidateCount)
        }

        let candidates = try rows.map(parseCandidate)
        let result = try LocationScoreComposition.compose(candidates)
        let mode: String
        switch result.scoringMode {
        case .observingQuality:
            mode = "observing_quality"
        case .nightConditionsFallback:
            mode = "night_conditions_fallback"
        }
        return [
            "scoring_mode": mode,
            "candidates": result.candidates.map { candidate in
                [
                    "input_index": candidate.inputIndex,
                    "public_score": candidate.publicScore,
                    "improvement_over_center": candidate.improvementOverCenter as Any? ?? NSNull(),
                ] as [String: Any]
            },
        ]
    }

    private static func parseCandidate(_ value: Any) throws -> LocationScoreCompositionCandidate {
        guard let row = value as? [String: Any],
              Set(row.keys) == [
                  "is_center", "night_conditions_score", "has_nighttime_rows", "observing_quality",
              ],
              let observingQuality = row["observing_quality"] as? [String: Any],
              Set(observingQuality.keys) == ["score", "has_valid_light_pollution"] else {
            throw LocationScoreCompositionError.invalidInput
        }
        return LocationScoreCompositionCandidate(
            isCenter: try boolean(row["is_center"]),
            nightConditionsScore: try score(row["night_conditions_score"]),
            hasNighttimeRows: try boolean(row["has_nighttime_rows"]),
            observingQuality: ObservingQualityCompositionInput(
                score: try score(observingQuality["score"]),
                hasValidLightPollution: try boolean(observingQuality["has_valid_light_pollution"])
            )
        )
    }

    private static func boolean(_ value: Any?) throws -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw LocationScoreCompositionError.invalidInput
        }
        return number.boolValue
    }

    private static func score(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw LocationScoreCompositionError.invalidInput
        }
        let raw = number.doubleValue
        guard raw.isFinite, raw.rounded(.towardZero) == raw,
              raw >= 0, raw <= 100 else {
            throw LocationScoreCompositionError.invalidInput
        }
        return Int(raw)
    }
}
