import Foundation

public struct LocationRecommendabilityFilterInputError: Error, Equatable, Sendable {
    public let code: String
    public let message: String

    init() {
        code = "validation"
        message = "invalid \(LocationRecommendabilityFilter.capabilityID) input"
    }

    init(rowCap maximum: Int) {
        code = "sample_cap"
        message = "\(LocationRecommendabilityFilter.capabilityID) exceeds the 1.0 suitability-row cap (\(maximum) rows)"
    }
}

public enum LocationRecommendabilityFilterContract {
    public static let capabilityID = LocationRecommendabilityFilter.capabilityID
    /// Transport/resource bound equal to the largest public `location.grid` result.
    public static let maxCandidateCount = GeographicGridGenerator.contractPointCapCount

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys) == ["suitability"],
              let rows = input["suitability"] as? [Any] else {
            throw LocationRecommendabilityFilterInputError()
        }
        guard rows.count <= maxCandidateCount else {
            throw LocationRecommendabilityFilterInputError(rowCap: maxCandidateCount)
        }
        let statuses = try rows.map { value -> LocationCompareSuitability in
            guard let token = value as? String,
                  let status = LocationCompareSuitability(rawValue: token) else {
                throw LocationRecommendabilityFilterInputError()
            }
            return status
        }
        return [
            "recommendable_input_indices": LocationRecommendabilityFilter
                .recommendableInputIndices(for: statuses),
        ]
    }
}
