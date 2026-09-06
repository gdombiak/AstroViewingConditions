import Foundation
import AstroEngine

/// Host catalog protocol. Engine `DeepSkyCatalogEntry` has no image field;
/// injected providers may supply a credit via `imageCredit(for:)`.
public protocol DeepSkyCatalogProvider: DeepSkyCatalogProviding {
    func imageCredit(for id: String) -> TargetImageCredit?
}

extension DeepSkyCatalogProvider {
    public func imageCredit(for id: String) -> TargetImageCredit? { nil }
}

extension CuratedDeepSkyCatalogProvider: DeepSkyCatalogProvider {}

public struct DefaultTargetCatalogProvider: TargetCatalogProvider {
    private let deepSkyCatalog: any DeepSkyCatalogProvider

    public init(deepSkyCatalog: any DeepSkyCatalogProvider = CuratedDeepSkyCatalogProvider()) {
        self.deepSkyCatalog = deepSkyCatalog
    }

    public func targets(for context: TargetRecommendationContext) -> [ObservableTarget] {
        Self.solarSystemTargets.map(Self.attachingHostImage)
            + deepSkyCatalog.entries().map { entry in
            Self.attachingHostImage(
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
                    image: deepSkyCatalog.imageCredit(for: entry.id)
                )
            )
        }
    }

    /// Host-side image credits. An injected entry credit wins; otherwise the
    /// bundled manifest is used. Curated catalog data does not call the manifest.
    private static func attachingHostImage(_ target: ObservableTarget) -> ObservableTarget {
        ObservableTarget(
            id: target.id,
            name: target.name,
            type: target.type,
            preferredEquipment: target.preferredEquipment,
            difficulty: target.difficulty,
            observingIntent: target.observingIntent,
            displayTypeNameOverride: target.displayTypeNameOverride,
            deepSkyObjectType: target.deepSkyObjectType,
            moonInterferenceSensitivity: target.moonInterferenceSensitivity,
            image: target.image ?? TargetImageManifest.image(for: target.id)
        )
    }

    private static func moonInterferenceSensitivity(for entry: DeepSkyCatalogEntry) -> Double {
        let sensitivity = EngineCalibration.current.targetScoring.moon.deep_sky_interference_sensitivity
        guard entry.objectType == .planetaryNebula else { return sensitivity.non_planetary_nebula }
        guard let surfaceBrightness = entry.surfaceBrightness else { return sensitivity.default }
        let nebula = sensitivity.planetary_nebula_by_surface_brightness
        if surfaceBrightness <= nebula.high_surface_brightness_max { return nebula.high_surface_brightness_sensitivity }
        if surfaceBrightness >= nebula.low_surface_brightness_min { return nebula.low_surface_brightness_sensitivity }
        return nebula.mid_sensitivity
    }

    // TODO: Consider adding Uranus and Neptune later as challenge planet targets once planet visibility support is verified.
    private static let solarSystemTargets = [
        ObservableTarget(id: "moon", name: "Moon", type: .moon, preferredEquipment: .nakedEye, difficulty: 0.1, observingIntent: .easy),
        ObservableTarget(id: "venus", name: "Venus", type: .planet, preferredEquipment: .nakedEye, difficulty: 0.1, observingIntent: .easy),
        ObservableTarget(id: "mars", name: "Mars", type: .planet, preferredEquipment: .nakedEye, difficulty: 0.2, observingIntent: .standard),
        ObservableTarget(id: "jupiter", name: "Jupiter", type: .planet, preferredEquipment: .smallTelescope, difficulty: 0.25, observingIntent: .easy),
        ObservableTarget(id: "saturn", name: "Saturn", type: .planet, preferredEquipment: .smallTelescope, difficulty: 0.35, observingIntent: .easy)
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
