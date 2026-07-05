import Foundation
import SharedCode
import XCTest
@testable import AstroViewingConditions

@MainActor
final class TargetDetailContentBuilderTests: XCTestCase {

    func testNGC7009KeepsVerifiedMetadataAndRealisticObservingNote() throws {
        let image = try XCTUnwrap(TargetImageManifest.image(for: "ngc7009"))
        XCTAssertTrue(image.isVerified)
        XCTAssertTrue(image.hasCompleteMetadata)
        XCTAssertEqual(image.sourceName, "NASA/ESA Hubble")
        XCTAssertEqual(image.creditText, "NASA, ESA and STScI")
        XCTAssertEqual(image.licenseName, "Public Domain (PD-Hubble)")

        let content = Self.detailContent(id: "ngc7009", name: "NGC 7009 Saturn Nebula", type: .planetaryNebula, image: image)
        XCTAssertEqual(
            content.sections.first(where: { $0.title == "Observing notes" })?.text,
            "Small bright planetary nebula. In a telescope it may look like a tiny blue-green oval; the Saturn-like extensions need higher magnification and good seeing."
        )
    }

    func testM27UsesVisualObservingSpecificDetailTextAndKeepsDynamicFindingData() {
        let content = Self.detailContent(
            id: "m27",
            name: "M27 Dumbbell Nebula",
            type: .planetaryNebula,
            reasons: [.moonInterference],
            direction: "S",
            altitude: 60
        )
        let sections = Dictionary(uniqueKeysWithValues: content.sections.map { ($0.title, $0.text) })

        XCTAssertEqual(
            sections["Why recommended"],
            "This large, bright planetary nebula is well placed during this observing window. The bright Moon may reduce contrast, but M27 is still worth trying because its dumbbell shape can stand out better than many faint nebulae."
        )
        XCTAssertEqual(
            sections["Best equipment"],
            "Use a telescope at low to moderate magnification. A nebula filter may help if available."
        )
        XCTAssertEqual(
            sections["Observing notes"],
            "Visually, M27 usually appears as a grayish fuzzy patch with a dumbbell or apple-core shape. Photos show much more color than you should expect at the eyepiece."
        )
        XCTAssertEqual(
            sections["Finding tips"],
            "Look in Vulpecula near Sagitta and Cygnus. Use low power first, then increase magnification once found."
        )
        XCTAssertNil(sections["How to find it"])
        XCTAssertTrue(sections["Why recommended"]?.contains("large, bright planetary nebula") == true)
        XCTAssertTrue(sections["Why recommended"]?.contains("stand out") == true)
        XCTAssertTrue(sections["Observing notes"]?.contains("grayish fuzzy patch") == true)
        XCTAssertFalse(sections.values.contains(where: { $0.localizedCaseInsensitiveContains("small target") }))
        XCTAssertFalse(sections.values.contains(where: { $0.localizedCaseInsensitiveContains("small bright nebula") }))
    }

    func testFindingTipsUseCuratedAndTypeFallbackGuidanceWithoutRepeatingWhenAndWhere() {
        let doubleCluster = Self.detailContent(
            id: "double-cluster",
            name: "NGC 869/884 Double Cluster",
            type: .openCluster,
            displayTypeNameOverride: "Open Cluster Pair",
            reasons: [.poorWeather],
            direction: "NE",
            altitude: 52
        )
        let clusterSections = Dictionary(uniqueKeysWithValues: doubleCluster.sections.map { ($0.title, $0.text) })
        XCTAssertEqual(doubleCluster.displayType, "Open Cluster Pair")
        XCTAssertNil(clusterSections["How to find it"])
        XCTAssertEqual(
            clusterSections["Finding tips"],
            "Look in Perseus between Cassiopeia and the bright star Mirfak. Use binoculars or a low-power telescope so both clusters fit in the same view."
        )
        XCTAssertFalse(clusterSections["Finding tips"]?.contains("52°") == true)
        XCTAssertFalse(clusterSections["Finding tips"]?.contains("Best from") == true)
        XCTAssertEqual(
            clusterSections["Why recommended"],
            "The Double Cluster is a rewarding wide-field target during this observing window. Clouds may interfere, but if the sky clears, both clusters can fit beautifully in binoculars or a low-power telescope."
        )
        XCTAssertEqual(clusterSections["Best equipment"], "Use binoculars or a low-power telescope to keep both clusters in view.")
        XCTAssertEqual(clusterSections["Observing notes"], "Both clusters can fit in a binocular or low-power telescope view, surrounded by a rich Milky Way star field.")

        let globular = Self.detailContent(name: "Generic Globular", type: .globularCluster)
        XCTAssertEqual(
            globular.sections.first(where: { $0.title == "Finding tips" })?.text,
            "Start with low power to locate the fuzzy core, then increase magnification to try resolving outer stars."
        )
    }

