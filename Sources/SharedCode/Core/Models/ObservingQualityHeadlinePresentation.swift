import Foundation

/// Display band for the **headline** observing-quality score (0…100).
///
/// Uses the same thresholds as the dashboard score color. Distinct from
/// `NightQualityAssessment.Rating`, which describes weather/Moon night quality
/// on a different internal scale.
public enum ObservingQualityScoreBand: Sendable, Equatable {
    case excellent  // 80...100
    case good       // 60..<80
    case fair       // 40..<60
    case poor       // ..<40

    public static func from(score: Int) -> Self {
        switch score {
        case 80...100: return .excellent
        case 60..<80: return .good
        case 40..<60: return .fair
        default: return .poor
        }
    }

    public var accessibilityAdjective: String {
        switch self {
        case .excellent: return "excellent"
        case .good: return "good"
        case .fair: return "fair"
        case .poor: return "poor"
        }
    }

    /// Public headline verdict/category label (shared by dashboard widgets).
    public var shortLabel: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    /// Tone for model-level widget presentation (e.g. Three-Night Outlook).
    public var widgetTargetScoreTone: WidgetTargetScoreTone {
        switch self {
        case .excellent: return .positive
        case .good: return .informational
        case .fair: return .caution
        case .poor: return .negative
        }
    }
}

/// Shared mapping from a 0…100 headline score (night or OQ) to public category presentation.
public enum CrossSurfaceHeadlineScorePresentation: Sendable {
    public static func band(for score: Int) -> ObservingQualityScoreBand {
        ObservingQualityScoreBand.from(score: score)
    }

    public static func verdict(for score: Int) -> String {
        ObservingQualityScoreBand.from(score: score).shortLabel
    }

    public static func widgetTargetScoreTone(for score: Int) -> WidgetTargetScoreTone {
        ObservingQualityScoreBand.from(score: score).widgetTargetScoreTone
    }
}

/// Pure presentation inputs for the dashboard headline (number + band + a11y).
///
/// Condition-specific copy (weather summary, Moon, clouds, early/late half scores)
/// remains on `NightQualityAssessment` and is not derived here.
public struct ObservingQualityHeadlinePresentation: Sendable, Equatable {
    public let score: Int
    public let band: ObservingQualityScoreBand
    public let accessibilityLabel: String

    public init(score: Int) {
        let clamped = min(100, max(0, score))
        self.score = clamped
        self.band = ObservingQualityScoreBand.from(score: clamped)
        self.accessibilityLabel =
            "Observing quality score \(clamped) out of 100, \(band.accessibilityAdjective)"
    }

    public init(assessment: ObservingQualityAssessment) {
        self.init(score: assessment.score)
    }
}
