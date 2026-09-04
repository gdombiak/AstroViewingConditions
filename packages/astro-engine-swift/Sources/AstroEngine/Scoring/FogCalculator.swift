import Foundation

public struct FogCalculator {
    public static func calculate(from forecast: HourlyForecast) -> FogScore {
        var score = 0
        var factors: [FogScore.FogFactor] = []
        
        // Humidity factor: +0-40 points for RH 80-100%
        // Gradient: RH >= 95% = 40pts, RH 80% = 0pts
        if forecast.humidity >= 80 {
            let humidityScore = Int((Double(forecast.humidity) - 80.0) / 20.0 * 40.0)
            score += max(humidityScore, 0)
            if humidityScore > 0 {
                factors.append(.highHumidity)
            }
        }
        
        // Dew point spread: +0-30 points for spread 0-2C
        // Lower spread = higher fog risk
        if let dewPoint = forecast.dewPoint {
            let spread = forecast.temperature - dewPoint
            if spread < 2.0 {
                let spreadScore = Int((2.0 - spread) / 2.0 * 30.0)
                score += max(spreadScore, 0)
                if spreadScore > 0 {
                    factors.append(.lowTempDewDiff)
                }
            }
        }
        
        // Visibility factor: +0-20 points for visibility 0-1000m
        // Lower visibility = higher fog risk
        if let visibility = forecast.visibility {
            if visibility < 1000 {
                let visibilityScore = Int((1000.0 - visibility) / 1000.0 * 20.0)
                score += max(visibilityScore, 0)
                if visibilityScore > 0 {
                    factors.append(.lowVisibility)
                }
            }
        }
        
        // Low cloud factor: +0-10 points for low clouds 70-100%
        // Higher low clouds = higher fog risk
        if let lowCloud = forecast.lowCloudCover {
            if lowCloud >= 70 {
                let cloudScore = Int((Double(lowCloud) - 70.0) / 30.0 * 10.0)
                score += max(cloudScore, 0)
                if cloudScore > 0 {
                    factors.append(.highLowCloud)
                }
            }
        }
        
        // Wind speed factor: +0-15 points for wind 0-3 m/s
        // Calm winds = higher fog risk
        if forecast.windSpeed < 3.0 {
            let windScore = Int((3.0 - forecast.windSpeed) / 3.0 * 15.0)
            score += max(windScore, 0)
            if windScore > 0 {
                factors.append(.lowWind)
            }
        }
        
        return FogScore(score: score, factors: factors)
    }
    
    public static func calculateCurrent(from forecasts: [HourlyForecast]) -> FogScore {
        guard let current = forecasts.first else {
            return FogScore(score: 0, factors: [])
        }
        return calculate(from: current)
    }
}
