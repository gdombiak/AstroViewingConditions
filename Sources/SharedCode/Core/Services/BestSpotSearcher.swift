import Foundation
import CoreLocation
import SunCalc

/// Errors that can occur during best nearby area search
public enum BestSpotSearchError: Error, LocalizedError {
    case noLocationsFound
    case noWeatherData
    case invalidDate
    case unsupportedForecastDate(maxDays: Int)
    case noScorableLocations
    case noRecommendableLocations
    
    public var errorDescription: String? {
        switch self {
        case .noLocationsFound:
            return "No locations found in the search area."
        case .noWeatherData:
            return "Unable to retrieve weather data for the search area."
        case .invalidDate:
            return "Invalid search date."
        case .unsupportedForecastDate(let maxDays):
            return "Forecasts are only available for the next \(maxDays) days. Choose a nearer night."
        case .noScorableLocations:
            return "Weather data was available, but no night conditions could be scored for the selected date."
        case .noRecommendableLocations:
            return "No recommendable nearby areas found. The best-scoring candidates appear to be water or could not be verified. Try a different starting location, search radius, or date."
        }
    }
}

public protocol BestSpotSearching: Sendable {
    func findBestSpots(
        around center: CachedLocation,
        radiusMiles: Double,
        spacingMiles: Double,
        for date: Date,
        topN: Int,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> BestSpotResult
}

public protocol LocationSuitabilityProviding: Sendable {
    func suitability(for point: GridPoint) async -> LocationSuitabilityStatus
    func suitability(for points: [GridPoint]) async -> [GridPoint: LocationSuitabilityStatus]
}

public protocol LocationSuitabilityResolving: Sendable {
    func resolveSuitability(for coordinate: Coordinate) async -> LocationSuitabilityStatus
}

public actor CoreLocationSuitabilityResolver: LocationSuitabilityResolving {
    public init() {}

    public func resolveSuitability(for coordinate: Coordinate) async -> LocationSuitabilityStatus {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return .unknown(reason: .geocodingFailed)
            }

            if placemark.ocean != nil || placemark.inlandWater != nil {
                return .unsuitable(reason: "Water area")
            }

            if placemark.country != nil || placemark.administrativeArea != nil || placemark.locality != nil {
                return .suitable
            }

            return .unknown(reason: .notChecked)
        } catch {
            return Self.suitabilityStatus(for: error)
        }
    }

    public static func suitabilityStatus(for error: Error) -> LocationSuitabilityStatus {
        if let error = error as? CLError, error.code == .network {
            return .unknown(reason: .temporarilyUnavailable)
        }

        let nsError = error as NSError
        if nsError.domain == "GEOErrorDomain", nsError.code == -3 {
            return .unknown(reason: .temporarilyUnavailable)
        }

        return .unknown(reason: .geocodingFailed)
    }
}

public actor LocationSuitabilityService: LocationSuitabilityProviding {
    public struct CacheKey: Sendable, Hashable {
        public let roundedLatitude: Double
        public let roundedLongitude: Double
    }

    /// Rounds to 0.001 degrees by default, roughly 110 meters of latitude.
    public static let defaultCoordinatePrecision: Double = 0.001
    public static let defaultMaxConcurrentLookups = 4

    private let resolver: any LocationSuitabilityResolving
    private let coordinatePrecision: Double
    private let maxConcurrentLookups: Int
    private var cache: [CacheKey: LocationSuitabilityStatus] = [:]

    public init(
        resolver: any LocationSuitabilityResolving = CoreLocationSuitabilityResolver(),
        coordinatePrecision: Double = defaultCoordinatePrecision,
        maxConcurrentLookups: Int = defaultMaxConcurrentLookups
    ) {
        self.resolver = resolver
        self.coordinatePrecision = coordinatePrecision
        self.maxConcurrentLookups = max(maxConcurrentLookups, 1)
    }

    public func suitability(for point: GridPoint) async -> LocationSuitabilityStatus {
        await suitability(for: [point])[point] ?? .unknown(reason: .geocodingFailed)
    }

    public func suitability(for points: [GridPoint]) async -> [GridPoint: LocationSuitabilityStatus] {
        guard !points.isEmpty else { return [:] }

        var results: [GridPoint: LocationSuitabilityStatus] = [:]
        var representativeByKey: [CacheKey: GridPoint] = [:]

        for point in points {
            let key = Self.cacheKey(for: point.coordinate, precision: coordinatePrecision)
            if let cached = cache[key] {
                results[point] = cached
            } else if representativeByKey[key] == nil {
                representativeByKey[key] = point
            }
        }

        let missing = Array(representativeByKey)
        let resolved = await resolveMissingSuitability(missing)

        for (key, status) in resolved {
            cache[key] = status
        }

        for point in points where results[point] == nil {
            let key = Self.cacheKey(for: point.coordinate, precision: coordinatePrecision)
            results[point] = cache[key] ?? .unknown(reason: .geocodingFailed)
        }

        return results
    }

    private func resolveMissingSuitability(_ missing: [(key: CacheKey, value: GridPoint)]) async -> [CacheKey: LocationSuitabilityStatus] {
        guard !missing.isEmpty else { return [:] }

        return await withTaskGroup(of: (CacheKey, LocationSuitabilityStatus).self) { group in
            var nextIndex = 0
            var resolved: [CacheKey: LocationSuitabilityStatus] = [:]

            func addNextTask() {
                guard nextIndex < missing.count else { return }
                let entry = missing[nextIndex]
                nextIndex += 1
                group.addTask { [resolver] in
                    let status = await resolver.resolveSuitability(for: entry.value.coordinate)
                    return (entry.key, status)
                }
            }

            for _ in 0..<min(maxConcurrentLookups, missing.count) {
                addNextTask()
            }

            while let (key, status) = await group.next() {
                resolved[key] = status
                addNextTask()
            }

            return resolved
        }
    }

    public static func cacheKey(for coordinate: Coordinate, precision: Double = defaultCoordinatePrecision) -> CacheKey {
        CacheKey(
            roundedLatitude: (coordinate.latitude / precision).rounded() * precision,
            roundedLongitude: (coordinate.longitude / precision).rounded() * precision
        )
    }
}

