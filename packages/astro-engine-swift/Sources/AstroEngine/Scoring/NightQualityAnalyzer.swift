import Foundation

public struct NightWindow: Sendable, Hashable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public enum NightConditionsAnalysisError: Error, Equatable, Sendable {
    case missingMoonTimestamp(Date)
    case invalidClock
    case invalidTimeZone

    public var message: String {
        switch self {
        case .missingMoonTimestamp(let time):
            return "moon_series missing timestamp \(formatUTCTimestamp(time))"
        case .invalidClock:
            return "clock is required"
        case .invalidTimeZone:
            return "time_zone is required"
        }
    }
}

/// Top-level `night_conditions.analyze` envelope fields. Clipping still uses
/// `injected.night_window` only; clock and IANA time zone are required identity.
public enum NightConditionsEnvelope {
    public static func requireClockAndTimeZone(_ document: [String: Any]) throws {
        guard parseUTCInstant(document["clock"]) != nil else {
            throw NightConditionsAnalysisError.invalidClock
        }
        guard let identifier = document["time_zone"] as? String, !identifier.isEmpty else {
            throw NightConditionsAnalysisError.invalidTimeZone
        }
        guard TimeZone(identifier: identifier) != nil else {
            throw NightConditionsAnalysisError.invalidTimeZone
        }
    }

    /// ISO-8601 UTC instant (`YYYY-MM-DDTHH:MM:SSZ`). Offset forms are rejected.
    public static func parseUTCInstant(_ value: Any?) -> Date? {
        guard let text = value as? String, text.hasSuffix("Z") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: text)
    }
}

public struct NightQualityAnalyzer {
    public final class MoonCalculationCache: MoonSampling, @unchecked Sendable {
        private struct MoonAltitudeKey: Hashable {
            let latitude: Double
            let longitude: Double
            let time: Date
        }

        private let lock = NSLock()
        private var moonAltitudes: [MoonAltitudeKey: Double] = [:]
        private var moonIlluminations: [Date: Int] = [:]
        private let sampler: any MoonSampling

        public init(sampler: any MoonSampling = SunCalcMoonSampler()) {
            self.sampler = sampler
        }

        public func moonAltitude(latitude: Double, longitude: Double, at time: Date) -> Double {
            let key = MoonAltitudeKey(latitude: latitude, longitude: longitude, time: time)

            do {
                lock.lock()
                defer { lock.unlock() }
                if let cachedAltitude = moonAltitudes[key] {
                    return cachedAltitude
                }
            }

            let altitude: Double
            do {
                altitude = try sampler.position(latitude: latitude, longitude: longitude, at: time).altitude
            } catch {
                altitude = 0
            }

            do {
                lock.lock()
                defer { lock.unlock() }
                moonAltitudes[key] = altitude
            }

            return altitude
        }

        public func moonIllumination(at time: Date) -> Int {
            do {
                lock.lock()
                defer { lock.unlock() }
                if let cachedIllumination = moonIlluminations[time] {
                    return cachedIllumination
                }
            }

            let illumination: Int
            do {
                illumination = try sampler.illumination(at: time).illuminationPercent
            } catch {
                illumination = 0
            }

            do {
                lock.lock()
                defer { lock.unlock() }
                moonIlluminations[time] = illumination
            }

            return illumination
        }

        public func illumination(at time: Date) throws -> MoonIlluminationSample {
            let percent = moonIllumination(at: time)
            return MoonIlluminationSample(fraction: Double(percent) / 100.0, phaseDegrees: 0)
        }

        public func position(
            latitude: Double,
            longitude: Double,
            at time: Date
        ) throws -> MoonHorizontalCoordinates {
            MoonHorizontalCoordinates(
                altitude: moonAltitude(latitude: latitude, longitude: longitude, at: time),
                azimuth: 0
            )
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

        static let goodRatingThreshold: Double = 1.0
    }

    /// Production analysis: night window from sun events, moon from an injected sampler.
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

