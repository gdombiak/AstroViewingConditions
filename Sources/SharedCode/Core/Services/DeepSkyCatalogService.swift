import Foundation

public struct DeepSkyCatalogEntry: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let commonName: String
    public let catalogName: String
    public let objectType: DeepSkyObjectType
    public let constellation: String
    public let rightAscension: Double
    public let declination: Double
    public let magnitude: Double
    public let apparentSize: String
    public let surfaceBrightness: Double?
    public let difficulty: Double
    public let observingIntent: TargetObservingIntent
    public let displayTypeNameOverride: String?
    public let recommendedEquipment: TargetEquipmentType
    public let notes: String
    public let image: TargetImageCredit?

    public init(
        id: String,
        commonName: String,
        catalogName: String,
        objectType: DeepSkyObjectType,
        constellation: String,
        rightAscension: Double,
        declination: Double,
        magnitude: Double,
        apparentSize: String,
        surfaceBrightness: Double? = nil,
        difficulty: Double,
        observingIntent: TargetObservingIntent,
        recommendedEquipment: TargetEquipmentType,
        notes: String,
        image: TargetImageCredit? = nil,
        displayTypeNameOverride: String? = nil
    ) {
        self.id = id
        self.commonName = commonName
        self.catalogName = catalogName
        self.objectType = objectType
        self.constellation = constellation
        self.rightAscension = rightAscension
        self.declination = declination
        self.magnitude = magnitude
        self.apparentSize = apparentSize
        self.surfaceBrightness = surfaceBrightness
        self.difficulty = min(max(difficulty, 0), 1)
        self.observingIntent = observingIntent
        self.displayTypeNameOverride = displayTypeNameOverride
        self.recommendedEquipment = recommendedEquipment
        self.notes = notes
        self.image = image
    }
}

public protocol DeepSkyCatalogProvider: Sendable {
    func entries() -> [DeepSkyCatalogEntry]
}

public struct CuratedDeepSkyCatalogProvider: DeepSkyCatalogProvider {
    public init() {}

    public func entries() -> [DeepSkyCatalogEntry] {
        Self.catalog
    }

