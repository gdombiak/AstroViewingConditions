import Foundation

public struct DeepSkyCatalogEntry: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let commonName: String
    public let catalogName: String
    public let objectType: DeepSkyObjectType
    public let constellation: String
    public let rightAscension: Double
    public let declination: Double
    /// Integrated visual magnitude when available; extended-object values are source-dependent.
    public let magnitude: Double
    public let apparentSize: String
    /// Approximate visual surface brightness in magnitudes per square arcminute, when available.
    public let surfaceBrightness: Double?
    /// App-specific observing difficulty heuristic on a 0...1 scale, not a catalog measurement.
    public let difficulty: Double
    public let observingIntent: TargetObservingIntent
    public let displayTypeNameOverride: String?
    public let recommendedEquipment: TargetEquipmentType
    public let notes: String

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
    }
}

public protocol DeepSkyCatalogProviding: Sendable {
    func entries() -> [DeepSkyCatalogEntry]
}

public struct CuratedDeepSkyCatalogProvider: DeepSkyCatalogProviding {
    public init() {}

    public func entries() -> [DeepSkyCatalogEntry] {
        Self.catalog
    }

    private static let catalog: [DeepSkyCatalogEntry] = [
        entry("m13", "M13 Hercules Cluster", "M13", .globularCluster, "Hercules", 16.6949, 36.4613, 5.8, "20 arcmin", 12.0, 0.55, .binoculars, .easy, "Bright northern globular cluster."),
        entry("m31", "M31 Andromeda Galaxy", "M31", .galaxy, "Andromeda", 0.7123, 41.2692, 3.4, "190 x 60 arcmin", 13.5, 0.45, .binoculars, .easy, "Easy to locate, though suburban views may show mostly its bright core rather than the photo-like disk."),
        entry("m2", "M2 Globular Cluster", "M2", .globularCluster, "Aquarius", 21.5575, -0.8233, 6.2, "16 arcmin", 12.5, 0.55, .binoculars, .standard, "Compact globular cluster."),
        entry("m30", "M30 Globular Cluster", "M30", .globularCluster, "Capricornus", 21.6728, -23.1799, 7.2, "12 arcmin", 11.0, 0.65, .smallTelescope, .standard, "Dense globular cluster with a bright core."),
        entry("m52", "M52 Open Cluster", "M52", .openCluster, "Cassiopeia", 23.4133, 61.5931, 6.9, "13 arcmin", 12.0, 0.45, .binoculars, .standard, "Rich open cluster in a crowded Milky Way field."),
        entry("m11", "M11 Wild Duck Cluster", "M11", .openCluster, "Scutum", 18.8514, -6.2700, 6.3, "14 arcmin", 11.1, 0.4, .binoculars, .easy, "Bright, compact open cluster."),
        entry("m36", "M36 Pinwheel Cluster", "M36", .openCluster, "Auriga", 5.6017, 34.1400, 6.3, "12 arcmin", nil, 0.25, .binoculars, .easy, "Bright young open cluster that is easy to find with binoculars or a small telescope."),
        entry("m38", "M38 Starfish Cluster", "M38", .openCluster, "Auriga", 5.4783, 35.8333, 7.4, "21 arcmin", nil, 0.4, .binoculars, .standard, "Large open cluster whose brighter stars form a distinctive cross or starfish pattern."),
        entry("m57", "M57 Ring Nebula", "M57", .planetaryNebula, "Lyra", 18.8931, 33.0292, 8.8, "1.4 x 1.0 arcmin", 9.3, 0.55, .smallTelescope, .standard, "Small, high-surface-brightness planetary nebula."),
        entry("m27", "M27 Dumbbell Nebula", "M27", .planetaryNebula, "Vulpecula", 19.9934, 22.7212, 7.5, "8.0 x 5.7 arcmin", 11.3, 0.5, .binoculars, .standard, "Large, bright planetary nebula."),
        entry("ngc7009", "NGC 7009 Saturn Nebula", "NGC 7009", .planetaryNebula, "Aquarius", 21.0697, -11.3633, 8.0, "0.7 x 0.4 arcmin", 8.1, 0.5, .smallTelescope, .standard, "Compact planetary nebula that tolerates moonlight well."),
        entry("ngc7293", "NGC 7293 Helix Nebula", "NGC 7293", .planetaryNebula, "Aquarius", 22.4933, -20.8372, 7.6, "25 x 20 arcmin", 13.6, 0.8, .telescope, .challenge, "Very large planetary nebula with low surface brightness."),
        entry("m51", "M51 Whirlpool Galaxy", "M51", .galaxy, "Canes Venatici", 13.4978, 47.1952, 8.4, "11 x 7 arcmin", 12.9, 0.75, .telescope, .challenge, "Face-on galaxy whose spiral detail needs dark skies."),
        entry("m64", "M64 Black Eye Galaxy", "M64", .galaxy, "Coma Berenices", 12.9455, 21.6827, 8.5, "10 x 5 arcmin", 12.8, 0.7, .telescope, .challenge, "Galaxy with a prominent dark dust feature."),
        entry("m77", "M77 Cetus A", "M77", .galaxy, "Cetus", 2.7113, -0.0133, 9.6, "7.1 x 6.0 arcmin", 13.0, 0.8, .telescope, .challenge, "Galaxy with a bright compact core; dark skies are needed to see more than its central region."),
        entry("m81", "M81 Bode's Galaxy", "M81", .galaxy, "Ursa Major", 9.9259, 69.0653, 6.9, "27 x 14 arcmin", 13.0, 0.55, .binoculars, .standard, "Bright galaxy, though extended detail favors dark skies."),
        entry("m82", "M82 Cigar Galaxy", "M82", .galaxy, "Ursa Major", 9.9313, 69.6797, 8.4, "11 x 5 arcmin", 12.7, 0.6, .smallTelescope, .standard, "High-surface-brightness edge-on galaxy."),
        entry("m92", "M92 Globular Cluster", "M92", .globularCluster, "Hercules", 17.2854, 43.1365, 6.4, "14 arcmin", 11.2, 0.5, .binoculars, .standard, "Bright compact globular cluster."),
        entry("albireo", "Albireo", "Beta Cygni", .doubleStar, "Cygnus", 19.5120, 27.9597, 3.1, "34 arcsec", nil, 0.25, .smallTelescope, .easy, "Colorful gold-and-blue double star."),
        entry("epsilon-lyrae", "Epsilon Lyrae", "Epsilon Lyrae", .doubleStar, "Lyra", 18.7380, 39.6701, 4.7, "208 arcsec", nil, 0.4, .smallTelescope, .standard, "The Double Double; higher power resolves both pairs."),
        entry("m45", "M45 Pleiades", "M45", .openCluster, "Taurus", 3.7833, 24.1167, 1.6, "110 arcmin", nil, 0.15, .binoculars, .easy, "Excellent beginner target; best with binoculars or very low power."),
        entry("m42", "M42 Orion Nebula", "M42", .diffuseNebula, "Orion", 5.5881, -5.3911, 4.0, "85 x 60 arcmin", 13.0, 0.25, .binoculars, .easy, "Excellent beginner nebula; visually it is a gray-green fuzzy patch, not a colorful photograph."),
        entry("double-cluster", "NGC 869/884 Double Cluster", "NGC 869/884", .openCluster, "Perseus", 2.3333, 57.1333, 3.7, "60 arcmin", nil, 0.2, .binoculars, .easy, "A rewarding pair of clusters for binoculars or low-power telescopes.", displayTypeNameOverride: "Open Cluster Pair"),
        entry("m5", "M5 Globular Cluster", "M5", .globularCluster, "Serpens", 15.3092, 2.0810, 5.7, "23 arcmin", 12.0, 0.5, .smallTelescope, .standard, "Good telescope target; higher magnification may resolve outer stars."),
        entry("m3", "M3 Globular Cluster", "M3", .globularCluster, "Canes Venatici", 13.7031, 28.3773, 6.2, "18 arcmin", 12.1, 0.5, .smallTelescope, .standard, "Bright spring and summer globular cluster for a telescope."),
        entry("m16", "M16 Eagle Nebula", "M16", .diffuseNebula, "Serpens", 18.3133, -13.8067, 6.0, "35 x 28 arcmin", 12.0, 0.6, .telescope, .standard, "The cluster and faint nebulosity may be visible; the Pillars of Creation are mainly an imaging target."),
        entry("m20", "M20 Trifid Nebula", "M20", .diffuseNebula, "Sagittarius", 18.0433, -23.0297, 6.3, "28 arcmin", 12.4, 0.65, .telescope, .standard, "Look for faint gray nebulosity and possible dark lanes under good dark skies; do not expect photographic color."),
        entry("m33", "M33 Triangulum Galaxy", "M33", .galaxy, "Triangulum", 1.5641, 30.6602, 5.7, "70 x 42 arcmin", 14.2, 0.8, .binoculars, .challenge, "Dark-sky challenge with low surface brightness; difficult from suburban skies."),
        entry("m101", "M101 Pinwheel Galaxy", "M101", .galaxy, "Ursa Major", 14.0535, 54.3488, 7.9, "29 x 27 arcmin", 14.8, 0.85, .telescope, .challenge, "Rewarding dark-sky challenge with low surface brightness; difficult from suburban skies.")
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
            displayTypeNameOverride: displayTypeNameOverride
        )
    }
}
