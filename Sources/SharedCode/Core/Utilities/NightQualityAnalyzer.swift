import Foundation
import SunCalc

public struct NightQualityAnalyzer {
    final class MoonCalculationCache: @unchecked Sendable {
        private struct MoonAltitudeKey: Hashable {
            let latitude: Double
            let longitude: Double
            let time: Date
        }
        
        private let lock = NSLock()
        private var moonAltitudes: [MoonAltitudeKey: Double] = [:]
        private var moonIlluminations: [Date: Int] = [:]
        
        func moonAltitude(latitude: Double, longitude: Double, at time: Date) -> Double {
            let key = MoonAltitudeKey(latitude: latitude, longitude: longitude, time: time)
            
            do {
                lock.lock()
                defer { lock.unlock() }
                if let cachedAltitude = moonAltitudes[key] {
                    return cachedAltitude
                }
            }
            
            let altitude = NightQualityAnalyzer.calculateMoonAltitude(
                latitude: latitude,
                longitude: longitude,
                at: time
            )
            
            do {
                lock.lock()
                defer { lock.unlock() }
                moonAltitudes[key] = altitude
            }
            
            return altitude
        }
        
        func moonIllumination(at time: Date) -> Int {
            do {
                lock.lock()
                defer { lock.unlock() }
                if let cachedIllumination = moonIlluminations[time] {
                    return cachedIllumination
                }
            }
            
            let illumination = NightQualityAnalyzer.calculateMoonIllumination(at: time)
            
            do {
                lock.lock()
                defer { lock.unlock() }
                moonIlluminations[time] = illumination
            }
            
            return illumination
        }
    }
    
    private enum Constants {
        static let cloudCoverWeight: Double = 0.55
        static let fogWeight: Double = 0.20
        static let moonWeight: Double = 0.15
        static let windWeight: Double = 0.10
        
        static let cloudCoverThresholds: [(max: Int, score: Double)] = [
            (5, 0.0), (20, 0.5), (40, 1.0), (60, 1.5), (100, 2.0)
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
        analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: latitude,
            longitude: longitude,
            for: date,
            calendar: calendar,
            moonCalculationCache: MoonCalculationCache()
        )
    }
    
    public static func analyzeConditions(
        _ conditions: ViewingConditions,
        dayOffset: Int = 0,
        referenceDate: Date = Date()
    ) -> NightQualityAssessment? {
        guard let firstForecastTime = conditions.hourlyForecasts.first else { return nil }
        
        let timeZone = conditions.timeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? LocationTimeZoneResolver.approximate(longitude: conditions.location.longitude)
        let calendar = LocationTimeZoneResolver.calendar(for: timeZone)
        let firstForecastDay = calendar.startOfDay(for: firstForecastTime.time)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: referenceDay) ?? referenceDay
        let dayIndex = calendar.dateComponents([.day], from: firstForecastDay, to: targetDay).day ?? dayOffset
        
        guard dayIndex >= 0,
              dayIndex < conditions.dailySunEvents.count,
              dayIndex < conditions.dailyMoonInfo.count else {
            return nil
        }
        
        let startOfSelectedDay = calendar.date(byAdding: .day, value: dayIndex, to: firstForecastDay) ?? targetDay
        let endOfFollowingDay = calendar.date(byAdding: .day, value: 3, to: startOfSelectedDay) ?? startOfSelectedDay
        let forecasts = conditions.hourlyForecasts.filter { forecast in
            forecast.time >= startOfSelectedDay && forecast.time < endOfFollowingDay
        }
        
        let sunEventsToday = conditions.dailySunEvents[dayIndex]
        let sunEventsTomorrowIndex = dayIndex + 1
        let sunEventsTomorrow = sunEventsTomorrowIndex < conditions.dailySunEvents.count
            ? conditions.dailySunEvents[sunEventsTomorrowIndex]
            : nil
        let moonInfo = conditions.dailyMoonInfo[dayIndex]
        