    private static let catalog: [DeepSkyCatalogEntry] = [
        entry("m13", "M13 Hercules Cluster", "M13", .globularCluster, "Hercules", 16.6949, 36.4613, 5.8, "20 arcmin", 12.0, 0.55, .binoculars, .easy, "Bright northern globular cluster.", image: TargetImageManifest.image(for: "m13")),
        entry("m31", "M31 Andromeda Galaxy", "M31", .galaxy, "Andromeda", 0.7123, 41.2692, 3.4, "190 x 60 arcmin", 13.5, 0.45, .binoculars, .easy, "Easy to locate, though suburban views may show mostly its bright core rather than the photo-like disk.", image: TargetImageManifest.image(for: "m31")),
        entry("m2", "M2 Globular Cluster", "M2", .globularCluster, "Aquarius", 21.5575, -0.8233, 6.2, "16 arcmin", 12.5, 0.55, .binoculars, .standard, "Compact globular cluster.", image: TargetImageManifest.image(for: "m2")),
        entry("m30", "M30 Globular Cluster", "M30", .globularCluster, "Capricornus", 21.6728, -23.1799, 7.2, "12 arcmin", 11.0, 0.65, .smallTelescope, .standard, "Dense globular cluster with a bright core."),
        entry("m52", "M52 Open Cluster", "M52", .openCluster, "Cassiopeia", 23.4133, 61.5931, 6.9, "13 arcmin", 12.0, 0.45, .binoculars, .standard, "Rich open cluster in a crowded Milky Way field.", image: TargetImageManifest.image(for: "m52")),
        entry("m11", "M11 Wild Duck Cluster", "M11", .openCluster, "Scutum", 18.8514, -6.2700, 6.3, "14 arcmin", 11.1, 0.4, .binoculars, .easy, "Bright, compact open cluster.", image: TargetImageManifest.image(for: "m11")),
        entry("m57", "M57 Ring Nebula", "M57", .planetaryNebula, "Lyra", 18.8931, 33.0292, 8.8, "1.4 x 1.0 arcmin", 9.3, 0.55, .smallTelescope, .standard, "Small, high-surface-brightness planetary nebula.", image: TargetImageManifest.image(for: "m57")),
        entry("m27", "M27 Dumbbell Nebula", "M27", .planetaryNebula, "Vulpecula", 19.9934, 22.7212, 7.5, "8.0 x 5.7 arcmin", 11.3, 0.5, .binoculars, .standard, "Large, bright planetary nebula.", image: TargetImageManifest.image(for: "m27")),
        entry("ngc7009", "NGC 7009 Saturn Nebula", "NGC 7009", .planetaryNebula, "Aquarius", 21.0697, -11.3633, 8.0, "0.7 x 0.4 arcmin", 8.1, 0.5, .smallTelescope, .standard, "Compact planetary nebula that tolerates moonlight well.", image: TargetImageManifest.image(for: "ngc7009")),
        entry("ngc7293", "NGC 7293 Helix Nebula", "NGC 7293", .planetaryNebula, "Aquarius", 22.4933, -20.8372, 7.6, "25 x 20 arcmin", 13.6, 0.8, .telescope, .challenge, "Very large planetary nebula with low surface brightness."),
        entry("m51", "M51 Whirlpool Galaxy", "M51", .galaxy, "Canes Venatici", 13.4978, 47.1952, 8.4, "11 x 7 arcmin", 12.9, 0.75, .telescope, .challenge, "Face-on galaxy whose spiral detail needs dark skies."),
        entry("m64", "M64 Black Eye Galaxy", "M64", .galaxy, "Coma Berenices", 12.9455, 21.6827, 8.5, "10 x 5 arcmin", 12.8, 0.7, .telescope, .challenge, "Galaxy with a prominent dark dust feature."),
        entry("m81", "M81 Bode's Galaxy", "M81", .galaxy, "Ursa Major", 9.9259, 69.0653, 6.9, "27 x 14 arcmin", 13.0, 0.55, .binoculars, .standard, "Bright galaxy, though extended detail favors dark skies."),
        entry("m82", "M82 Cigar Galaxy", "M82", .galaxy, "Ursa Major", 9.9313, 69.6797, 8.4, "11 x 5 arcmin", 12.7, 0.6, .smallTelescope, .standard, "High-surface-brightness edge-on galaxy."),
        entry("m92", "M92 Globular Cluster", "M92", .globularCluster, "Hercules", 17.2854, 43.1365, 6.4, "14 arcmin", 11.2, 0.5, .binoculars, .standard, "Bright compact globular cluster.", image: TargetImageManifest.image(for: "m92")),
        entry("albireo", "Albireo", "Beta Cygni", .doubleStar, "Cygnus", 19.5120, 27.9597, 3.1, "34 arcsec", nil, 0.25, .smallTelescope, .easy, "Colorful gold-and-blue double star.", image: TargetImageManifest.image(for: "albireo")),
        entry("epsilon-lyrae", "Epsilon Lyrae", "Epsilon Lyrae", .doubleStar, "Lyra", 18.7380, 39.6701, 4.7, "208 arcsec", nil, 0.4, .smallTelescope, .standard, "The Double Double; higher power resolves both pairs.", image: TargetImageManifest.image(for: "epsilon-lyrae")),
        entry("m45", "M45 Pleiades", "M45", .openCluster, "Taurus", 3.7833, 24.1167, 1.6, "110 arcmin", nil, 0.15, .binoculars, .easy, "Excellent beginner target; best with binoculars or very low power.", image: TargetImageManifest.image(for: "m45")),
        entry("m42", "M42 Orion Nebula", "M42", .diffuseNebula, "Orion", 5.5881, -5.3911, 4.0, "85 x 60 arcmin", 13.0, 0.25, .binoculars, .easy, "Excellent beginner nebula; visually it is a gray-green fuzzy patch, not a colorful photograph.", image: TargetImageManifest.image(for: "m42")),
        entry("double-cluster", "NGC 869/884 Double Cluster", "NGC 869/884", .openCluster, "Perseus", 2.3333, 57.1333, 3.7, "60 arcmin", nil, 0.2, .binoculars, .easy, "A rewarding pair of clusters for binoculars or low-power telescopes.", displayTypeNameOverride: "Open Cluster Pair"),
        entry("m5", "M5 Globular Cluster", "M5", .globularCluster, "Serpens", 15.3092, 2.0810, 5.7, "23 arcmin", 12.0, 0.5, .smallTelescope, .standard, "Good telescope target; higher magnification may resolve outer stars.", image: TargetImageManifest.image(for: "m5")),
        entry("m3", "M3 Globular Cluster", "M3", .globularCluster, "Canes Venatici", 13.7031, 28.3773, 6.2, "18 arcmin", 12.1, 0.5, .smallTelescope, .standard, "Bright spring and summer globular cluster for a telescope.", image: TargetImageManifest.image(for: "m3")),
        entry("m16", "M16 Eagle Nebula", "M16", .diffuseNebula, "Serpens", 18.3133, -13.8067, 6.0, "35 x 28 arcmin", 12.0, 0.6, .telescope, .standard, "The cluster and faint nebulosity may be visible; the Pillars of Creation are mainly an imaging target."),
        entry("m20", "M20 Trifid Nebula", "M20", .diffuseNebula, "Sagittarius", 18.0347, -23.0297, 6.3, "28 arcmin", 12.4, 0.65, .telescope, .standard, "Look for faint gray nebulosity and possible dark lanes under good dark skies; do not expect photographic color."),
        entry("m33", "M33 Triangulum Galaxy", "M33", .galaxy, "Triangulum", 1.5641, 30.6602, 5.7, "70 x 42 arcmin", 14.2, 0.8, .binoculars, .challenge, "Dark-sky challenge with low surface brightness; difficult from suburban skies.", image: TargetImageManifest.image(for: "m33")),
        entry("m101", "M101 Pinwheel Galaxy", "M101", .galaxy, "Ursa Major", 14.0535, 54.3488, 7.9, "29 x 27 arcmin", 14.8, 0.85, .telescope, .challenge, "Rewarding dark-sky challenge with low surface brightness; difficult from suburban skies.", image: TargetImageManifest.image(for: "m101"))
    ]

