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
                    moonInterferenceSensitivity: TargetMetadata.moonSensitivity(objectType: entry.objectType, surfaceBrightness: entry.surfaceBrightness),
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

    // Ordered objective metadata belongs to the engine; names remain host copy.
    private static let solarSystemNames = [
        "moon": "Moon", "venus": "Venus", "mars": "Mars", "jupiter": "Jupiter", "saturn": "Saturn"
    ]
    private static let solarSystemTargets = TargetMetadata.solarSystemCandidates.map { entry in
        ObservableTarget(id: entry.id, name: solarSystemNames[entry.id]!,
            type: ObservableTargetType(rawValue: entry.type.rawValue)!,
            preferredEquipment: entry.preferredEquipment, difficulty: entry.difficulty,
            observingIntent: entry.observingIntent)
    }

}

public struct DeepSkyTargetPositionProvider: TargetPositionProvider {
    private let entriesByID: [String: DeepSkyCatalogEntry]
    private let minimumAltitude: Double
    private let sampleInterval: TimeInterval

    public init(
        catalog: any DeepSkyCatalogProvider = CuratedDeepSkyCatalogProvider(),
        minimumAltitude: Double = DeepSkyObservation.defaultMinimumAltitude,
        sampleInterval: TimeInterval = DeepSkyObservation.defaultSampleInterval
    ) {
        self.entriesByID = Dictionary(uniqueKeysWithValues: catalog.entries().map { ($0.id, $0) })
        self.minimumAltitude = minimumAltitude
        self.sampleInterval = sampleInterval
    }

    /// Sampling, threshold and window semantics live in the shared engine; see
    /// contracts/procedures/deep-sky-observation.md. This adapter keeps the host
    /// catalog/target guard and the host `TargetVisibilityWindow` shape.
    public func visibilityWindows(
        for target: ObservableTarget,
        context: TargetRecommendationContext
    ) -> [TargetVisibilityWindow] {
        guard target.type == .deepSky, let entry = entriesByID[target.id] else { return [] }
        let samples = DeepSkyObservation.samples(
            rightAscensionHours: entry.rightAscension,
            declinationDegrees: entry.declination,
            latitudeDegrees: context.location.latitude,
            longitudeDegrees: context.location.longitude,
            start: context.astronomicalNightStart,
            end: context.astronomicalNightEnd,
            sampleInterval: sampleInterval
        )
        let windows = DeepSkyObservation.windows(
            from: samples,
            intervalStart: context.astronomicalNightStart,
            intervalEnd: context.astronomicalNightEnd,
            minimumAltitude: minimumAltitude
        )
        Self.logValidation(
            entry: entry,
            samples: samples,
            windows: windows,
            minimumAltitude: minimumAltitude,
            context: context
        )
        return windows.map { window in
            TargetVisibilityWindow(
                start: window.start,
                end: window.end,
                bestTime: window.bestTime,
                maxAltitude: window.maxAltitude,
                direction: window.direction,
                azimuth: window.azimuth
            )
        }
    }

    private static func compassDirection(for azimuth: Double) -> String {
        HorizontalCoordinates.compassDirection(forAzimuth: azimuth)
    }

    private static func logValidation(
        entry: DeepSkyCatalogEntry,
        samples: [DeepSkyObservation.Sample],
        windows: [DeepSkyObservation.Window],
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
            bestTime: \(best.map { formatter.string(from: $0.time) } ?? "n/a")
            visibilityWindowAboveMinimum: \(windowsText)
            altitudeAtBestTime: \(best.map { String(format: "%.1f°", $0.altitude) } ?? "n/a")
            azimuthAtBestTime: \(best.map { String(format: "%.1f° (%@)", $0.azimuth, compassDirection(for: $0.azimuth)) } ?? "n/a")
            """
        )
        */
#endif
    }
}