        return analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: conditions.location.latitude,
            longitude: conditions.location.longitude,
            for: startOfSelectedDay,
            calendar: calendar
        )
    }
    
    static func analyzeNight(
        forecasts: [HourlyForecast],
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents?,
        moonInfo: MoonInfo,
        latitude: Double,
        longitude: Double,
        for date: Date,
        calendar: Calendar,
        moonCalculationCache: MoonCalculationCache
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
        
        for (index, forecast) in nightForecasts.enumerated() {
            let moonAltitude = moonCalculationCache.moonAltitude(
                latitude: latitude,
                longitude: longitude,
                at: forecast.time
            )
            let moonIllumination = moonCalculationCache.moonIllumination(at: forecast.time)
            
            let fogScore = FogCalculator.calculate(from: forecast)
            let cloudScore = calculateCloudCoverScore(forecast.cloudCover)
            let seeingScore = SeeingCalculator.penalty(
                currentTemperature: forecast.temperature,
                previousTemperature: index > 0 ? nightForecasts[index - 1].temperature : nil,
                windSpeed200hPa: forecast.windSpeed200hPa
            )
            let transparencyScore = TransparencyCalculator.penalty(
                totalCloudCover: forecast.cloudCover,
                lowCloudCover: forecast.lowCloudCover,
                midCloudCover: forecast.midCloudCover,
                highCloudCover: forecast.highCloudCover,
                visibilityMeters: forecast.visibility
            )
            let hasTransparencyData =
                forecast.lowCloudCover != nil &&
                forecast.midCloudCover != nil &&
                forecast.highCloudCover != nil
            let moonScore = calculateMoonScore(illumination: moonIllumination, altitude: moonAltitude)
            let windScore = calculateWindScore(forecast.windSpeed)
            let fogPenalty = Double(fogScore.score) / 50.0
            let weightedScore: Double

            switch (hasTransparencyData ? transparencyScore : nil, seeingScore) {
            case let (.some(transparency), .some(seeing)):
                weightedScore = transparency * 0.40 + seeing * 0.20 + fogPenalty * 0.15 + moonScore * 0.15 + windScore * 0.10
            case let (.some(transparency), nil):
                weightedScore = transparency * 0.50 + fogPenalty * 0.20 + moonScore * 0.20 + windScore * 0.10
            case let (nil, .some(seeing)):
                weightedScore = cloudScore * 0.40 + seeing * 0.20 + fogPenalty * 0.15 + moonScore * 0.15 + windScore * 0.10
            case (nil, nil):
                weightedScore = cloudScore * Constants.cloudCoverWeight + fogPenalty * Constants.fogWeight + moonScore * Constants.moonWeight + windScore * Constants.windWeight
            }
            
            let hourlyRating = NightQualityAssessment.HourlyRating(
                time: forecast.time,
                score: weightedScore,
                cloudCover: forecast.cloudCover,
                fogScore: fogScore.score,
                moonIllumination: moonIllumination,
                moonAltitude: moonAltitude,
                windSpeed: forecast.windSpeed,
                seeingScore: seeingScore,
                transparencyScore: hasTransparencyData ? transparencyScore : nil
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
        let seeingScores = hourlyRatings.compactMap(\.seeingScore)
        let transparencyScores = hourlyRatings.compactMap(\.transparencyScore)
        
        let details = NightQualityAssessment.Details(
            cloudCoverScore: Double(avgCloudCover),
            fogScoreAvg: Double(avgFogScore),
            moonIlluminationAvg: avgMoonIllumination,
            windSpeedAvg: avgWindSpeed,
            seeingScoreAvg: seeingScores.isEmpty ? nil : seeingScores.reduce(0, +) / Double(seeingScores.count),
            transparencyScoreAvg: transparencyScores.isEmpty ? nil : transparencyScores.reduce(0, +) / Double(transparencyScores.count)
        )
        
        let (trend, firstHalf, secondHalf) = calculateTrend(hourlyRatings: hourlyRatings)
        
        let summary = generateSummary(
            rating: rating,
            avgScore: avgScore,
            trend: trend,
            averageCloudCover: avgCloudCover,
            seeingScoreAvg: details.seeingScoreAvg
        )
        
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
    
    private static func generateSummary(
        rating: NightQualityAssessment.Rating,
        avgScore: Double,
        trend: NightQualityAssessment.Trend,
        averageCloudCover: Int,
        seeingScoreAvg: Double?
    ) -> String {
        let seeingWarning = seeingScoreAvg.map { NightQualityAssessment.Rating.from(score: $0) == .poor } == true
            ? " Poor seeing may limit fine detail."
            : ""

        if averageCloudCover >= 80 {
            switch trend {
            case .improving:
                return "Cloudy early, improving through the night." + seeingWarning
            case .stable:
                return "Clouds are likely to block the view." + seeingWarning
            case .degrading:
                return "Cloud cover worsens through the night." + seeingWarning
            }
        }

        let hasClearSkies = averageCloudCover <= 20

        switch rating {
        case .excellent:
            if hasClearSkies {
                switch trend {
                case .improving: return "Excellent conditions, improving through the night!" + seeingWarning
                case .stable: return "Perfect conditions for stargazing this night!" + seeingWarning
                case .degrading: return "Excellent early, degrading after midnight." + seeingWarning
                }
            }

            switch trend {
            case .improving: return "Excellent overall conditions, with clouds improving through the night." + seeingWarning
            case .stable: return "Excellent overall conditions, with some cloud cover." + seeingWarning
            case .degrading: return "Excellent overall conditions early, with increasing cloud cover later." + seeingWarning
            }
        case .good:
            if hasClearSkies {
                switch trend {
                case .improving: return "Good conditions, improving through the night." + seeingWarning
                case .stable: return "Good night for observing. Expect clear skies." + seeingWarning
                case .degrading: return "Good early, conditions degrade after midnight." + seeingWarning
                }
            }

            switch trend {
            case .improving: return "Good overall conditions, with cloud cover improving." + seeingWarning
            case .stable: return "Good overall conditions, but some clouds may affect the view." + seeingWarning
            case .degrading: return "Good conditions early, with cloud cover increasing later." + seeingWarning
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
            case .degrading: return "Poor early, degrading after midnight."
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
