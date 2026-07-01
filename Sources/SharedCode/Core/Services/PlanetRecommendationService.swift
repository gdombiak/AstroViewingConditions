import Foundation

public struct PlanetPositionSample: Sendable, Hashable {
    public let time: Date
    public let altitude: Double
    public let azimuth: Double
    public let solarElongation: Double?

    public init(
        time: Date,
        altitude: Double,
        azimuth: Double,
        solarElongation: Double? = nil
    ) {
        self.time = time
        self.altitude = altitude
        self.azimuth = azimuth
        self.solarElongation = solarElongation
    }
}

public struct PlanetObservationData: Sendable, Hashable {
    public let targetID: String
    public let samples: [PlanetPositionSample]

    public init(targetID: String, samples: [PlanetPositionSample]) {
        self.targetID = targetID
        self.samples = samples
    }
}

public protocol PlanetAstronomyProviding: Sendable {
    func planetObservation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> PlanetObservationData?
}

public protocol PlanetTargetRecommendationProviding: Sendable {
    func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation?
}

public struct LowPrecisionPlanetAstronomyProvider: PlanetAstronomyProviding {
    private let sampleInterval: TimeInterval

    public init(sampleInterval: TimeInterval = 15 * 60) {
        self.sampleInterval = sampleInterval
    }

    public func planetObservation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> PlanetObservationData? {
        guard let planet = PlanetOrbitalElements.Planet(rawValue: target.id.lowercased()) else {
            return nil
        }

        let start = context.astronomicalNightStart.addingTimeInterval(-2 * 3600)
        let end = context.astronomicalNightEnd.addingTimeInterval(60 * 60)
        guard end > start else { return nil }

        var samples: [PlanetPositionSample] = []
        var time = start

        while time <= end {
            samples.append(position(
                for: planet,
                at: time,
                latitude: context.location.latitude,
                longitude: context.location.longitude
            ))
            time = time.addingTimeInterval(sampleInterval)
        }

        return PlanetObservationData(targetID: target.id, samples: samples)
    }

    private func position(
        for planet: PlanetOrbitalElements.Planet,
        at date: Date,
        latitude: Double,
        longitude: Double
    ) -> PlanetPositionSample {
        let jd = Self.julianDate(from: date)
        let d = jd - 2_451_543.5
        let sunGeocentric = PlanetOrbitalElements.elements(for: .earth, daysSinceJ2000: d).heliocentricCoordinates()
        let planetCoordinates = PlanetOrbitalElements.elements(for: planet, daysSinceJ2000: d).heliocentricCoordinates()

        let x = planetCoordinates.x + sunGeocentric.x
        let y = planetCoordinates.y + sunGeocentric.y
        let z = planetCoordinates.z + sunGeocentric.z
        let obliquity = Self.radians(23.4393 - 3.563e-7 * d)

        let equatorialX = x
        let equatorialY = y * cos(obliquity) - z * sin(obliquity)
        let equatorialZ = y * sin(obliquity) + z * cos(obliquity)
        let rightAscension = atan2(equatorialY, equatorialX)
        let declination = atan2(equatorialZ, sqrt(equatorialX * equatorialX + equatorialY * equatorialY))

        let localSiderealTime = Self.radians(Self.normalizedDegrees(
            280.460_618_37 + 360.985_647_366_29 * (jd - 2_451_545.0) + longitude
        ))
        let hourAngle = Self.normalizedRadians(localSiderealTime - rightAscension)
        let latitudeRadians = Self.radians(latitude)

        let altitude = asin(
            sin(declination) * sin(latitudeRadians)
            + cos(declination) * cos(latitudeRadians) * cos(hourAngle)
        )
        let azimuth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitudeRadians) - tan(declination) * cos(latitudeRadians)
        )

        return PlanetPositionSample(
            time: date,
            altitude: Self.degrees(altitude),
            azimuth: Self.normalizedDegrees(Self.degrees(azimuth) + 180),
            solarElongation: Self.angularSeparation(
                first: (x, y, z),
                second: sunGeocentric
            )
        )
    }

    private static func angularSeparation(
        first: (x: Double, y: Double, z: Double),
        second: (x: Double, y: Double, z: Double)
    ) -> Double {
        let dotProduct = first.x * second.x + first.y * second.y + first.z * second.z
        let firstMagnitude = sqrt(first.x * first.x + first.y * first.y + first.z * first.z)
        let secondMagnitude = sqrt(second.x * second.x + second.y * second.y + second.z * second.z)
        guard firstMagnitude > 0, secondMagnitude > 0 else { return 0 }

        let cosine = min(max(dotProduct / (firstMagnitude * secondMagnitude), -1), 1)
        return degrees(acos(cosine))
    }

    private static func julianDate(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    private static func normalizedRadians(_ radians: Double) -> Double {
        let twoPi = 2 * Double.pi
        return (radians.truncatingRemainder(dividingBy: twoPi) + twoPi)
            .truncatingRemainder(dividingBy: twoPi)
    }
}