    public static func analyzeNight(
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
        let (nightStart, nightEnd) = NightForecastFilter.calculateNightRange(
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            for: date,
            calendar: calendar
        )

        let nightForecasts = forecasts
            .filter { forecast in
                forecast.time >= nightStart && forecast.time < nightEnd
            }
            .sorted { $0.time < $1.time }

        return assessNightForecasts(
            nightForecasts,
            emptyNightStart: sunEventsToday.astronomicalNightStart,
            emptyNightEnd: sunEventsToday.astronomicalNightEnd,
            emptyMoonIllumination: moonInfo.illumination,
            moonAltitude: { forecast in
                moonCalculationCache.moonAltitude(
                    latitude: latitude,
                    longitude: longitude,
                    at: forecast.time
                )
            },
            moonIllumination: { forecast in
                moonCalculationCache.moonIllumination(at: forecast.time)
            }
        )
    }

    /// Deterministic contract analysis: injected window + required 1:1 moon series.
    /// Does not call SunCalc or `NightForecastFilter`.
    public static func analyzeNight(
        forecasts: [HourlyForecast],
        nightWindow: NightWindow,
        moonSeries: [MoonSample]
    ) throws -> NightQualityAssessment {
        let nightForecasts = forecasts
            .filter { forecast in
                forecast.time >= nightWindow.start && forecast.time < nightWindow.end
            }
            .sorted { $0.time < $1.time }

        var moonByTime: [Date: MoonSample] = [:]
        for sample in moonSeries {
            if moonByTime[sample.time] == nil {
                moonByTime[sample.time] = sample
            }
        }

        return try assessNightForecasts(
            nightForecasts,
            emptyNightStart: nightWindow.start,
            emptyNightEnd: nightWindow.end,
            emptyMoonIllumination: 0,
            moonAltitude: { forecast in
                guard let sample = moonByTime[forecast.time] else {
                    throw NightConditionsAnalysisError.missingMoonTimestamp(forecast.time)
                }
                return sample.altitudeDegrees
            },
            moonIllumination: { forecast in
                guard let sample = moonByTime[forecast.time] else {
                    throw NightConditionsAnalysisError.missingMoonTimestamp(forecast.time)
                }
                return sample.illuminationPercent
            }
        )
    }