    func testCuratedObservingGuideCatalogPreservesVisualExpectationCopy() throws {
        let doubleCluster = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: "double-cluster"))
        XCTAssertTrue(doubleCluster.findingTips?.contains("Perseus") == true)
        XCTAssertTrue(doubleCluster.findingTips?.contains("Cassiopeia") == true)
        XCTAssertTrue(doubleCluster.findingTips?.contains("Mirfak") == true)

        let m27 = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: "M27"))
        XCTAssertTrue(m27.observingNotes?.contains("grayish fuzzy patch") == true)
        XCTAssertTrue(m27.observingNotes?.contains("Photos show much more color") == true)

        let m16 = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: "m16"))
        XCTAssertTrue(m16.observingNotes?.contains("mainly an imaging and Hubble target") == true)
        XCTAssertFalse(m16.observingNotes?.localizedCaseInsensitiveContains("visible Pillars") == true)

        let m20 = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: "m20"))
        XCTAssertTrue(m20.observingNotes?.contains("do not expect the vivid colors") == true)

        for id in ["m33", "m101"] {
            let guide = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: id))
            XCTAssertTrue(guide.observingNotes?.contains("Low surface brightness") == true, id)
            XCTAssertTrue(guide.observingNotes?.contains("dark-sky challenge") == true, id)
        }
    }

    func testTargetDetailsExposeImageAttributionWhenPresent() {
        let content = Self.detailContent(name: "Moon", targetType: .moon, image: TargetImageManifest.image(for: "moon"))
        XCTAssertEqual(content.imageAttribution, "Image: NASA Johnson Space Center · NASA Public Domain")
    }

    func testM57DetailUnderBrightMoonExplainsCompactNebulaAndContrast() {
        let content = Self.detailContent(
            name: "M57 Ring Nebula",
            type: .planetaryNebula,
            reasons: [.moonInterference],
            summary: "Small bright nebula; well placed despite bright Moon."
        )

        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("small bright nebula"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("Moon"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("contrast"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("small bright nebula"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("contrast"))
    }

    func testEpsilonLyraeDetailRecommendsTelescopeAndHighMagnification() {
        let content = Self.detailContent(
            name: "Epsilon Lyrae",
            type: .doubleStar,
            reasons: [.highAltitude, .astronomicalDarkness, .goodNightQuality],
            summary: "Good target even under bright Moon.",
            direction: "S",
            altitude: 84
        )

        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("double"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("telescope"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("high magnification"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("steady moments"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("split the pair"))
        XCTAssertEqual(content.directionText, "Look south.")
        XCTAssertEqual(content.altitudeDegrees ?? 0, 84, accuracy: 0.01)
        XCTAssertEqual(content.altitudeText, "About 84° high.")
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("bright Moon"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("high in the sky"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("astronomical darkness"))
        XCTAssertNotEqual(
            content.whyRecommended,
            "Good target even under bright Moon. High in the sky during the best window. Visible during astronomical darkness. Weather and sky quality look favorable."
        )
    }

    func testMoonDetailIncludesFilterAndBrightnessGuidance() {
        let content = Self.detailContent(
            name: "Moon",
            targetType: .moon,
            reasons: [.brightFullMoonDeepSkyImpact]
        )

        XCTAssertTrue(content.sectionsText.contains("Moon filter"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("brightness"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("good lunar target"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("faint deep-sky"))
    }

    func testM31UnderBrightMoonPrefersDarkSkyAndWarnsOfWashedOutDetail() {
        let content = Self.detailContent(
            name: "M31 Andromeda Galaxy",
            type: .galaxy,
            reasons: [.moonInterference],
            summary: "High in the sky, but bright Moon will wash out galaxy detail."
        )

        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("wash out"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("dark"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("averted vision"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("wash out"))
    }

    func testLowVenusDetailIncludesWestLowHorizonAndTwilightGuidance() {
        let content = Self.detailContent(
            name: "Venus",
            targetType: .planet,
            reasons: [.lowAltitude, .outsideAstronomicalDarkness],
            direction: "W",
            altitude: 9
        )

        XCTAssertTrue(content.direction?.localizedCaseInsensitiveContains("west") == true)
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("low"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("trees, hills, or buildings"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("twilight"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("low in the sky"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("trees, hills, or buildings"))
    }

    func testTargetDetailIncludesWindowDirectionAltitudeAndNeedsNoOptionalCatalogData() {
        let content = Self.detailContent(name: "Unknown", direction: "S", altitude: 78)

        XCTAssertFalse(content.bestTime.isEmpty)
        XCTAssertEqual(content.direction, "Look south.")
        XCTAssertEqual(content.altitude, "About 78° high.")
        XCTAssertEqual(content.sections.count, 4)
    }

    func testTargetDetailPreservesKnownAzimuthWithoutAddingItToBeginnerRows() {
        let content = Self.detailContent(
            name: "Known Position",
            direction: "S",
            altitude: 84,
            azimuth: 180
        )

        XCTAssertEqual(content.compassDirectionLabel, "S")
        XCTAssertEqual(content.azimuthDegrees ?? 0, 180, accuracy: 0.01)
        XCTAssertEqual(content.azimuthText, "Azimuth 180°")
        XCTAssertEqual(content.directionText, "Look south.")
        XCTAssertEqual(content.altitudeText, "About 84° high.")
    }

    func testTargetDetailWithoutAzimuthLeavesStructuredAzimuthEmpty() {
        let content = Self.detailContent(name: "No Azimuth", azimuth: nil)

        XCTAssertNil(content.azimuthDegrees)
        XCTAssertNil(content.azimuthText)
        XCTAssertFalse(content.sectionsText.localizedCaseInsensitiveContains("azimuth"))
    }

    func testDateNeutralTargetDetailProseDoesNotHardCodeTonight() {
        let content = Self.detailContent(
            name: "Future Target",
            reasons: [.highAltitude, .astronomicalDarkness],
            summary: "A strong target tonight."
        )

        XCTAssertFalse(content.sectionsText.localizedCaseInsensitiveContains("tonight"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("for this night"))
    }

    private static func detailContent(
        id: String? = nil,
        name: String,
        targetType: ObservableTargetType = .deepSky,
        type: DeepSkyObjectType? = nil,
        observingIntent: TargetObservingIntent = .standard,
        displayTypeNameOverride: String? = nil,
        reasons: [TargetRecommendationReason] = [],
        summary: String = "Visible tonight.",
        direction: String? = "S",
        altitude: Double? = 60,
        azimuth: Double? = nil,
        image: TargetImageCredit? = nil
    ) -> TargetDetailContent {
        let start = Date(timeIntervalSince1970: 1_782_790_000)
        let recommendation = TargetRecommendation(
            target: ObservableTarget(
                id: id ?? name.lowercased(),
                name: name,
                type: targetType,
                preferredEquipment: .telescope,
                difficulty: 0.5,
                observingIntent: observingIntent,
                displayTypeNameOverride: displayTypeNameOverride,
                deepSkyObjectType: type,
                image: image
            ),
            score: 75,
            visibilityWindow: TargetVisibilityWindow(
                start: start,
                end: start.addingTimeInterval(7_200),
                bestTime: start.addingTimeInterval(3_600),
                maxAltitude: altitude,
                direction: direction,
                azimuth: azimuth
            ),
            reasons: reasons,
            summary: summary
        )
        return TargetDetailContentBuilder().build(
            from: recommendation,
            timeZone: TimeZone(secondsFromGMT: 0)
        )
    }
}

