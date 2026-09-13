import Foundation
import CoreFoundation

/// Selects whether the production night summary may lead with cloud timing.
/// English wording remains presentation.
public enum CloudAdvisorySelector {
    public static let capabilityID = "night_conditions.select_cloud_advisory"

    public struct Selection: Sendable, Equatable {
        public let wholeNightHeavy: Bool
        public let advisory: CloudTimingClassifier.Classification?
    }

    public static func select(
        cloudTiming: CloudTimingClassifier.Classification,
        rating: NightQualityAssessment.Rating,
        averageCloudCover: Double
    ) -> Selection {
        let heavy = averageCloudCover >= Double(
            EngineCalibration.current.nightQuality.cloudFloor.cloudCoverMin
        )
        return Selection(
            wholeNightHeavy: heavy,
            advisory: heavy || rating == .poor || cloudTiming == .none ? nil : cloudTiming
        )
    }
}

public struct CloudAdvisoryInputError: Error, Sendable {
    public let code = "validation"
    public let message = "invalid night_conditions.select_cloud_advisory input"
}

/// Strict JSON transport for the semantic selector.
public enum CloudAdvisoryContract {
    public static let capabilityID = CloudAdvisorySelector.capabilityID

    public static func evaluate(_ input: [String: Any]) throws -> [String: Any] {
        guard Set(input.keys) == ["cloud_timing", "rating", "average_cloud_cover"],
              let timingText = input["cloud_timing"] as? String,
              let timing = CloudTimingClassifier.Classification(rawValue: timingText),
              let ratingText = input["rating"] as? String,
              let rating = NightQualityAssessment.Rating(rawValue: ratingText),
              let number = input["average_cloud_cover"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              (0...100).contains(number.doubleValue) else {
            throw CloudAdvisoryInputError()
        }
        let advisory = CloudAdvisorySelector.select(
            cloudTiming: timing,
            rating: rating,
            averageCloudCover: number.doubleValue
        ).advisory
        return ["cloud_advisory": advisory.map { $0.rawValue as Any } ?? NSNull()]
    }
}
