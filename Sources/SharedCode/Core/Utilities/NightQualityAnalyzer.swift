import Foundation
import SunCalc

public struct NightQualityAnalyzer {
    
    private enum Constants {
        static let cloudCoverWeight: Double = 0.55
        static let fogWeight: Double = 0.20
        static let moonWeight: Double = 0.15
        static let windWeight: Double = 0.10
        
        static let cloudCoverThresholds: [(max: Int, score: Double)] = [
            (5, 0.0), (20, 0.5), (40, 1.0), (60, 1.5), (100, 2.0)
        ]
        
        static let fogScoreThresholds: [(max: Int, score: Double)] = [
            (25, 0.0), (50, 0.5), (75, 1.0), (100, 2.0)
        ]
        
        static let moonIlluminationThresholds: [(max: Int, score: Double)] = [
            (10, 0.0), (25, 0.5), (50, 1.0), (100, 2.0)
        ]
        
        static let windSpeedThresholds: [(max: Double, score: Double)] = [
            (3.0, 0.0), (6.0, 0.5), (10.0, 1.0), (100.0, 2.0)
        ]
        
        static let goodRatingThreshold: Double = 1.0
    }
    
    public static func analyzeNight(
        forecasts: [HourlyForecast],
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents?,
        moonInfo: MoonInfo,
        latitude: Double,
        longitude: Double,
        for date: Date,
        calendar: Calendar
    ) -> NightQualityAssessment {
        
        // Filter forecasts to nighttime hours only
        let (nightStart, nightEnd) = NightForecastFilter.calculateNightRange(
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            for: date,
            calendar: calendar
        )
        
        let nightForecasts = forecasts.filter { forecast in
            forecast.time >= nightStart && forecast.time < nightEnd
        }
        
        guard !nightForecasts.isEmpty else {
            return createNoNighttimeDataAssessment(sunEvents: sunEventsToday, moonInfo: moonInfo)
        }
        
        var hourlyRatings: [NightQualityAssessment.HourlyRating] = []
        var totalScore: Double = 0
        
        for forecast in nightForecasts {
            let moonAltitude = calculateMoonAltitude(latitude: latitude, longitude: longitude, at: forecast.time)
            let moonIllumination = calculateMoonIllumination(at: forecast.time)
            
            let fogScore = FogCalculator.calculate(from: forecast)
            let cloudScore = calculateCloudCoverScore(forecast.cloudCover)
            let moonScore = calculateMoonScore(illumination: moonIllumination, altitude: moonAltitude)
            let windScore = calculateWindScore(forecast.windSpeed)
            
            let weightedScore = (
                cloudScore * Constants.cloudCoverWeight +
                Double(fogScore.score) / 50.0 * Constants.fogWeight +
                moonScore * Constants.moonWeight +
                windScore * Constants.windWeight
            )
            
            let hourlyRating = NightQualityAssessment.HourlyRating(
                time: forecast.time,
                score: weightedScore,
                cloudCover: forecast.cloudCover,
                fogScore: fogScore.score,
                moonIllumination: moonIllumination,
                moonAltitude: moonAltitude,
                windSpeed: forecast.windSpeed
            )
            
            hourlyRatings.append(hourlyRating)
            totalScore += weightedScore
        }
        
        let avgScore = totalScore / Double(hourlyRatings.count)
        let rating = determineRating(avgScore)
        
        let avgCloudCover = hourlyRatings.map { $0.cloudCover }.reduce(0, +) / hourlyRatings.count
        let avgFogScore = hourlyRatings.map { $0.fogScore }.reduce(0, +) / hourlyRatings.count
        let avgMoonIllumination = hourlyRatings.map { $0.moonIllumination }.reduce(0, +) / hourlyRatings.count
        let avgWindSpeed = hourlyRatings.map { $0.windSpeed }.reduce(0, +) / Double(hourlyRatings.count)
        
        let details = NightQualityAssessment.Details(
            cloudCoverScore: Double(avgCloudCover),
            fogScoreAvg: Double(avgFogScore),
            moonIlluminationAvg: avgMoonIllumination,
            windSpeedAvg: avgWindSpeed
        )
        
        let (trend, firstHalf, secondHalf) = calculateTrend(hourlyRatings: hourlyRatings)
        
        let summary = generateSummary(rating: rating, avgScore: avgScore, trend: trend)
        
        let bestWindowStart = hourlyRatings.first?.time ?? date
        let bestWindowEnd = hourlyRatings.last?.time ?? date
        
        let bestWindow = calculateBestWindow(hourlyRatings: hourlyRatings, nightStart: bestWindowStart, nightEnd: bestWindowEnd)
        
        return NightQualityAssessment(
            rating: rating,
            summary: summary,
            details: details,
            bestWindow: bestWindow,
            hourlyRatings: hourlyRatings,
            nightStart: bestWindowStart,
            nightEnd: bestWindowEnd,
            trend: trend,
            firstHalfScore: firstHalf,
            secondHalfScore: secondHalf
        )
    }
    
