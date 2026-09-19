import Foundation

public struct FogCalculator {
    public static func calculate(from forecast: HourlyForecast) -> FogScore {
        calculate(from: forecast, calibration: EngineCalibration.current.fog)
    }

    public static func calculate(from forecast: HourlyForecast, calibration: FogCalibration) -> FogScore {
        var score = 0
        var factors: [FogScore.FogFactor] = []
        
        // Humidity factor: +0-40 points for RH 80-100%
        // Gradient: RH >= 95% = 40pts, RH 80% = 0pts
        if forecast.humidity >= calibration.humidity.minPercent {
            let humidityScore = Int(
                (Double(forecast.humidity) - Double(calibration.humidity.minPercent))
                    / calibration.humidity.spanPercent
                    * calibration.humidity.maxPoints
            )
            score += max(humidityScore, 0)
            if humidityScore > 0 {
                factors.append(.highHumidity)
            }
        }
        
        // Dew point spread: +0-30 points for spread 0-2C
        // Lower spread = higher fog risk
        if let dewPoint = forecast.dewPoint {
            let spread = forecast.temperature - dewPoint
            if spread < calibration.dewSpread.maxCelsius {
                let spreadScore = Int(
                    (calibration.dewSpread.maxCelsius - spread)
                        / calibration.dewSpread.maxCelsius
                        * calibration.dewSpread.maxPoints
                )
                score += max(spreadScore, 0)
                if spreadScore > 0 {
                    factors.append(.lowTempDewDiff)
                }
            }
        }
        
        // Visibility factor: +0-20 points for visibility 0-1000m
        // Lower visibility = higher fog risk
        if let visibility = forecast.visibility {
            if visibility < calibration.visibility.maxMeters {
                let visibilityScore = Int(
                    (calibration.visibility.maxMeters - visibility)
                        / calibration.visibility.maxMeters
                        * calibration.visibility.maxPoints
                )
                score += max(visibilityScore, 0)
                if visibilityScore > 0 {
                    factors.append(.lowVisibility)
                }
            }
        }
        
        // Low cloud factor: +0-10 points for low clouds 70-100%
        // Higher low clouds = higher fog risk
        if let lowCloud = forecast.lowCloudCover {
            if lowCloud >= calibration.lowCloud.minPercent {
                let cloudScore = Int(
                    (Double(lowCloud) - Double(calibration.lowCloud.minPercent))
                        / calibration.lowCloud.spanPercent
                        * calibration.lowCloud.maxPoints
                )
                score += max(cloudScore, 0)
                if cloudScore > 0 {
                    factors.append(.highLowCloud)
                }
            }
        }
        
        // Wind speed factor: +0-15 points for wind 0-3 m/s
        // Calm winds = higher fog risk
        if forecast.windSpeed < calibration.wind.maxMetersPerSecond {
            let windScore = Int(
                (calibration.wind.maxMetersPerSecond - forecast.windSpeed)
                    / calibration.wind.maxMetersPerSecond
                    * calibration.wind.maxPoints
            )
            score += max(windScore, 0)
            if windScore > 0 {
                factors.append(.lowWind)
            }
        }
        
        return FogScore(score: score, factors: factors)
    }
    
    public static func calculateCurrent(from forecasts: [HourlyForecast]) -> FogScore {
        calculateCurrent(from: forecasts, calibration: EngineCalibration.current.fog)
    }

    public static func calculateCurrent(
        from forecasts: [HourlyForecast],
        calibration: FogCalibration
    ) -> FogScore {
        guard let current = forecasts.first else {
            return FogScore(score: 0, factors: [])
        }
        return calculate(from: current, calibration: calibration)
    }
}