    private static func entry(
        _ id: String,
        _ commonName: String,
        _ catalogName: String,
        _ objectType: DeepSkyObjectType,
        _ constellation: String,
        _ rightAscension: Double,
        _ declination: Double,
        _ magnitude: Double,
        _ apparentSize: String,
        _ surfaceBrightness: Double?,
        _ difficulty: Double,
        _ equipment: TargetEquipmentType,
        _ observingIntent: TargetObservingIntent,
        _ notes: String,
        image: TargetImageCredit? = nil,
        displayTypeNameOverride: String? = nil
    ) -> DeepSkyCatalogEntry {
        DeepSkyCatalogEntry(
            id: id,
            commonName: commonName,
            catalogName: catalogName,
            objectType: objectType,
            constellation: constellation,
            rightAscension: rightAscension,
            declination: declination,
            magnitude: magnitude,
            apparentSize: apparentSize,
            surfaceBrightness: surfaceBrightness,
            difficulty: difficulty,
            observingIntent: observingIntent,
            recommendedEquipment: equipment,
            notes: notes,
            image: image,
            displayTypeNameOverride: displayTypeNameOverride
        )
    }
}

public struct DefaultTargetCatalogProvider: TargetCatalogProvider {
    private let deepSkyCatalog: any DeepSkyCatalogProvider

    public init(deepSkyCatalog: any DeepSkyCatalogProvider = CuratedDeepSkyCatalogProvider()) {
        self.deepSkyCatalog = deepSkyCatalog
    }

    public func targets(for context: TargetRecommendationContext) -> [ObservableTarget] {
        Self.solarSystemTargets + deepSkyCatalog.entries().map { entry in
            ObservableTarget(
                id: entry.id,
                name: entry.commonName,
                type: .deepSky,
                preferredEquipment: entry.recommendedEquipment,
                difficulty: entry.difficulty,
                observingIntent: entry.observingIntent,
                displayTypeNameOverride: entry.displayTypeNameOverride,
                deepSkyObjectType: entry.objectType,
                moonInterferenceSensitivity: Self.moonInterferenceSensitivity(for: entry),
                image: entry.image
            )
        }
    }