public struct DefaultPlanetTargetRecommendationProvider: PlanetTargetRecommendationProviding {
    private static let minimumVisibleAltitude = 8.0

    private let planetAstronomyProvider: any PlanetAstronomyProviding

    public init(planetAstronomyProvider: any PlanetAstronomyProviding = LowPrecisionPlanetAstronomyProvider()) {
        self.planetAstronomyProvider = planetAstronomyProvider
    }

    public func recommendation(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> TargetRecommendation? {
        guard target.type == .planet,
              let observation = planetAstronomyProvider.planetObservation(for: target, context: context) else {
            return nil
        }

        let visibleSamples = observation.samples.filter { $0.altitude >= Self.minimumVisibleAltitude }
        guard !visibleSamples.isEmpty,
              let bestSample = bestSample(from: visibleSamples, context: context) else {
            return nil
        }

        let window = visibilityWindow(from: visibleSamples, bestSample: bestSample)
        let weatherQuality = weatherQuality(in: window, context: context)
        let darknessOverlap = overlapFraction(
            windowStart: window.start,
            windowEnd: window.end,
            darknessStart: context.astronomicalNightStart,
            darknessEnd: context.astronomicalNightEnd
        )
        let convenience = convenienceScore(for: bestSample.time, context: context)
        let score = score(
            altitude: bestSample.altitude,
            weatherQuality: weatherQuality,
            darknessOverlap: darknessOverlap,
            convenience: convenience
        )
        let reasons = reasons(
            bestSample: bestSample,
            weatherQuality: weatherQuality,
            darknessOverlap: darknessOverlap,
            convenience: convenience
        )

        let recommendation = TargetRecommendation(
            target: target,
            score: score,
            visibilityWindow: window,
            reasons: reasons,
            summary: summary(
                for: target,
                bestSample: bestSample,
                window: window,
                context: context
            )
        )
        TargetRecommendationDebugLogger.logRecommendation(
            recommendation,
            context: context,
            sampledTimeRange: TargetRecommendationDebugLogger.sampledTimeRange(
                start: observation.samples.first?.time,
                end: observation.samples.last?.time
            ),
            samplesSummary: Self.samplesSummary(
                allSamples: observation.samples,
                visibleSamples: visibleSamples
            ),
            bestAltitude: bestSample.altitude,
            bestAzimuth: bestSample.azimuth,
            scoreBreakdown: scoreBreakdown(
                altitude: bestSample.altitude,
                weatherQuality: weatherQuality,
                darknessOverlap: darknessOverlap,
                convenience: convenience
            )
        )
        return recommendation
    }

    private func bestSample(
        from samples: [PlanetPositionSample],
        context: TargetRecommendationContext
    ) -> PlanetPositionSample? {
        samples.max { lhs, rhs in
            weightedScore(for: lhs, context: context) < weightedScore(for: rhs, context: context)
        }
    }

    private func weightedScore(
        for sample: PlanetPositionSample,
        context: TargetRecommendationContext
    ) -> Double {
        let altitude = min(max(sample.altitude / 70, 0), 1)
        let darkness = sample.time >= context.astronomicalNightStart
            && sample.time <= context.astronomicalNightEnd ? 1.0 : 0.55
        let convenience = convenienceScore(for: sample.time, context: context)
        return altitude * 0.70 + darkness * 0.15 + convenience * 0.15
    }

    private func visibilityWindow(
        from visibleSamples: [PlanetPositionSample],
        bestSample: PlanetPositionSample
    ) -> TargetVisibilityWindow {
        TargetVisibilityWindow(
            start: visibleSamples.first?.time ?? bestSample.time,
            end: visibleSamples.last?.time.addingTimeInterval(15 * 60) ?? bestSample.time.addingTimeInterval(15 * 60),
            bestTime: bestSample.time,
            maxAltitude: bestSample.altitude,
            direction: Self.userFacingCompassDirection(for: bestSample.azimuth)
        )
    }

    private func score(
        altitude: Double,
        weatherQuality: Double,
        darknessOverlap: Double,
        convenience: Double
    ) -> Int {
        let altitudeQuality = min(max(altitude / 70, 0), 1)
        let lowAltitudePenalty = altitude < 15 ? 18.0 : 0
        let rawScore = altitudeQuality * 45
            + weatherQuality * 30
            + darknessOverlap * 12
            + convenience * 13
            - lowAltitudePenalty
        return Int(round(min(max(rawScore, 0), 100)))
    }

    private func scoreBreakdown(
        altitude: Double,
        weatherQuality: Double,
        darknessOverlap: Double,
        convenience: Double
    ) -> [String] {
        let altitudeQuality = min(max(altitude / 70, 0), 1)
        let lowAltitudePenalty = altitude < 15 ? 18.0 : 0
        let altitudeComponent = altitudeQuality * 45
        let weatherComponent = weatherQuality * 30
        let darknessComponent = darknessOverlap * 12
        let convenienceComponent = convenience * 13
        let rawScore = altitudeComponent
            + weatherComponent
            + darknessComponent
            + convenienceComponent
            - lowAltitudePenalty

        return [
            String(format: "altitude %.1f", altitudeComponent),
            String(format: "weather %.1f", weatherComponent),
            String(format: "darkness %.1f", darknessComponent),
            String(format: "convenience %.1f", convenienceComponent),
            String(format: "lowAltitudePenalty -%.1f", lowAltitudePenalty),
            String(format: "raw %.1f", rawScore)
        ]
    }

    private func reasons(
        bestSample: PlanetPositionSample,
        weatherQuality: Double,
        darknessOverlap: Double,
        convenience: Double
    ) -> [TargetRecommendationReason] {
        var reasons: [TargetRecommendationReason] = []

        if bestSample.altitude >= 45 {
            reasons.append(.highAltitude)
        } else if bestSample.altitude < 20 {
            reasons.append(.lowAltitude)
        }

        if darknessOverlap >= 0.45 {
            reasons.append(.astronomicalDarkness)
        }

        if convenience >= 0.72 {
            reasons.append(.convenientPlanetWindow)
        } else if convenience <= 0.35 {
            reasons.append(.lateOrEarlyPlanetWindow)
        }

        if weatherQuality >= 0.7 {
            reasons.append(.goodNightQuality)
        } else if weatherQuality < 0.45 {
            reasons.append(.poorWeather)
        }

        reasons.append(.planetMoonlightResistant)
        return reasons
    }

    private func summary(
        for target: ObservableTarget,
        bestSample: PlanetPositionSample,
        window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> String {
        let direction = Self.userFacingCompassDirection(for: bestSample.azimuth)
        let altitude = Int(round(bestSample.altitude))

        if context.hasPoorTargetRecommendationConditions(in: window) {
            if bestSample.time < context.astronomicalNightStart {
                return "Well placed after sunset, but clouds may block the view."
            }

            if bestSample.time > context.astronomicalNightEnd.addingTimeInterval(-2 * 3600) {
                return "Well placed before dawn, but clouds may block the view."
            }

            return "Well placed tonight, but clouds may block the view."
        }

        if bestSample.time < context.astronomicalNightStart {
            if bestSample.altitude < 20 {
                return "Low in the \(direction) shortly after sunset; horizon obstructions may matter."
            }
            return "Look \(direction), about \(altitude)° high shortly after sunset."
        }

        if bestSample.time > context.astronomicalNightEnd.addingTimeInterval(-2 * 3600) {
            if bestSample.altitude < 20 {
                return "Visible before dawn, but low altitude limits the view."
            }
            if bestSample.altitude < 35 {
                return "Best before dawn; only moderately high."
            }
            return "Visible before dawn in the \(direction), about \(altitude)° high."
        }

        return "Highest around \(Self.timeFormatter.string(from: bestSample.time)), facing \(direction)."
    }

    private func convenienceScore(for time: Date, context: TargetRecommendationContext) -> Double {
        let eveningStart = context.astronomicalNightStart.addingTimeInterval(-2 * 3600)
        let eveningEnd = context.astronomicalNightStart.addingTimeInterval(4 * 3600)
        if time >= eveningStart && time <= eveningEnd {
            return 1
        }

        let lateNightStart = context.astronomicalNightEnd.addingTimeInterval(-3 * 3600)
        if time >= lateNightStart {
            return 0.35
        }

        return 0.65
    }

    private func weatherQuality(
        in window: TargetVisibilityWindow,
        context: TargetRecommendationContext
    ) -> Double {
        let overlappingRatings = context.nightQuality.hourlyRatings.filter { rating in
            let ratingEnd = rating.time.addingTimeInterval(3600)
            return ratingEnd > window.start && rating.time < window.end
        }

        guard !overlappingRatings.isEmpty else {
            return 1 - min(max(context.nightQuality.details.cloudCoverScore / 100, 0), 1)
        }

        let averageScore = overlappingRatings.map(\.score).reduce(0, +) / Double(overlappingRatings.count)
        return 1 - min(max(averageScore / 2, 0), 1)
    }

    private func overlapFraction(
        windowStart: Date,
        windowEnd: Date,
        darknessStart: Date,
        darknessEnd: Date
    ) -> Double {
        guard windowEnd > windowStart else { return 0 }

        let overlapStart = max(windowStart, darknessStart)
        let overlapEnd = min(windowEnd, darknessEnd)
        guard overlapEnd > overlapStart else { return 0 }

        return overlapEnd.timeIntervalSince(overlapStart) / windowEnd.timeIntervalSince(windowStart)
    }

    public static func compassDirection(for azimuth: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        ]
        let normalized = (azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % directions.count
        return directions[index]
    }

    private static func userFacingCompassDirection(for azimuth: Double) -> String {
        compassDirection(for: azimuth).uppercased()
    }

    private static func samplesSummary(
        allSamples: [PlanetPositionSample],
        visibleSamples: [PlanetPositionSample]
    ) -> String {
        guard !allSamples.isEmpty else { return "0 samples" }

        let altitudeValues = allSamples.map(\.altitude)
        let azimuthValues = allSamples.map(\.azimuth)
        let solarElongationValues = allSamples.compactMap(\.solarElongation)
        let visibleAltitudeValues = visibleSamples.map(\.altitude)

        let altitudeSummary = minMaxSummary(values: altitudeValues)
        let azimuthSummary = minMaxSummary(values: azimuthValues)
        let solarElongationSummary = minMaxSummary(values: solarElongationValues)
        let visibleAltitudeSummary = minMaxSummary(values: visibleAltitudeValues)

        return "\(allSamples.count) samples; visible \(visibleSamples.count) >= \(Int(minimumVisibleAltitude))°; altitude \(altitudeSummary); visible altitude \(visibleAltitudeSummary); azimuth \(azimuthSummary); solar elongation \(solarElongationSummary)"
    }

    private static func minMaxSummary(values: [Double]) -> String {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return "n/a"
        }

        return String(format: "%.1f°...%.1f°", minValue, maxValue)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct PlanetOrbitalElements {
    enum Planet: String {
        case earth
        case venus
        case mars
        case jupiter
        case saturn
    }

    let longitudeOfAscendingNode: Double
    let inclination: Double
    let argumentOfPerihelion: Double
    let semiMajorAxis: Double
    let eccentricity: Double
    let meanAnomaly: Double

    static func elements(for planet: Planet, daysSinceJ2000 d: Double) -> PlanetOrbitalElements {
        switch planet {
        case .earth:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 0,
                inclination: 0,
                argumentOfPerihelion: 282.9404 + 4.70935e-5 * d,
                semiMajorAxis: 1,
                eccentricity: 0.016709 - 1.151e-9 * d,
                meanAnomaly: 356.0470 + 0.9856002585 * d
            )
        case .venus:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 76.6799 + 2.46590e-5 * d,
                inclination: 3.3946 + 2.75e-8 * d,
                argumentOfPerihelion: 54.8910 + 1.38374e-5 * d,
                semiMajorAxis: 0.723330,
                eccentricity: 0.006773 - 1.302e-9 * d,
                meanAnomaly: 48.0052 + 1.6021302244 * d
            )
        case .mars:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 49.5574 + 2.11081e-5 * d,
                inclination: 1.8497 - 1.78e-8 * d,
                argumentOfPerihelion: 286.5016 + 2.92961e-5 * d,
                semiMajorAxis: 1.523688,
                eccentricity: 0.093405 + 2.516e-9 * d,
                meanAnomaly: 18.6021 + 0.5240207766 * d
            )
        case .jupiter:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 100.4542 + 2.76854e-5 * d,
                inclination: 1.3030 - 1.557e-7 * d,
                argumentOfPerihelion: 273.8777 + 1.64505e-5 * d,
                semiMajorAxis: 5.20256,
                eccentricity: 0.048498 + 4.469e-9 * d,
                meanAnomaly: 19.8950 + 0.0830853001 * d
            )
        case .saturn:
            return PlanetOrbitalElements(
                longitudeOfAscendingNode: 113.6634 + 2.38980e-5 * d,
                inclination: 2.4886 - 1.081e-7 * d,
                argumentOfPerihelion: 339.3939 + 2.97661e-5 * d,
                semiMajorAxis: 9.55475,
                eccentricity: 0.055546 - 9.499e-9 * d,
                meanAnomaly: 316.9670 + 0.0334442282 * d
            )
        }
    }

    func heliocentricCoordinates() -> (x: Double, y: Double, z: Double) {
        let meanAnomalyRadians = Self.radians(Self.normalizedDegrees(meanAnomaly))
        let eccentricAnomaly = meanAnomalyRadians
            + eccentricity * sin(meanAnomalyRadians) * (1 + eccentricity * cos(meanAnomalyRadians))

        let xv = semiMajorAxis * (cos(eccentricAnomaly) - eccentricity)
        let yv = semiMajorAxis * sqrt(1 - eccentricity * eccentricity) * sin(eccentricAnomaly)
        let trueAnomaly = atan2(yv, xv)
        let radius = sqrt(xv * xv + yv * yv)

        let node = Self.radians(longitudeOfAscendingNode)
        let inclinationRadians = Self.radians(inclination)
        let argument = trueAnomaly + Self.radians(argumentOfPerihelion)

        let x = radius * (cos(node) * cos(argument) - sin(node) * sin(argument) * cos(inclinationRadians))
        let y = radius * (sin(node) * cos(argument) + cos(node) * sin(argument) * cos(inclinationRadians))
        let z = radius * sin(argument) * sin(inclinationRadians)

        return (x, y, z)
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }
}
