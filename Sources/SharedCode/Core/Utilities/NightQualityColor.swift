import SwiftUI

extension NightQualityAssessment.Rating {
    public var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

extension NightQualityAssessment {
    public func scoreColor(for score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    public var scoreColor: Color {
        scoreColor(for: calculatedScore)
    }
    
    public var ratingColor: Color {
        rating.color
    }
    
    public func scoreToColor(_ score: Double) -> Color {
        if score < 0.3 { return .green }
        else if score < 0.7 { return .blue }
        else if score < 1.0 { return .orange }
        else { return .red }
    }
    
    public func scoreLabel(_ score: Double) -> String {
        if score < 0.3 { return "Excellent" }
        else if score < 0.7 { return "Good" }
        else if score < 1.0 { return "Fair" }
        else { return "Poor" }
    }
    
    public func cloudColor(_ coverage: Double) -> Color {
        switch Int(coverage) {
        case 0..<20: return .green
        case 20..<50: return .blue
        case 50..<80: return .orange
        default: return .red
        }
    }
    
    public func moonColor(_ illumination: Int) -> Color {
        switch illumination {
        case 0..<25: return .green
        case 25..<50: return .blue
        case 50..<75: return .orange
        default: return .red
        }
    }
    
    public func windColor(_ speed: Double) -> Color {
        switch speed {
        case 0..<5: return .green
        case 5..<10: return .blue
        case 10..<15: return .orange
        default: return .red
        }
    }
    
    public func fogColor(_ score: Int) -> Color {
        switch score {
        case 0..<25: return .green
        case 25..<50: return .blue
        case 50..<75: return .orange
        default: return .red
        }
    }
}

public enum ConditionColorPalette {
    public static func astronomyRiskBackground(for percentage: Int) -> Color {
        let coverage = Double(min(max(percentage, 0), 100)) / 100.0
        let red = 10 + (230 * coverage)
        let green = 20 + (220 * coverage)
        let blue = 80 + (155 * coverage)
        return Color(red: red / 255, green: green / 255, blue: blue / 255)
    }
    
    public static func astronomyRiskText(for percentage: Int) -> Color {
        percentage > 60 ? .black : .white
    }
}
