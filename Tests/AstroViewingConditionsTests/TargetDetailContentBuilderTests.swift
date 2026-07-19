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
            "Small bright planetary nebula that may look like a tiny blue-green oval; its Saturn-like extensions are subtle visually."
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
            "This large, bright planetary nebula is well placed during this observing window. The bright Moon may reduce contrast, but M27 is still worth trying."
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
            "Look in Vulpecula near Sagitta and Cygnus. Compare direct and averted vision to distinguish the dumbbell shape from nearby stars."
        )
        XCTAssertNil(sections["How to find it"])
        XCTAssertTrue(sections["Why recommended"]?.contains("large, bright planetary nebula") == true)
        XCTAssertFalse(sections["Why recommended"]?.localizedCaseInsensitiveContains("dumbbell") == true)
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
            "Look in Perseus between Cassiopeia and the bright star Mirfak. Scan slowly between both clusters and compare their bright star patterns."
        )
        XCTAssertFalse(clusterSections["Finding tips"]?.contains("52°") == true)
        XCTAssertFalse(clusterSections["Finding tips"]?.contains("Best from") == true)
        XCTAssertEqual(
            clusterSections["Why recommended"],
            "The Double Cluster is a rewarding target for this observing window. Clouds or haze may make it harder to see."
        )
        XCTAssertEqual(clusterSections["Best equipment"], "Use binoculars or a low-power telescope to keep both clusters in view.")
        XCTAssertEqual(clusterSections["Observing notes"], "Two rich clusters sit close together in a Milky Way star field, with many bright blue-white stars and dense central concentrations.")

        let globular = Self.detailContent(name: "Generic Globular", type: .globularCluster)
        XCTAssertEqual(
            globular.sections.first(where: { $0.title == "Finding tips" })?.text,
            "Use averted vision on the outer halo, then increase magnification gradually to compare the compact core with the surrounding granularity."
        )
    }

    func testBestEquipmentSuppressionUsesFitLevelAndSemanticSectionKind() {
        let content = Self.detailContent(name: "Generic Galaxy", type: .galaxy)

        XCTAssertEqual(
            content.sections.map(\.kind),
            [.whyRecommended, .findingTips, .bestEquipment, .observingNotes]
        )
        XCTAssertEqual(
            content.sections(hidingBestEquipment: false).map(\.kind),
            [.whyRecommended, .findingTips, .bestEquipment, .observingNotes]
        )
        XCTAssertEqual(
            content.sections(hidingBestEquipment: true).map(\.kind),
            [.whyRecommended, .findingTips, .observingNotes]
        )
        XCTAssertEqual(
            content.sections(hidingBestEquipment: true).map(\.title),
            ["Why recommended", "Finding tips", "Observing notes"]
        )

        XCTAssertFalse(TargetDetailView.shouldHideBestEquipment(for: nil))
        XCTAssertTrue(TargetDetailView.shouldHideBestEquipment(for: .excellent))
        XCTAssertTrue(TargetDetailView.shouldHideBestEquipment(for: .good))
        XCTAssertTrue(TargetDetailView.shouldHideBestEquipment(for: .challenging))
        XCTAssertFalse(TargetDetailView.shouldHideBestEquipment(for: .poor))
    }

    func testFindingTipsAreTechniqueFocusedAcrossRepresentativeCategories() {
        let cases: [(String, TargetDetailContent)] = [
            ("double star", Self.detailContent(name: "Epsilon Lyrae", type: .doubleStar)),
            ("planet", Self.detailContent(name: "Jupiter", targetType: .planet)),
            ("Moon", Self.detailContent(name: "Moon", targetType: .moon)),
            ("open cluster", Self.detailContent(name: "Generic Open Cluster", type: .openCluster)),
            ("globular cluster", Self.detailContent(name: "Generic Globular", type: .globularCluster)),
            ("planetary nebula", Self.detailContent(name: "Generic Planetary Nebula", type: .planetaryNebula)),
            ("diffuse nebula", Self.detailContent(name: "Generic Diffuse Nebula", type: .diffuseNebula)),
            ("galaxy", Self.detailContent(name: "Generic Galaxy", type: .galaxy))
        ]
        let expectedTips = [
            "Wait for steady seeing, then increase magnification gradually until the pair separates cleanly.",
            "Wait for brief moments of steady seeing, when fine detail may become easier to distinguish.",
            "Trace the terminator, where long shadows make craters and ridges easier to recognize.",
            "Scan slowly around the target and look for the distinctive pattern formed by its brighter members.",
            "Use averted vision on the outer halo, then increase magnification gradually to compare the compact core with the surrounding granularity.",
            "Compare direct and averted vision and look for a compact disk that remains slightly extended beside nearby stars.",
            "Shield your eyes from stray light and sweep slowly across the field to make faint boundaries easier to notice.",
            "Find the brighter central glow first, then use averted vision to trace the galaxy’s orientation and fainter extent."
        ]

        let tips = cases.map { label, content -> String in
            let tip = content.sections.first(where: { $0.kind == .findingTips })?.text
            XCTAssertNotNil(tip, label)
            return tip ?? ""
        }

        XCTAssertEqual(tips, expectedTips)
        for (label, tip) in zip(cases.map(\.0), tips) {
            let lowercasedTip = tip.lowercased()
            XCTAssertFalse(lowercasedTip.contains("use a telescope"), label)
            XCTAssertFalse(lowercasedTip.contains("best viewed with"), label)
            XCTAssertFalse(lowercasedTip.contains("larger aperture"), label)
            XCTAssertFalse(lowercasedTip.contains("medium or high magnification"), label)
        }
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
            XCTAssertTrue(guide.observingNotes?.contains("faint, diffuse glow") == true, id)
            XCTAssertTrue(guide.observingNotes?.contains("subtle spiral structure") == true, id)
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
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("steady seeing"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("pair separates cleanly"))
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

    func testObservingNotesPreserveAppearanceWhileFindingTipsKeepTechnique() {
        let moon = Self.detailContent(name: "Moon", targetType: .moon)
        let jupiter = Self.detailContent(id: "jupiter", name: "Jupiter", targetType: .planet)
        let saturn = Self.detailContent(id: "saturn", name: "Saturn", targetType: .planet)
        let albireo = Self.detailContent(id: "albireo", name: "Albireo", type: .doubleStar)
        let genericDouble = Self.detailContent(name: "Generic Double", type: .doubleStar)
        let genericGlobular = Self.detailContent(name: "Generic Globular", type: .globularCluster)
        let genericPlanetaryNebula = Self.detailContent(name: "Generic Planetary Nebula", type: .planetaryNebula)
        let genericNebula = Self.detailContent(name: "Generic Nebula", type: .diffuseNebula)

        XCTAssertEqual(Self.section(.findingTips, in: moon), "Trace the terminator, where long shadows make craters and ridges easier to recognize.")
        XCTAssertTrue(Self.section(.bestEquipment, in: moon).contains("Moon filter"))
        XCTAssertTrue(Self.section(.observingNotes, in: moon).contains("shadows changing"))
        XCTAssertEqual(Self.section(.observingNotes, in: jupiter), "Look for dark cloud bands across the disk; finer features may appear only briefly.")
        XCTAssertEqual(Self.section(.observingNotes, in: saturn), "The rings are the most distinctive feature, with the planet’s globe appearing smaller and more subdued.")
        XCTAssertEqual(Self.section(.observingNotes, in: albireo), "Look for the strong color contrast between the brighter golden star and its fainter blue companion.")
        XCTAssertTrue(Self.section(.findingTips, in: genericDouble).contains("steady seeing"))
        XCTAssertTrue(Self.section(.observingNotes, in: genericDouble).contains("brightness and color"))
        XCTAssertFalse(Self.section(.observingNotes, in: genericDouble).localizedCaseInsensitiveContains("magnification"))
        let globularTips = Self.section(.findingTips, in: genericGlobular)
        let globularNotes = Self.section(.observingNotes, in: genericGlobular)
        XCTAssertTrue(globularTips.contains("averted vision"))
        XCTAssertTrue(globularTips.contains("increase magnification gradually"))
        XCTAssertFalse(globularTips.localizedCaseInsensitiveContains("resolved edge stars"))
        XCTAssertTrue(globularNotes.contains("bright central glow"))
        XCTAssertTrue(globularNotes.contains("granular outer halo"))
        XCTAssertTrue(globularNotes.contains("edge stars may resolve"))
        XCTAssertTrue(Self.section(.observingNotes, in: genericPlanetaryNebula).contains("small gray-green disk or ring"))
        XCTAssertFalse(Self.section(.observingNotes, in: genericPlanetaryNebula).localizedCaseInsensitiveContains("nebula filter"))
        XCTAssertTrue(Self.section(.observingNotes, in: genericNebula).contains("photographs usually show more color"))
    }

    func testCuratedGuidesKeepEquipmentAndAppearanceGuidanceInSeparateSections() {
        let doubleCluster = Self.detailContent(id: "double-cluster", name: "NGC 869/884 Double Cluster", type: .openCluster)
        let m27 = Self.detailContent(id: "m27", name: "M27 Dumbbell Nebula", type: .planetaryNebula)
        let m33 = Self.detailContent(id: "m33", name: "M33 Triangulum Galaxy", type: .galaxy)
        let m31 = Self.detailContent(id: "m31", name: "M31 Andromeda Galaxy", type: .galaxy)

        XCTAssertTrue(Self.section(.bestEquipment, in: doubleCluster).contains("binoculars"))
        XCTAssertFalse(Self.section(.observingNotes, in: doubleCluster).localizedCaseInsensitiveContains("binocular"))
        XCTAssertTrue(Self.section(.bestEquipment, in: m27).contains("nebula filter"))
        XCTAssertTrue(Self.section(.observingNotes, in: m27).contains("dumbbell or apple-core"))
        XCTAssertTrue(Self.section(.findingTips, in: m27).contains("direct and averted vision"))
        XCTAssertTrue(Self.section(.findingTips, in: m33).contains("brighter central glow"))
        XCTAssertTrue(Self.section(.observingNotes, in: m33).contains("faint, diffuse glow"))
        XCTAssertTrue(Self.section(.observingNotes, in: m31).contains("bright core"))
        XCTAssertFalse(Self.section(.observingNotes, in: m31).localizedCaseInsensitiveContains("easy to locate"))
    }

    func testWhyRecommendedDoesNotRepeatSummaryEquipmentAdvice() {
        let content = Self.detailContent(
            name: "Equipment Summary",
            type: .globularCluster,
            reasons: [.highAltitude],
            summary: "Good telescope target; higher magnification may resolve outer stars."
        )

        XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("telescope"))
        XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("magnification"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("high in the sky"))
        XCTAssertTrue(Self.section(.bestEquipment, in: content).localizedCaseInsensitiveContains("telescope"))
        XCTAssertTrue(Self.section(.observingNotes, in: content).localizedCaseInsensitiveContains("edge stars may resolve"))
    }

    func testWhyRecommendedPreservesNonEquipmentSummarySentencesAndClauses() {
        let equipmentThenConditions = Self.detailContent(
            name: "Mixed Summary",
            summary: "Good telescope target. High in the southeast tonight."
        )
        let conditionsThenEquipment = Self.detailContent(
            name: "Mixed Summary",
            summary: "High in the southeast tonight. Best viewed through a telescope."
        )
        let semicolonMix = Self.detailContent(
            name: "Mixed Summary",
            summary: "High in the southeast tonight; use a telescope for the best view."
        )
        let conjunctionMix = Self.detailContent(
            name: "Mixed Summary",
            summary: "High in the southeast tonight and rewarding through a telescope."
        )

        for content in [equipmentThenConditions, conditionsThenEquipment, semicolonMix, conjunctionMix] {
            XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("high in the southeast"))
            XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("telescope"))
        }
    }

    func testWhyRecommendedPreservesOrdinarySummaryAndAvoidsDuplicateStructuredPlacement() {
        let ordinarySummary = Self.detailContent(
            name: "Placement Summary",
            summary: "High in the sky during astronomical darkness."
        )
        let duplicatePlacement = Self.detailContent(
            name: "Placement Summary",
            reasons: [.highAltitude],
            summary: "High in the southeast tonight."
        )
        let visibleTonight = Self.detailContent(name: "Visible Tonight", summary: "Visible tonight.")

        XCTAssertEqual(ordinarySummary.whyRecommended, "High in the sky during astronomical darkness.")
        XCTAssertEqual(
            duplicatePlacement.whyRecommended.lowercased().components(separatedBy: "high in").count - 1,
            1
        )
        XCTAssertEqual(visibleTonight.whyRecommended, "This target should be worth observing during its best window.")
    }

    func testWhyRecommendedPreservesOrdinarySummaryPunctuationAndConjunctions() {
        let cases = [
            (
                "Bright and well placed during astronomical darkness.",
                "Bright and well placed during astronomical darkness."
            ),
            (
                "Clouds, haze, and moonlight may interfere.",
                "Clouds, haze, and moonlight may interfere."
            ),
            (
                "High in the southeast tonight, with a long observing window.",
                "High in the southeast for this night, with a long observing window."
            ),
            (
                "The telescope icon identifies this target category.",
                "The telescope icon identifies this target category."
            )
        ]

        for (summary, expectedWhyRecommended) in cases {
            let content = Self.detailContent(name: "Ordinary Summary", summary: summary)
            XCTAssertEqual(content.whyRecommended, expectedWhyRecommended, summary)
        }
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

    private static func section(
        _ kind: TargetDetailSectionKind,
        in content: TargetDetailContent
    ) -> String {
        content.sections.first(where: { $0.kind == kind })?.text ?? ""
    }
}