    private static func moonInterferenceSensitivity(for entry: DeepSkyCatalogEntry) -> Double {
        guard entry.objectType == .planetaryNebula else { return 1 }
        guard let surfaceBrightness = entry.surfaceBrightness else { return 1 }
        if surfaceBrightness <= 10 { return 0.65 }
        if surfaceBrightness >= 13 { return 1.2 }
        return 1
    }

    // TODO: Consider adding Uranus and Neptune later as challenge planet targets once planet visibility support is verified.
    private static let solarSystemTargets = [
        ObservableTarget(id: "moon", name: "Moon", type: .moon, preferredEquipment: .nakedEye, difficulty: 0.1, observingIntent: .easy, image: TargetImageManifest.image(for: "moon")),
        ObservableTarget(id: "venus", name: "Venus", type: .planet, preferredEquipment: .nakedEye, difficulty: 0.1, observingIntent: .easy, image: TargetImageManifest.image(for: "venus")),
        ObservableTarget(id: "mars", name: "Mars", type: .planet, preferredEquipment: .nakedEye, difficulty: 0.2, observingIntent: .standard, image: TargetImageManifest.image(for: "mars")),
        ObservableTarget(id: "jupiter", name: "Jupiter", type: .planet, preferredEquipment: .smallTelescope, difficulty: 0.25, observingIntent: .easy, image: TargetImageManifest.image(for: "jupiter")),
        ObservableTarget(id: "saturn", name: "Saturn", type: .planet, preferredEquipment: .smallTelescope, difficulty: 0.35, observingIntent: .easy, image: TargetImageManifest.image(for: "saturn"))
    ]
}

public struct DeepSkyTargetPositionProvider: TargetPositionProvider {
    private let entriesByID: [String: DeepSkyCatalogEntry]
    private let minimumAltitude: Double
    private let sampleInterval: TimeInterval

    public init(
        catalog: any DeepSkyCatalogProvider = CuratedDeepSkyCatalogProvider(),
        minimumAltitude: Double = 15,
        sampleInterval: TimeInterval = 15 * 60
    ) {
        self.entriesByID = Dictionary(uniqueKeysWithValues: catalog.entries().map { ($0.id, $0) })
        self.minimumAltitude = minimumAltitude
        self.sampleInterval = sampleInterval
    }

    public func visibilityWindows(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> [TargetVisibilityWindow] {
        guard target.type == .deepSky, let entry = entriesByID[target.id] else { return [] }
        let samples = sampledPositions(for: entry, context: context)
        let windows = visibilityWindows(from: samples, context: context)
        Self.logValidation(
            entry: entry,
            samples: samples,
            windows: windows,
            minimumAltitude: minimumAltitude,
            context: context
        )
        return windows
    }

    private func visibilityWindows(
        from samples: [HorizontalPosition],
        context: TargetRecommendationContext
    ) -> [TargetVisibilityWindow] {
        var windows: [TargetVisibilityWindow] = []
        var runStartIndex: Int?

        for index in samples.indices {
            let isVisible = samples[index].altitude >= minimumAltitude
            if isVisible, runStartIndex == nil {
                runStartIndex = index
            }

            let runEnded = runStartIndex != nil && (!isVisible || index == samples.index(before: samples.endIndex))
            guard runEnded, let startIndex = runStartIndex else { continue }

            let endIndex = isVisible ? index : samples.index(before: index)
            let run = samples[startIndex...endIndex]
            guard let best = run.max(by: { $0.altitude < $1.altitude }) else { continue }

            let start = startIndex == samples.startIndex
                ? context.astronomicalNightStart
                : thresholdCrossing(between: samples[startIndex - 1], and: samples[startIndex])
            let end = endIndex == samples.index(before: samples.endIndex)
                ? context.astronomicalNightEnd
                : thresholdCrossing(between: samples[endIndex], and: samples[endIndex + 1])

            windows.append(TargetVisibilityWindow(
                start: start,
                end: end,
                bestTime: best.date,
                maxAltitude: best.altitude,
                direction: Self.compassDirection(for: best.azimuth),
                azimuth: best.azimuth
            ))
            runStartIndex = nil
        }

        return windows
    }

    private func thresholdCrossing(
        between first: HorizontalPosition,
        and second: HorizontalPosition
    ) -> Date {
        let altitudeChange = second.altitude - first.altitude
        guard abs(altitudeChange) > 0.0001 else { return first.date }
        let fraction = min(max((minimumAltitude - first.altitude) / altitudeChange, 0), 1)
        return first.date.addingTimeInterval(second.date.timeIntervalSince(first.date) * fraction)
    }

    private func sampledPositions(
        for entry: DeepSkyCatalogEntry,
        context: TargetRecommendationContext
    ) -> [HorizontalPosition] {
        var positions: [HorizontalPosition] = []
        var date = context.astronomicalNightStart
        while date <= context.astronomicalNightEnd {
            positions.append(Self.horizontalPosition(
                rightAscensionHours: entry.rightAscension,
                declinationDegrees: entry.declination,
                date: date,
                latitudeDegrees: context.location.latitude,
                longitudeDegrees: context.location.longitude
            ))
            date = date.addingTimeInterval(sampleInterval)
        }
        return positions
    }

    private static func horizontalPosition(
        rightAscensionHours: Double,
        declinationDegrees: Double,
        date: Date,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> HorizontalPosition {
        let julianDate = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let daysSinceJ2000 = julianDate - 2_451_545.0
        let greenwichSiderealDegrees = normalizedDegrees(280.46061837 + 360.98564736629 * daysSinceJ2000)
        let localSiderealDegrees = normalizedDegrees(greenwichSiderealDegrees + longitudeDegrees)
        let hourAngle = normalizedSignedDegrees(localSiderealDegrees - rightAscensionHours * 15).radians
        let declination = declinationDegrees.radians
        let latitude = latitudeDegrees.radians

        let altitude = asin(
            sin(declination) * sin(latitude)
                + cos(declination) * cos(latitude) * cos(hourAngle)
        )
        let azimuth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude)
        ) + .pi

        return HorizontalPosition(
            date: date,
            altitude: altitude.degrees,
            azimuth: normalizedDegrees(azimuth.degrees)
        )
    }

