import Foundation
import SunCalc

/// Errors that can occur during best spot search
public enum BestSpotSearchError: Error, LocalizedError {
    case noLocationsFound
    case noWeatherData
    case invalidDate
    
    public var errorDescription: String? {
        switch self {
        case .noLocationsFound:
            return "No locations found in the search area."
        case .noWeatherData:
            return "Unable to retrieve weather data for the search area."
        case .invalidDate:
            return "Invalid search date."
        }
    }
}

/// Orchestrates the search for the best viewing conditions in a geographic area
@MainActor
public class BestSpotSearcher {
    private let weatherService: WeatherService
    private let astronomyService: AstronomyService
    private let fogScoreCalculator: (HourlyForecast) -> FogScore
    
    public init(
        weatherService: WeatherService = WeatherService(),
        astronomyService: AstronomyService = AstronomyService(),
        fogScoreCalculator: @escaping (HourlyForecast) -> FogScore = FogCalculator.calculate
    ) {
        self.weatherService = weatherService
        self.astronomyService = astronomyService
        self.fogScoreCalculator = fogScoreCalculator
    }
    
    /// Finds the best viewing condition spots within a radius of a center location
    /// - Parameters:
    ///   - center: The center location to search around
    ///   - radiusMiles: Search radius in miles (default 30)
    ///   - spacingMiles: Grid spacing in miles (default 5)
    ///   - date: The date to search for (tonight/tomorrow night)
    ///   - topN: Number of top results to return (default 5)
    ///   - progressHandler: Called with progress updates (0.0 to 1.0)
    /// - Returns: BestSpotResult containing scored locations sorted by score
    public func findBestSpots(
        around center: SavedLocation,
        radiusMiles: Double = 30,
        spacingMiles: Double = 5,
        for date: Date,
        topN: Int = 5,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> BestSpotResult {
        let startTime = Date()
        
        // Generate grid points
        progressHandler?(0.1)
        let gridPoints = GeographicGridGenerator.generateGrid(
            around: center.coordinate,
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles
        )
        
        guard !gridPoints.isEmpty else {
            throw BestSpotSearchError.noLocationsFound
        }
        
        // Fetch weather for all grid points in one API call
        progressHandler?(0.2)
        let coordinates = gridPoints.map { $0.coordinate }
        let weatherData = try await weatherService.fetchForecastForMultipleLocations(
            coordinates: coordinates,
            days: 3
        )
        
        guard !weatherData.isEmpty else {
            throw BestSpotSearchError.noWeatherData
        }
        
        progressHandler?(0.4)
        
        // Calculate sun and moon data for the date (same for all points in the area)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        let sunEventsToday = await astronomyService.calculateSunEvents(
            latitude: center.latitude,
            longitude: center.longitude,
            on: startOfDay
        )
        
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let sunEventsTomorrow = await astronomyService.calculateSunEvents(
            latitude: center.latitude,
            longitude: center.longitude,
            on: nextDay
        )
        
        let moonInfo = await astronomyService.calculateMoonInfo(
            latitude: center.latitude,
            longitude: center.longitude,
            on: startOfDay
        )
        
        progressHandler?(0.5)
        
        // Score each location
        var scoredLocations: [LocationScore] = []
        let totalPoints = gridPoints.count
        
        for (index, gridPoint) in gridPoints.enumerated() {
            guard let forecasts = weatherData[gridPoint.coordinate] else { continue }
            
            if let locationScore = await scoreLocation(
                gridPoint: gridPoint,
                forecasts: forecasts,
                sunEventsToday: sunEventsToday,
                sunEventsTomorrow: sunEventsTomorrow,
                moonInfo: moonInfo,
                date: date
            ) {
                scoredLocations.append(locationScore)
            }
            
            // Update progress (50% to 90%)
            let progress = 0.5 + (Double(index + 1) / Double(totalPoints)) * 0.4
            progressHandler?(progress)
        }
        
        // Sort by score (highest first) and take top N
        scoredLocations.sort { $0.score > $1.score }
        let topLocations = Array(scoredLocations.prefix(topN))
        
        progressHandler?(1.0)
        
        let searchDuration = Date().timeIntervalSince(startTime)
        
        return BestSpotResult(
            centerLocation: CachedLocation(from: center),
            searchRadiusMiles: radiusMiles,
            gridSpacingMiles: spacingMiles,
            scoredLocations: topLocations,
            moonInfo: moonInfo,
            searchDate: date,
            searchDuration: searchDuration
        )
    }
    