    private static func assessNightForecasts(
        _ nightForecasts: [HourlyForecast],
        emptyNightStart: Date,
        emptyNightEnd: Date,
        emptyMoonIllumination: Int,
        moonAltitude: (HourlyForecast) throws -> Double,
        moonIllumination: (HourlyForecast) throws -> Int
    ) rethrows -> NightQualityAssessment {
        guard !nightForecasts.isEmpty else {
            return createNoNighttimeDataAssessment(
                nightStart: emptyNightStart,
                nightEnd: emptyNightEnd,
                moonIllumination: emptyMoonIllumination
            )
        }

        var hourlyRatings: [NightQualityAssessment.HourlyRating] = []
        var totalScore: Double = 0

        for (index, forecast) in nightForecasts.enumerated() {
            let moonAltitudeValue = try moonAltitude(forecast)
            let moonIlluminationValue = try moonIllumination(forecast)

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
            let moonScore = NightQualityAnalysisRules.moonPenalty(
                illumination: moonIlluminationValue,
                altitude: moonAltitudeValue
            )
            let windScore = NightQualityAnalysisRules.windPenalty(forecast.windSpeed)
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

            let finalScore: Double
            if forecast.cloudCover >= 80 {
                finalScore = max(
                    weightedScore,
                    NightQualityAssessment.Rating.Thresholds.fairMax
                )
            } else {
                finalScore = weightedScore
            }

            let hourlyRating = NightQualityAssessment.HourlyRating(
                time: forecast.time,
                score: finalScore,
                cloudCover: forecast.cloudCover,
                fogScore: fogScore.score,
                moonIllumination: moonIlluminationValue,
                moonAltitude: moonAltitudeValue,
                windSpeed: forecast.windSpeed,
                seeingScore: seeingScore,
                transparencyScore: hasTransparencyData ? transparencyScore : nil
            )

            hourlyRatings.append(hourlyRating)
            totalScore += finalScore
        }

        let rawAverageScore = totalScore / Double(hourlyRatings.count)
        let avgCloudCover =
            Double(hourlyRatings.map(\.cloudCover).reduce(0, +))
            / Double(hourlyRatings.count)

        let avgScore: Double
        if avgCloudCover >= 80 {
            avgScore = max(rawAverageScore, NightQualityAssessment.Rating.Thresholds.fairMax)
        } else {
            avgScore = rawAverageScore
        }
        let rating = determineRating(avgScore)
        let avgFogScore = hourlyRatings.map { $0.fogScore }.reduce(0, +) / hourlyRatings.count
        let avgMoonIllumination = hourlyRatings.map { $0.moonIllumination }.reduce(0, +) / hourlyRatings.count
        let avgWindSpeed = hourlyRatings.map { $0.windSpeed }.reduce(0, +) / Double(hourlyRatings.count)
        let seeingScores = hourlyRatings.compactMap(\.seeingScore)
        let transparencyScores = hourlyRatings.compactMap(\.transparencyScore)

        let details = NightQualityAssessment.Details(
            cloudCoverScore: avgCloudCover,
            fogScoreAvg: Double(avgFogScore),
            moonIlluminationAvg: avgMoonIllumination,
            windSpeedAvg: avgWindSpeed,
            seeingScoreAvg: seeingScores.isEmpty ? nil : seeingScores.reduce(0, +) / Double(seeingScores.count),
            transparencyScoreAvg: transparencyScores.isEmpty ? nil : transparencyScores.reduce(0, +) / Double(transparencyScores.count)
        )

        let (trend, firstHalf, secondHalf) = calculateTrend(hourlyRatings: hourlyRatings)
        let cloudTiming = NightQualityAnalysisRules.cloudTiming(in: hourlyRatings)

        let summary = generateSummary(
            rating: rating,
            avgScore: avgScore,
            trend: trend,
            averageCloudCover: avgCloudCover,
            seeingScoreAvg: details.seeingScoreAvg,
            cloudTiming: cloudTiming
        )

        let bestWindowStart = hourlyRatings.first?.time ?? emptyNightStart
        let bestWindowEnd = hourlyRatings.last?.time ?? emptyNightEnd

        let bestWindow = calculateBestWindow(
            hourlyRatings: hourlyRatings,
            nightStart: bestWindowStart,
            nightEnd: bestWindowEnd
        )

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

    private static func determineRating(_ avgScore: Double) -> NightQualityAssessment.Rating {
        NightQualityAssessment.Rating.from(score: avgScore)
    }

    private static func generateSummary(
        rating: NightQualityAssessment.Rating,
        avgScore: Double,
        trend: NightQualityAssessment.Trend,
        averageCloudCover: Double,
        seeingScoreAvg: Double?,
        cloudTiming: NightQualityAnalysisRules.CloudTiming
    ) -> String {
        let seeingWarning = seeingScoreAvg.map { NightQualityAssessment.Rating.from(score: $0) == .poor } == true
            ? " Poor seeing may limit fine detail."
            : ""

        if averageCloudCover >= 80 {
            switch trend {
            case .improving:
                return "Poor conditions early, but overall conditions improve through the night." + seeingWarning
            case .stable:
                return "Poor conditions for stargazing. Heavy clouds are likely to block the view." + seeingWarning
            case .degrading:
                return "Poor conditions for stargazing, with overall conditions worsening later." + seeingWarning
            }
        }

        if rating != .poor,
           let summary = cloudTiming.summaryText {
            return summary + seeingWarning
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
            case .improving: return "Excellent overall conditions, improving through the night despite some cloud cover." + seeingWarning
            case .stable: return "Excellent overall conditions, with some cloud cover." + seeingWarning
            case .degrading: return "Excellent overall conditions early, but they may worsen later." + seeingWarning
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
            case .improving: return "Good overall conditions, improving through the night despite some cloud cover." + seeingWarning
            case .stable: return "Good overall conditions, but some clouds may affect the view." + seeingWarning
            case .degrading: return "Good overall conditions early, but they may worsen later." + seeingWarning
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
        nightStart: Date,
        nightEnd: Date,
        moonIllumination: Int
    ) -> NightQualityAssessment {
        NightQualityAssessment(
            rating: .poor,
            summary: "No nighttime data available for analysis.",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 0,
                fogScoreAvg: 0,
                moonIlluminationAvg: moonIllumination,
                windSpeedAvg: 0
            ),
            bestWindow: nil,
            hourlyRatings: [],
            nightStart: nightStart,
            nightEnd: nightEnd,
            trend: .stable,
            firstHalfScore: nil,
            secondHalfScore: nil
        )
    }
}

private func formatUTCTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}
