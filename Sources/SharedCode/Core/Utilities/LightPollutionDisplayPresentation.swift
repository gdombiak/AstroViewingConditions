import Foundation

/// Pollution-intensity category for modeled zenith sky brightness (mag/arcsec²).
///
/// Lower mag/arcsec² → more light pollution. Boundaries are inclusive on the lower
/// edge of each band (except Very high, which is exclusive of 17.5).
public enum LightPollutionIntensityCategory: String, Sendable, Equatable, CaseIterable {
    case veryHigh = "Very high"
    case high = "High"
    case moderate = "Moderate"
    case low = "Low"
    case veryLow = "Very low"

    /// Deterministic category for a **validated** brightness in the plausible range.
    public static func category(forValidatedBrightness brightness: Double) -> LightPollutionIntensityCategory {
        switch brightness {
        case ..<17.5:
            return .veryHigh
        case 17.5..<19.5:
            return .high
        case 19.5..<20.5:
            return .moderate
        case 20.5..<21.3:
            return .low
        default:
            return .veryLow
        }
    }
}

/// Resolved display state for a Locations-screen light-pollution row.
public enum LightPollutionRowDisplayState: Sendable, Equatable {
    /// Lookup not finished for this identity+coordinate key.
    case unresolved
    case available(LightPollutionDisplayPresentation)
    case unavailable

    public var showsRow: Bool {
        switch self {
        case .unresolved:
            return false
        case .available, .unavailable:
            return true
        }
    }
}

/// Deterministic presentation of a modeled light-pollution estimate (no atlas I/O).
public struct LightPollutionDisplayPresentation: Sendable, Equatable {
    public let category: LightPollutionIntensityCategory
    /// Validated brightness (mag/arcsec²).
    public let brightness: Double
    /// One-decimal scientific value, e.g. `18.5`.
    public let formattedBrightness: String
    /// Combined value text: `High · 18.5 mag/arcsec²`
    public let displayValue: String
    /// VoiceOver wording without visual separator or unit abbreviation.
    public let accessibilityLabel: String

    public static let metricLabel = "Light pollution"
    public static let coordinatesLabel = "Coordinates"
    public static let listFooterExplanation =
        "Higher mag/arcsec² values indicate darker skies. Modeled estimates may differ from local conditions."
    public static let unavailableValueText = "Unavailable"
    public static let unavailableAccessibilityLabel = "Light pollution unavailable"

    /// Builds presentation only when `brightness` is finite and in the canonical plausible range.
    public static func available(brightness: Double) -> LightPollutionDisplayPresentation? {
        guard ModeledZenithBrightnessValidity.isBrightnessInPlausibleRange(brightness) else {
            return nil
        }
        let category = LightPollutionIntensityCategory.category(forValidatedBrightness: brightness)
        let formatted = formatOneDecimal(brightness)
        let displayValue = "\(category.rawValue) · \(formatted) mag/arcsec²"
        let accessibilityLabel =
            "Light pollution, \(category.rawValue), modeled sky brightness \(formatted) magnitudes per square arcsecond"
        return LightPollutionDisplayPresentation(
            category: category,
            brightness: brightness,
            formattedBrightness: formatted,
            displayValue: displayValue,
            accessibilityLabel: accessibilityLabel
        )
    }

    /// Resolves raw provider output to a row state (never invents pristine darkness).
    public static func resolve(rawBrightness: Double?) -> LightPollutionRowDisplayState {
        guard let rawBrightness else { return .unavailable }
        guard let presentation = available(brightness: rawBrightness) else {
            return .unavailable
        }
        return .available(presentation)
    }

    /// Locale-stable one-decimal formatting (half-up via Foundation rounding).
    public static func formatOneDecimal(_ brightness: Double) -> String {
        let rounded = (brightness * 10).rounded() / 10
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: rounded)) ?? String(format: "%.1f", rounded)
    }
}