    /// Scores a single location based on viewing conditions
    private func scoreLocation(
        gridPoint: GridPoint,
        forecasts: [HourlyForecast],
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents,
        moonInfo: MoonInfo,
        date: Date
    ) async -> LocationScore? {
        let calendar = Calendar.current
        
        // Calculate night quality using the existing analyzer
        let nightQuality = NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: gridPoint.coordinate.latitude,
            longitude: gridPoint.coordinate.longitude,
            for: date
        )
        
        // Convert night quality to 0-100 score
        let score = convertNightQualityToScore(nightQuality, elevation: gridPoint.elevation)
        
        // Calculate average metrics for the night
        let nightForecasts = filterNightForecasts(forecasts, sunEventsToday: sunEventsToday, sunEventsTomorrow: sunEventsTomorrow, date: date)
        
        guard !nightForecasts.isEmpty else { return nil }
        
        let avgCloudCover = Double(nightForecasts.map { $0.cloudCover }.reduce(0, +)) / Double(nightForecasts.count)
        let avgWindSpeed = nightForecasts.map { $0.windSpeed }.reduce(0, +) / Double(nightForecasts.count)
        
        // Calculate fog score for current conditions
        let fogScore = fogScoreCalculator(nightForecasts.first ?? forecasts.first!)
        
        // Generate summary
        let summary = generateSummary(nightQuality: nightQuality, score: score)
        
        return LocationScore(
            point: gridPoint,
            score: score,
            nightQuality: nightQuality,
            fogScore: fogScore,
            avgCloudCover: avgCloudCover,
            avgWindSpeed: avgWindSpeed,
            summary: summary
        )
    }
    
    /// Converts NightQualityAssessment to a 0-100 score
    /// Higher score = better viewing conditions
    private func convertNightQualityToScore(_ assessment: NightQualityAssessment, elevation: Double?) -> Int {
        // Base score from rating
        let baseScore: Int
        switch assessment.rating {
        case .excellent:
            baseScore = 90
        case .good:
            baseScore = 70
        case .fair:
            baseScore = 45
        case .poor:
            baseScore = 20
        }
        
        // Fine-tune based on actual average score within the rating band
        let hourlyScores = assessment.hourlyRatings.map { $0.score }
        let avgScore = hourlyScores.reduce(0, +) / Double(hourlyScores.count)
        
        // Convert avgScore (0-2, lower is better) to adjustment (-10 to +10)
        let adjustment = Int((1.0 - avgScore) * 10)
        
        // Elevation bonus: +1 point per 100ft above sea level (max +10)
        let elevationBonus = min(Int((elevation ?? 0) / 100), 10)
        
        let finalScore = baseScore + adjustment + elevationBonus
        return min(100, max(0, finalScore))
    }
    
    /// Filters forecasts to only include nighttime hours (8 PM - 5 AM)
    private func filterNightForecasts(
        _ forecasts: [HourlyForecast],
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents,
        date: Date
    ) -> [HourlyForecast] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // Use astronomical twilight times as bounds
        let duskHour = calendar.component(.hour, from: sunEventsToday.astronomicalTwilightEnd)
        let duskMinute = calendar.component(.minute, from: sunEventsToday.astronomicalTwilightEnd)
        let nightStart = calendar.date(bySettingHour: duskHour, minute: duskMinute, second: 0, of: startOfDay)!
        
        let dawnHour = calendar.component(.hour, from: sunEventsTomorrow.astronomicalTwilightBegin)
        let dawnMinute = calendar.component(.minute, from: sunEventsTomorrow.astronomicalTwilightBegin)
        let nightEnd = calendar.date(bySettingHour: dawnHour, minute: dawnMinute, second: 0, of: nextDay)!
        
        return forecasts.filter { forecast in
            forecast.time >= nightStart && forecast.time < nightEnd
        }
    }
    
    /// Generates a human-readable summary of the conditions
    private func generateSummary(nightQuality: NightQualityAssessment, score: Int) -> String {
        let cloudCover = Int(nightQuality.details.cloudCoverScore)
        let windSpeed = nightQuality.details.windSpeedAvg
        
        var parts: [String] = []
        
        // Cloud cover description
        if cloudCover < 10 {
            parts.append("Crystal clear skies")
        } else if cloudCover < 30 {
            parts.append("Mostly clear")
        } else if cloudCover < 60 {
            parts.append("Partly cloudy")
        } else {
            parts.append("Cloudy")
        }
        
        // Wind description
        if windSpeed < 5 {
            parts.append("calm winds")
        } else if windSpeed < 15 {
            parts.append("light winds")
        } else {
            parts.append("breezy")
        }
        
        return parts.joined(separator: ", ")
    }
}
