import Foundation

/// Shared domain rules used while analyzing a night's observing conditions.
/// These rules intentionally contain no platform presentation concerns.
public enum NightQualityAnalysisRules {
    /// Production presentation alias for the authoritative
    /// ``CloudTimingClassifier/Classification`` verdict. `summaryText` is iOS
    /// copy and is deliberately **not** part of the public parity contract.
    public enum CloudTiming: Sendable, Equatable {
        case none
        case earlyHeavy
        case lateHeavy
        case intermittentHeavy

        init(_ classification: CloudTimingClassifier.Classification) {
            switch classification {
            case .none: self = .none
            case .earlyHeavy: self = .earlyHeavy
            case .lateHeavy: self = .lateHeavy
            case .intermittentHeavy: self = .intermittentHeavy
            }
        }

        var summaryText: String? {
            switch self {
            case .none: return nil
            case .earlyHeavy: return "Heavy clouds early, with better conditions later."
            case .lateHeavy: return "Decent early, with heavy clouds expected later tonight."
            case .intermittentHeavy: return "A period of heavy clouds may interrupt otherwise better conditions."
            }
        }
    }

    public static func moonPenalty(illumination: Int, altitude: Double) -> Double {
        moonPenalty(
            illumination: illumination,
            altitude: altitude,
            calibration: EngineCalibration.current.nightQuality
        )
    }

    public static func moonPenalty(
        illumination: Int,
        altitude: Double,
        calibration: NightQualityCalibration
    ) -> Double {
        guard altitude > 0 else { return 0 }

        let illuminationScore = CalibrationTables.score(
            for: illumination,
            in: calibration.moonIlluminationBuckets
        )
        let altitudeFactor = min(max(altitude / 90, 0), 1)
        return illuminationScore * (0.5 + 0.5 * altitudeFactor)
    }

    public static func windPenalty(_ windSpeed: Double) -> Double {
        windPenalty(windSpeed, calibration: EngineCalibration.current.nightQuality)
    }

    public static func windPenalty(
        _ windSpeed: Double,
        calibration: NightQualityCalibration
    ) -> Double {
        CalibrationTables.score(for: windSpeed, in: calibration.windPenaltyTable)
    }

    /// Delegates to the shared ``CloudTimingClassifier``. The hourly rows carry
    /// only the three facts the classification reads.
    public static func cloudTiming(
        in hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> CloudTiming {
        CloudTiming(
            CloudTimingClassifier.classify(
                hourlyRatings.map {
                    CloudTimingClassifier.HourlyRow(
                        time: $0.time,
                        score: $0.score,
                        cloudCover: $0.cloudCover
                    )
                }
            )
        )
    }
}