/// Orchestrates the search for the best nearby area based on viewing conditions.
public final class BestSpotSearcher: BestSpotSearching {
    public static let maxForecastDays = 16
    public static let minimumSuitabilityCandidateCount = 20
    // Keep below the observed iOS/CoreLocation reverse-geocoding throttling threshold.
    // Coastal searches can otherwise trigger many checks; 40 allows ranked expansion
    // bands without the real-device slowdowns seen at higher caps.
    public static let maxSuitabilityCandidateChecks = 40

    private let weatherService: any WeatherForecastProviding
    private let astronomyService: any AstronomyProviding
    private let suitabilityService: any LocationSuitabilityProviding
    private let fogScoreCalculator: @Sendable (HourlyForecast) -> FogScore
    
    public init(
        weatherService: any WeatherForecastProviding = WeatherService(),
        astronomyService: any AstronomyProviding = AstronomyService(),
        suitabilityService: any LocationSuitabilityProviding = LocationSuitabilityService(),
        fogScoreCalculator: @escaping @Sendable (HourlyForecast) -> FogScore = FogCalculator.calculate
    ) {
        self.weatherService = weatherService
        self.astronomyService = astronomyService
        self.suitabilityService = suitabilityService
        self.fogScoreCalculator = fogScoreCalculator
    }
    
#if os(iOS)
    /// Finds nearby areas with the best viewing conditions within a radius of a center location.
    /// - Parameters:
    ///   - center: The center location to search around
    ///   - radiusMiles: Search radius in miles (default 30)
    ///   - spacingMiles: Grid spacing in miles (default 5)
    ///   - date: The date to search for (tonight/tomorrow night)
    ///   - topN: Number of top results to return (default 5)
    ///   - progressHandler: Called with progress updates (0.0 to 1.0)
    /// - Returns: BestSpotResult containing scored areas sorted by score
    public func findBestSpots(
        around center: SavedLocation,
        radiusMiles: Double = 30,
        spacingMiles: Double = 5,
        for date: Date,
        topN: Int = 5,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> BestSpotResult {
        let cachedLocation = CachedLocation(from: center)
        return try await findBestSpots(
            around: cachedLocation,
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles,
            for: date,
            topN: topN,
            progressHandler: progressHandler
        )
    }
#endif

    public func findBestSpots(
        around center: CachedLocation,
        radiusMiles: Double = 30,
        spacingMiles: Double = 5,
        for date: Date,
        topN: Int = 5,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> BestSpotResult {
        let startTime = Date()
        try Task.checkCancellation()
        
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
        
        let tz = await LocationTimeZoneResolver.resolve(latitude: center.latitude, longitude: center.longitude)
        try Task.checkCancellation()
        let calendar = LocationTimeZoneResolver.calendar(for: tz)
        let forecastDays = Self.forecastDaysNeeded(for: date, calendar: calendar)
        guard forecastDays <= Self.maxForecastDays else {
            throw BestSpotSearchError.unsupportedForecastDate(maxDays: Self.maxForecastDays)
        }
        
        // Fetch weather for all grid points in one API call
        progressHandler?(0.2)
        let coordinates = gridPoints.map { $0.coordinate }
        let weatherData = try await weatherService.fetchForecastForMultipleLocations(
            coordinates: coordinates,
            days: forecastDays
        )
        try Task.checkCancellation()
        
        guard !weatherData.isEmpty else {
            throw BestSpotSearchError.noWeatherData
        }
        
        progressHandler?(0.4)
        
        // Calculate sun and moon data for the date (same for all points in the area)
        let startOfDay = calendar.startOfDay(for: date)
        
        let sunEventsToday = await astronomyService.calculateSunEvents(
            latitude: center.latitude,
            longitude: center.longitude,
            on: startOfDay
        )
        
        guard let nextDay = calendar.date(byAdding: Calendar.Component.day, value: 1, to: startOfDay) else {
            throw BestSpotSearchError.invalidDate
        }
        let sunEventsTomorrow = await astronomyService.calculateSunEvents(
            latitude: center.latitude,
            longitude: center.longitude,
            on: nextDay
        )
        try Task.checkCancellation()
        
        let moonInfo = await astronomyService.calculateMoonInfo(
            latitude: center.latitude,
            longitude: center.longitude,
            on: startOfDay
        )
        try Task.checkCancellation()
        
        progressHandler?(0.5)
        
        // Score each location
        var scoredLocations: [LocationScore] = []
        let totalPoints = gridPoints.count
        let moonCalculationCache = NightQualityAnalyzer.MoonCalculationCache()
        
        for (index, gridPoint) in gridPoints.enumerated() {
            try Task.checkCancellation()
            guard let forecasts = weatherData[gridPoint.coordinate] else { continue }
            
            if let locationScore = scoreLocation(
                gridPoint: gridPoint,
                forecasts: forecasts,
                sunEventsToday: sunEventsToday,
                sunEventsTomorrow: sunEventsTomorrow,
                moonInfo: moonInfo,
                date: date,
                calendar: calendar,
                moonCalculationCache: moonCalculationCache
            ) {
                scoredLocations.append(locationScore)
            }
            
            // Update progress (50% to 90%)
            let progress = 0.5 + (Double(index + 1) / Double(totalPoints)) * 0.4
            progressHandler?(progress)
        }
        
        guard !scoredLocations.isEmpty else {
            throw BestSpotSearchError.noScorableLocations
        }

        let centerScore = scoredLocations.first { $0.point.isCenter }?.score
        let rankedWeatherLocations = scoredLocations
            .map { $0.withImprovement(comparedTo: centerScore) }
            .sorted(by: Self.isHigherRanked(_:than:))
        var checkedCandidates: [LocationScore] = []
        var checkedIDs = Set<LocationScore.ID>()
        var recommendableLocations: [LocationScore] = []
        let candidateBandSize = Self.suitabilityCandidateCount(topN: topN)
        var bandStartIndex = 0

        while recommendableLocations.count < topN &&
            bandStartIndex < rankedWeatherLocations.count &&
            checkedCandidates.count < Self.maxSuitabilityCandidateChecks {
            try Task.checkCancellation()
            let remainingCheckCapacity = Self.maxSuitabilityCandidateChecks - checkedCandidates.count
            let bandEndIndex = min(
                bandStartIndex + min(candidateBandSize, remainingCheckCapacity),
                rankedWeatherLocations.count
            )
            let uncheckedBand = rankedWeatherLocations[bandStartIndex..<bandEndIndex]
                .filter { checkedIDs.insert($0.id).inserted }
            bandStartIndex = bandEndIndex

            guard !uncheckedBand.isEmpty else { continue }

            let suitabilityByPoint = await suitabilityService.suitability(for: uncheckedBand.map(\.point))
            let checkedBand = uncheckedBand.map { location in
                location.with(suitability: suitabilityByPoint[location.point] ?? .unknown(reason: .geocodingFailed))
            }
            checkedCandidates.append(contentsOf: checkedBand)
            recommendableLocations = checkedCandidates
                .filter { $0.suitability.isRecommendable }
                .sorted(by: Self.isHigherRanked(_:than:))
        }

        recommendableLocations = Array(recommendableLocations.prefix(topN))
        let checkedByID = Dictionary(uniqueKeysWithValues: checkedCandidates.map { ($0.id, $0) })
        let allScoredLocations = rankedWeatherLocations.map { checkedByID[$0.id] ?? $0 }
        let topLocations = recommendableLocations

        guard !topLocations.isEmpty else {
            throw BestSpotSearchError.noRecommendableLocations
        }

        let failedChecks = checkedCandidates.filter { $0.suitability.indicatesIncompleteVerification }.count
        let suitabilityWarning = failedChecks > checkedCandidates.count / 2
            ? "Area verification was incomplete for many candidates. Confirm access and avoid water before traveling."
            : nil
        
        progressHandler?(1.0)
        
        let searchDuration = Date().timeIntervalSince(startTime)
        
        return BestSpotResult(
            centerLocation: center,
            searchRadiusMiles: radiusMiles,
            gridSpacingMiles: spacingMiles,
            allScoredLocations: allScoredLocations,
            topLocations: topLocations,
            moonInfo: moonInfo,
            searchDate: date,
            searchDuration: searchDuration,
            suitabilityWarning: suitabilityWarning
        )
    }
    
    /// Scores a single location based on viewing conditions
    private func scoreLocation(
        gridPoint: GridPoint,
        forecasts: [HourlyForecast],
        sunEventsToday: SunEvents,
        sunEventsTomorrow: SunEvents,
        moonInfo: MoonInfo,
        date: Date,
        calendar: Calendar,
        moonCalculationCache: NightQualityAnalyzer.MoonCalculationCache
    ) -> LocationScore? {
        // Calculate night quality using the existing analyzer
        let nightQuality = NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            moonInfo: moonInfo,
            latitude: gridPoint.coordinate.latitude,
            longitude: gridPoint.coordinate.longitude,
            for: date,
            calendar: calendar,
            moonCalculationCache: moonCalculationCache
        )
        
        // Convert night quality to 0-100 score
        let score = Self.calculateScore(nightQuality)
        
        // Calculate average metrics for the night
        let nightForecasts = NightForecastFilter.filterToNighttime(
            forecasts: forecasts,
            sunEventsToday: sunEventsToday,
            sunEventsTomorrow: sunEventsTomorrow,
            for: date,
            calendar: calendar
        )
        
        guard !nightForecasts.isEmpty else { return nil }
        
        let avgCloudCover = Double(nightForecasts.map { $0.cloudCover }.reduce(0, +)) / Double(nightForecasts.count)
        let avgWindSpeed = nightForecasts.map { $0.windSpeed }.reduce(0, +) / Double(nightForecasts.count)
        
        let fogScore = averageFogScore(for: nightForecasts)
        
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

    private func averageFogScore(for forecasts: [HourlyForecast]) -> FogScore {
        let fogScores = forecasts.map(fogScoreCalculator)
        guard !fogScores.isEmpty else { return FogScore(score: 0, factors: []) }

        let averageScore = fogScores.map(\.score).reduce(0, +) / fogScores.count
        let factors = FogScore.FogFactor.allCases.filter { factor in
            fogScores.contains { $0.factors.contains(factor) }
        }

        return FogScore(score: averageScore, factors: factors)
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
    
    static func forecastDaysNeeded(for date: Date, calendar: Calendar, referenceDate: Date = Date()) -> Int {
        let referenceStart = calendar.startOfDay(for: referenceDate)
        let searchStart = calendar.startOfDay(for: date)
        let dayOffset = calendar.dateComponents([.day], from: referenceStart, to: searchStart).day ?? 0
        
        return max(2, dayOffset + 2)
    }
    
    /// Converts NightQualityAssessment to a 0-100 score
    /// Higher score = better viewing conditions
    nonisolated public static func isHigherRanked(_ lhs: LocationScore, than rhs: LocationScore) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.avgCloudCover != rhs.avgCloudCover { return lhs.avgCloudCover < rhs.avgCloudCover }
        if lhs.fogScore.score != rhs.fogScore.score { return lhs.fogScore.score < rhs.fogScore.score }
        if lhs.avgWindSpeed != rhs.avgWindSpeed { return lhs.avgWindSpeed < rhs.avgWindSpeed }
        if lhs.suitability.verificationRank != rhs.suitability.verificationRank {
            return lhs.suitability.verificationRank < rhs.suitability.verificationRank
        }
        if lhs.point.distanceMiles != rhs.point.distanceMiles { return lhs.point.distanceMiles < rhs.point.distanceMiles }
        if lhs.point.coordinate.latitude != rhs.point.coordinate.latitude {
            return lhs.point.coordinate.latitude < rhs.point.coordinate.latitude
        }
        return lhs.point.coordinate.longitude < rhs.point.coordinate.longitude
    }

    nonisolated public static func suitabilityCandidateCount(topN: Int) -> Int {
        max(topN * 4, minimumSuitabilityCandidateCount)
    }

    nonisolated static func calculateScore(_ assessment: NightQualityAssessment) -> Int {
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
        var adjustment = 0
        if !hourlyScores.isEmpty {
            let avgScore = hourlyScores.reduce(0, +) / Double(hourlyScores.count)
            // Convert avgScore (0-2, lower is better) to adjustment (-10 to +10)
            adjustment = Int((1.0 - avgScore) * 10)
        }
        
        let finalScore = baseScore + adjustment
        return min(100, max(0, finalScore))
    }
}