    private static func compassDirection(for azimuth: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return directions[Int((normalizedDegrees(azimuth) + 22.5) / 45) % directions.count]
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result >= 0 ? result : result + 360
    }

    private static func normalizedSignedDegrees(_ value: Double) -> Double {
        let normalized = normalizedDegrees(value)
        return normalized > 180 ? normalized - 360 : normalized
    }

    private static func logValidation(
        entry: DeepSkyCatalogEntry,
        samples: [HorizontalPosition],
        windows: [TargetVisibilityWindow],
        minimumAltitude: Double,
        context: TargetRecommendationContext
    ) {
#if DEBUG
        /*
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current

        let altitudeRange: String
        if let minimum = samples.map(\.altitude).min(), let maximum = samples.map(\.altitude).max() {
            altitudeRange = String(format: "%.1f°...%.1f°", minimum, maximum)
        } else {
            altitudeRange = "n/a"
        }

        let visibleSamples = samples.filter { $0.altitude >= minimumAltitude }
        let best = visibleSamples.max(by: { $0.altitude < $1.altitude })
        let windowsText = windows.isEmpty
            ? "none"
            : windows.map {
                "\(formatter.string(from: $0.start)) - \(formatter.string(from: $0.end))"
            }.joined(separator: " | ")

        debugPrint(
            """
            [BestTargetsDeepSkyPosition]
            target: \(entry.commonName) (\(entry.objectType.displayName))
            observer: \(String(format: "%.4f, %.4f", context.location.latitude, context.location.longitude))
            astronomicalNight: \(formatter.string(from: context.astronomicalNightStart)) - \(formatter.string(from: context.astronomicalNightEnd))
            minimumAltitude: \(String(format: "%.1f°", minimumAltitude))
            sampledAltitudeRange: \(altitudeRange)
            bestTime: \(best.map { formatter.string(from: $0.date) } ?? "n/a")
            visibilityWindowAboveMinimum: \(windowsText)
            altitudeAtBestTime: \(best.map { String(format: "%.1f°", $0.altitude) } ?? "n/a")
            azimuthAtBestTime: \(best.map { String(format: "%.1f° (%@)", $0.azimuth, compassDirection(for: $0.azimuth)) } ?? "n/a")
            """
        )
        */
#endif
    }

    private struct HorizontalPosition {
        let date: Date
        let altitude: Double
        let azimuth: Double
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
