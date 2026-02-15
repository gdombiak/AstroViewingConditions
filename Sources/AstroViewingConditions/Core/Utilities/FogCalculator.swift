import Foundation

public struct FogCalculator {
    public static func calculate(from forecast: HourlyForecast) -> FogScore {
        var percentage = 0
        var factors: [FogScore.FogFactor] = []
        
        // +40% if RH > 95%
        if forecast.humidity > 95 {
            percentage += 40
            factors.append(.highHumidity)
        }
        
        // +30% if (temp - dewpoint) < 1°C
        if let dewPoint = forecast.dewPoint,
           (forecast.temperature - dewPoint) < 1.0 {
            percentage += 30
            factors.append(.lowTempDewDiff)
        }
        
        // +20% if visibility < 1000m
        if let visibility = forecast.visibility,
           visibility < 1000 {
            percentage += 20
            factors.append(.lowVisibility)
        }
        
        // +10% if low cloud > 80%
        if let lowCloud = forecast.lowCloudCover,
           lowCloud > 80 {
            percentage += 10
            factors.append(.highLowCloud)
        }
        
        return FogScore(percentage: percentage, factors: factors)
    }
    
    /// Calculate fog score for current conditions (first hourly forecast)
    public static func calculateCurrent(from forecasts: [HourlyForecast]) -> FogScore {
        guard let current = forecasts.first else {
            return FogScore(percentage: 0, factors: [])
        }
        return calculate(from: current)
    }
}