    private static func calculateCloudCoverScore(_ cloudCover: Int) -> Double {
        for threshold in Constants.cloudCoverThresholds {
            if cloudCover <= threshold.max {
                return threshold.score
            }
        }
        return 2.0
    }
    
    private static func calculateFogScore(_ score: Int) -> Double {
        for threshold in Constants.fogScoreThresholds {
            if score <= threshold.max {
                return threshold.score
            }
        }
        return 2.0
    }
    
    private static func calculateMoonScore(illumination: Int, altitude: Double) -> Double {
        // If moon is below horizon (altitude <= 0), it's perfect for stargazing regardless of illumination
        if altitude <= 0 {
            return 0.0
        }
        
        // For moon above horizon, score based on both illumination and altitude
        // Higher altitude = more interference, higher illumination = more interference
        var illuminationScore: Double = 2.0
        for threshold in Constants.moonIlluminationThresholds {
            if illumination <= threshold.max {
                illuminationScore = threshold.score
                break
            }
        }
        
        // Altitude factor: moon at 90° is worst, at 0° is best (but still above horizon)
        // Normalize altitude to 0-1 range (0° -> 0, 90° -> 1)
        let altitudeFactor = min(max(altitude / 90.0, 0.0), 1.0)
        
        // Combine scores: high altitude makes moon interference worse
        return illuminationScore * (0.5 + 0.5 * altitudeFactor)
    }
    
    private static func calculateMoonAltitude(latitude: Double, longitude: Double, at time: Date) -> Double {
        do {
            let position = try MoonPosition.compute()
                .at(latitude, longitude)
                .on(time)
                .execute()
            return position.altitude
        } catch {
            return 0
        }
    }
    
    private static func calculateMoonIllumination(at time: Date) -> Int {
        do {
            let illumination = try MoonIllumination.compute()
                .on(time)
                .execute()
            return Int(illumination.fraction * 100)
        } catch {
            return 0
        }
    }
    
    private static func calculateWindScore(_ windSpeed: Double) -> Double {
        for threshold in Constants.windSpeedThresholds {
            if windSpeed <= threshold.max {
                return threshold.score
            }
        }
        return 2.0
    }
    
    private static func determineRating(_ avgScore: Double) -> NightQualityAssessment.Rating {
        NightQualityAssessment.Rating.from(score: avgScore)
    }
    
    private static func generateSummary(rating: NightQualityAssessment.Rating, avgScore: Double, trend: NightQualityAssessment.Trend) -> String {
        switch rating {
        case .excellent:
            switch trend {
            case .improving: return "Excellent conditions, improving through the night!"
            case .stable: return "Perfect conditions for stargazing this night!"
            case .degrading: return "Excellent early, degrading after midnight."
            }
        case .good:
            switch trend {
            case .improving: return "Good conditions, improving through the night."
            case .stable: return "Good night for observing. Expect clear skies."
            case .degrading: return "Good early, conditions degrade after midnight."
            }
        case .fair:
            switch trend {
            case .improving: return "Fair early, improving after midnight."
            case .stable:
                if avgScore < 1.5 {
                    return "Decent conditions, but some clouds may be present."
                } else {
                    return "Fair conditions. Moon or clouds may interfere somewhat."
                }
            case .degrading: return "Fair early, degrading after midnight."
            }
        case .poor:
            switch trend {
            case .improving: return "Poor early, improving after midnight."
            case .stable: return "Not ideal for stargazing this night."
            case .degrading: return "Fair early, degrading after midnight."
            }
        }
    }
    
    private static func calculateTrend(
        hourlyRatings: [NightQualityAssessment.HourlyRating]
    ) -> (trend: NightQualityAssessment.Trend, firstHalf: Double, secondHalf: Double) {
        guard hourlyRatings.count >= 4 else {
            return (.stable, 0, 0)
        }
        
        let midIndex = hourlyRatings.count / 2
        let firstHalf = hourlyRatings[..<midIndex].map { $0.score }.reduce(0, +) / Double(midIndex)
        let secondHalf = hourlyRatings[midIndex...].map { $0.score }.reduce(0, +) / Double(hourlyRatings.count - midIndex)
        
        let diff = secondHalf - firstHalf
        
        let threshold: Double = 0.3
        let trend: NightQualityAssessment.Trend
        if diff > threshold {
            trend = .degrading
        } else if diff < -threshold {
            trend = .improving
        } else {
            trend = .stable
        }
        
        return (trend, firstHalf, secondHalf)
    }
    
    private static func calculateBestWindow(
        hourlyRatings: [NightQualityAssessment.HourlyRating],
        nightStart: Date,
        nightEnd: Date
    ) -> NightQualityAssessment.TimeWindow? {
        
        guard !hourlyRatings.isEmpty else { return nil }
        
        let goodHours = hourlyRatings.filter { $0.score < Constants.goodRatingThreshold }
        
        if goodHours.isEmpty {
            let best = hourlyRatings.min { $0.score < $1.score }
            if let best = best {
                return NightQualityAssessment.TimeWindow(start: best.time, end: best.time.addingTimeInterval(3600))
            }
            return nil
        }
        
        let goodCount = goodHours.count
        let totalCount = hourlyRatings.count
        let goodRatio = Double(goodCount) / Double(totalCount)
        
        if goodRatio >= 0.5 {
            return NightQualityAssessment.TimeWindow(start: nightStart, end: nightEnd)
        }
        
        var longestWindow: (start: Date, end: Date, length: TimeInterval) = (nightStart, nightStart, 0)
        var currentStart: Date?
        var currentLength: TimeInterval = 0
        
        for rating in hourlyRatings.sorted(by: { $0.time < $1.time }) {
            if rating.score < Constants.goodRatingThreshold {
                if currentStart == nil {
                    currentStart = rating.time
                }
                currentLength += 3600
            } else {
                if let start = currentStart, currentLength > longestWindow.length {
                    let end = start.addingTimeInterval(currentLength)
                    longestWindow = (start, end, currentLength)
                }
                currentStart = nil
                currentLength = 0
            }
        }
        
        if let start = currentStart, currentLength > longestWindow.length {
            let end = start.addingTimeInterval(currentLength)
            longestWindow = (start, end, currentLength)
        }
        
        if longestWindow.length > 0 {
            return NightQualityAssessment.TimeWindow(start: longestWindow.start, end: longestWindow.end)
        }
        
        return nil
    }
    
    private static func createNoNighttimeDataAssessment(
        sunEvents: SunEvents,
        moonInfo: MoonInfo
    ) -> NightQualityAssessment {
        return NightQualityAssessment(
            rating: .poor,
            summary: "No nighttime data available for analysis.",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 0,
                fogScoreAvg: 0,
                moonIlluminationAvg: moonInfo.illumination,
                windSpeedAvg: 0
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: sunEvents.astronomicalNightStart,
            nightEnd: sunEvents.astronomicalNightEnd,
            trend: .stable,
            firstHalfScore: nil,
            secondHalfScore: nil
        )
    }
}
