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
            "Expect a tiny, bright oval. A blue-green tint is easier for some observers in 150–200 mm telescopes; the ansae are difficult in about 200 mm or more under steady seeing, and their end knots are harder still."
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
            "Moonlight may reduce contrast during this window. M27’s brighter central lobes may remain detectable despite the reduced contrast."
        )
        XCTAssertEqual(
            sections["Best equipment"],
            "Binoculars can detect it as a fuzzy patch. For visual observing, use a telescope at low to moderate magnification; a UHC filter is the best first choice, while OIII can emphasize inner structure. A Smart/EAA telescope can reveal fainter extent."
        )
        XCTAssertEqual(
            sections["Observing notes"],
            "M27 usually appears visually as a gray fuzzy patch with a dumbbell or apple-core shape. Photographs show much more color and extent than an eyepiece view."
        )
        XCTAssertEqual(
            sections["Finding tips"],
            "Find the arrow-shaped Sagitta inside the Summer Triangle; on a star chart, M27 is roughly 3° north of Gamma Sagittae in neighboring Vulpecula. Use averted vision after centering it."
        )
        XCTAssertNil(sections["How to find it"])
        XCTAssertFalse(sections["Why recommended"]?.contains("large, bright planetary nebula") == true)
        XCTAssertFalse(sections["Why recommended"]?.localizedCaseInsensitiveContains("dumbbell") == true)
        XCTAssertTrue(sections["Observing notes"]?.contains("gray fuzzy patch") == true)
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
            "In Perseus, use the line between Cassiopeia and Mirfak to locate the pair, then sweep slowly between the two cluster centers."
        )
        XCTAssertFalse(clusterSections["Finding tips"]?.contains("52°") == true)
        XCTAssertFalse(clusterSections["Finding tips"]?.contains("Best from") == true)
        XCTAssertEqual(
            clusterSections["Why recommended"],
            "Clouds or haze may interfere."
        )
        XCTAssertEqual(clusterSections["Best equipment"], "Use binoculars or a low-power telescope to keep both clusters in view.")
        XCTAssertEqual(clusterSections["Observing notes"], "Two rich clusters sit close together in a Milky Way star field, with many blue-white stars and dense central concentrations.")

        let globular = Self.detailContent(name: "Generic Globular", type: .globularCluster)
        XCTAssertEqual(
            globular.sections.first(where: { $0.title == "Finding tips" })?.text,
            "Use averted vision to secure the cluster, then increase magnification gradually only after it is centered."
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
            ("planet", Self.detailContent(name: "Generic Planet", targetType: .planet)),
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
            "Use a low-power sweep around the catalog position, then center the cluster before increasing magnification.",
            "Use averted vision to secure the cluster, then increase magnification gradually only after it is centered.",
            "Use direct and averted vision to distinguish nebulosity from field stars; adjust magnification after centering.",
            "Shield your eyes from stray light and sweep slowly across the field to make faint boundaries easier to notice.",
            "Sweep slowly around the catalog position and use averted vision after centering the target."
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
        XCTAssertTrue(m27.observingNotes?.contains("gray fuzzy patch") == true)
        XCTAssertTrue(m27.observingNotes?.contains("Photographs show much more color") == true)

        let m16 = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: "m16"))
        XCTAssertTrue(m16.observingNotes?.contains("not a routine visual expectation") == true)
        XCTAssertFalse(m16.observingNotes?.localizedCaseInsensitiveContains("visible Pillars") == true)

        let m20 = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: "m20"))
        XCTAssertTrue(m20.observingNotes?.contains("not the vivid red and blue") == true)

        for id in ["m33", "m101"] {
            let guide = try XCTUnwrap(TargetObservingGuideCatalog.guide(for: id))
            XCTAssertTrue(guide.observingNotes?.localizedCaseInsensitiveContains("faint") == true, id)
            XCTAssertTrue(guide.observingNotes?.localizedCaseInsensitiveContains("spiral") == true, id)
        }
    }

    func testTargetDetailsExposeImageAttributionWhenPresent() {
        let content = Self.detailContent(name: "Moon", targetType: .moon, image: TargetImageManifest.image(for: "moon"))
        XCTAssertEqual(content.imageAttribution, "Image: NASA Johnson Space Center · NASA Public Domain")
    }

    func testM57DetailUnderBrightMoonExplainsCompactNebulaAndContrast() {
        let content = Self.detailContent(
            id: "m57",
            name: "M57 Ring Nebula",
            type: .planetaryNebula,
            reasons: [.moonInterference],
            summary: "Small bright nebula; well placed despite bright Moon."
        )

        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("tiny, dim gray smoke ring"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("Moon"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("contrast"))
        XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("small bright nebula"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("contrast"))
    }

    func testEpsilonLyraeDetailRecommendsTelescopeAndHighMagnification() {
        let content = Self.detailContent(
            id: "epsilon-lyrae",
            name: "Epsilon Lyrae",
            type: .doubleStar,
            reasons: [.highAltitude, .astronomicalDarkness, .goodNightQuality],
            summary: "Good target even under bright Moon.",
            direction: "S",
            altitude: 84
        )

        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("double"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("telescope"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("approximately 100×"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("steady seeing"))
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("without assuming both close pairs will split"))
        XCTAssertEqual(content.directionText, "Look south.")
        XCTAssertEqual(content.altitudeDegrees ?? 0, 84, accuracy: 0.01)
        XCTAssertEqual(content.altitudeText, "About 84° high.")
        XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("bright Moon"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("84° toward south"))
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
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("bright full Moon is prominent"))
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
        XCTAssertEqual(Self.section(.observingNotes, in: jupiter), "The disk commonly shows two dark equatorial cloud bands; finer features may appear only briefly.")
        XCTAssertEqual(Self.section(.observingNotes, in: saturn), "The rings are the most distinctive feature, with the planet’s globe appearing smaller and more subdued.")
        XCTAssertEqual(Self.section(.observingNotes, in: albireo), "Once resolved, the brighter star usually appears golden and the fainter companion blue.")
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
        XCTAssertTrue(Self.section(.observingNotes, in: genericPlanetaryNebula).contains("tiny disks to broad faint glows"))
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
        XCTAssertTrue(Self.section(.bestEquipment, in: m27).contains("UHC filter"))
        XCTAssertTrue(Self.section(.observingNotes, in: m27).contains("dumbbell or apple-core"))
        XCTAssertTrue(Self.section(.findingTips, in: m27).contains("Gamma Sagittae"))
        XCTAssertTrue(Self.section(.findingTips, in: m33).contains("sharp tip of Triangulum"))
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
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("60° toward south"))
        XCTAssertTrue(Self.section(.bestEquipment, in: content).localizedCaseInsensitiveContains("telescope"))
        XCTAssertTrue(Self.section(.observingNotes, in: content).localizedCaseInsensitiveContains("outer halo"))
    }

    func testWhyRecommendedPreservesSafeCompleteLegacySummarySentences() {
        let equipmentThenConditions = Self.detailContent(
            name: "Mixed Summary",
            summary: "Good telescope target. High in the southeast tonight."
        )
        let conditionsThenEquipment = Self.detailContent(
            name: "Mixed Summary",
            summary: "High in the southeast tonight. Best viewed through a telescope."
        )
        let weatherThenEquipment = Self.detailContent(
            name: "Mixed Summary",
            summary: "Clouds should clear during astronomical darkness. Use a telescope for the best view."
        )

        XCTAssertEqual(equipmentThenConditions.whyRecommended, "High in the southeast for this night.")
        XCTAssertEqual(conditionsThenEquipment.whyRecommended, "High in the southeast for this night.")
        XCTAssertEqual(weatherThenEquipment.whyRecommended, "Clouds should clear during astronomical darkness.")
    }

    func testWhyRecommendedDiscardsInseparableMixedAndEquipmentOnlySentences() {
        let semicolonMix = Self.detailContent(
            name: "Mixed Summary",
            summary: "High in the southeast tonight; use a telescope for the best view."
        )
        let conjunctionMix = Self.detailContent(
            name: "Mixed Summary",
            summary: "High in the southeast tonight and rewarding through a telescope."
        )
        let equipmentOnly = Self.detailContent(
            name: "Equipment Summary",
            summary: "Best viewed through a telescope."
        )

        for content in [semicolonMix, conjunctionMix, equipmentOnly] {
            XCTAssertEqual(content.whyRecommended, "This target should be worth observing during its best window.")
            XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("telescope"))
        }
    }

    func testWhyRecommendedPreservesSummaryWithoutEquipmentAdviceVerbatim() {
        let content = Self.detailContent(
            name: "Ordinary Summary",
            summary: "Bright and well placed! Clouds should clear later."
        )

        XCTAssertEqual(content.whyRecommended, "Bright and well placed! Clouds should clear later.")
    }

    func testStructuredFactsPreservePlacementWhenLegacySummaryMixesEquipmentAdvice() {
        let content = Self.detailContent(
            name: "Mixed Summary",
            reasons: [.highAltitude, .astronomicalDarkness, .goodNightQuality],
            summary: "High in the southeast tonight and rewarding through a telescope.",
            direction: "SE",
            altitude: 64
        )

        XCTAssertTrue(content.whyRecommended.contains("64° toward southeast"))
        XCTAssertTrue(content.whyRecommended.contains("astronomical darkness"))
        XCTAssertTrue(content.whyRecommended.contains("weather and sky quality"))
        XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("telescope"))
    }

    func testDifficultTargetsComposeChallengeContextWithFavorableLiveFacts() {
        for (id, name) in [("m33", "M33 Triangulum Galaxy"), ("m101", "M101 Pinwheel Galaxy")] {
            let content = Self.detailContent(
                id: id,
                name: name,
                type: .galaxy,
                reasons: [.highAltitude, .astronomicalDarkness, .goodNightQuality, .difficultTarget],
                direction: "S",
                altitude: 68
            )

            XCTAssertTrue(content.whyRecommended.contains("68° toward south"), id)
            XCTAssertTrue(content.whyRecommended.contains("astronomical darkness"), id)
            XCTAssertTrue(content.whyRecommended.contains("weather and sky quality look favorable"), id)
            XCTAssertTrue(content.whyRecommended.contains("intrinsically subtle target"), id)
            XCTAssertTrue(content.whyRecommended.contains("defining detail may remain difficult"), id)
        }
    }

    func testBrightMoonGlobularWhyUsesOnlyStructuredLiveFacts() {
        let high = Self.detailContent(name: "High Globular", type: .globularCluster, reasons: [.highAltitude, .moonInterference], direction: "S", altitude: 70)
        let low = Self.detailContent(name: "Low Globular", type: .globularCluster, reasons: [.lowAltitude, .moonInterference], direction: "W", altitude: 14)
        let neither = Self.detailContent(name: "Other Globular", type: .globularCluster, reasons: [.moonInterference], direction: "E", altitude: 40)

        XCTAssertTrue(high.whyRecommended.contains("70° toward south"))
        XCTAssertTrue(low.whyRecommended.contains("14° toward west"))
        XCTAssertFalse(neither.whyRecommended.localizedCaseInsensitiveContains("high in"))
        for content in [high, low, neither] {
            XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("Moonlight"))
            for equipmentWord in ["telescope", "binocular", "magnification", "filter"] {
                XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains(equipmentWord))
            }
        }
    }

    func testCuratedBrightMoonContextRequiresStructuredMoonReason() {
        let content = Self.detailContent(
            id: "m27",
            name: "M27 Dumbbell Nebula",
            type: .planetaryNebula,
            reasons: [.highAltitude],
            summary: "Bright Moon, but use a telescope.",
            direction: "S",
            altitude: 70
        )

        XCTAssertEqual(content.whyRecommended, "During the best window, it reaches about 70° toward south.")
        XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("central lobes"))
        XCTAssertFalse(content.whyRecommended.localizedCaseInsensitiveContains("telescope"))
    }

    func testAllSixteenCompassDirectionsUseNaturalNames() {
        let expected = [
            "N": "north", "NNE": "north-northeast", "NE": "northeast", "ENE": "east-northeast",
            "E": "east", "ESE": "east-southeast", "SE": "southeast", "SSE": "south-southeast",
            "S": "south", "SSW": "south-southwest", "SW": "southwest", "WSW": "west-southwest",
            "W": "west", "WNW": "west-northwest", "NW": "northwest", "NNW": "north-northwest"
        ]
        for (abbreviation, name) in expected {
            XCTAssertEqual(Self.detailContent(name: "Direction", direction: abbreviation).directionText, "Look \(name).")
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
        XCTAssertEqual(duplicatePlacement.whyRecommended, "During the best window, it reaches about 60° toward south.")
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
        XCTAssertTrue(content.sectionsText.localizedCaseInsensitiveContains("faint"))
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
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("9° toward west"))
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
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("60° toward south"))
        XCTAssertTrue(content.whyRecommended.localizedCaseInsensitiveContains("astronomical darkness"))
    }

    func testVerifiedDoubleStarGuidanceUsesApprovedApertureAndMagnificationLanguage() {
        let albireo = Self.detailContent(id: "albireo", name: "Albireo", type: .doubleStar)
        XCTAssertTrue(Self.section(.bestEquipment, in: albireo).contains("25–50×"))
        XCTAssertTrue(Self.section(.bestEquipment, in: albireo).contains("small telescope"))

        let epsilon = Self.detailContent(id: "epsilon-lyrae", name: "Epsilon Lyrae", type: .doubleStar)
        XCTAssertTrue(Self.section(.bestEquipment, in: epsilon).contains("75 mm"))
        XCTAssertTrue(Self.section(.bestEquipment, in: epsilon).contains("100 mm"))
        XCTAssertTrue(Self.section(.bestEquipment, in: epsilon).contains("100×"))
        XCTAssertTrue(Self.section(.findingTips, in: epsilon).contains("without assuming"))
        XCTAssertFalse(Self.section(.findingTips, in: epsilon).localizedCaseInsensitiveContains("telescope"))
        XCTAssertFalse(Self.section(.findingTips, in: epsilon).localizedCaseInsensitiveContains("binocular"))
        XCTAssertFalse(Self.section(.findingTips, in: epsilon).contains("75 mm"))
        XCTAssertFalse(Self.section(.findingTips, in: epsilon).contains("100×"))
        XCTAssertTrue(Self.section(.observingNotes, in: epsilon).contains("not a guarantee"))
    }

    func testM20EquipmentAndAppearanceRemainInTheirOwnedSections() {
        let content = Self.detailContent(id: "m20", name: "M20 Trifid Nebula", type: .diffuseNebula)
        let equipment = Self.section(.bestEquipment, in: content)
        let notes = Self.section(.observingNotes, in: content)

        XCTAssertTrue(equipment.contains("16×70-class binoculars"))
        XCTAssertTrue(equipment.contains("telescope"))
        XCTAssertTrue(equipment.contains("Smart/EAA"))
        XCTAssertTrue(equipment.contains("UHC filter"))
        for appearancePhrase in ["weak glow", "gray nebulosity", "dark lanes", "red and blue"] {
            XCTAssertFalse(equipment.localizedCaseInsensitiveContains(appearancePhrase), appearancePhrase)
        }
        XCTAssertTrue(notes.contains("Smaller binoculars may show only the stars and a weak glow"))
        XCTAssertTrue(notes.contains("faint gray nebulosity divided by dark lanes"))
        XCTAssertTrue(notes.contains("not the vivid red and blue seen in photographs"))
    }

    func testVerifiedNebulaFilterGuidanceIsTargetSpecific() {
        let expected: [(String, DeepSkyObjectType, [String])] = [
            ("m16", .diffuseNebula, ["UHC filter first", "OIII", "H-beta is not recommended"]),
            ("m20", .diffuseNebula, ["UHC filter first", "unfiltered view"]),
            ("m27", .planetaryNebula, ["UHC filter is the best first choice", "OIII"]),
            ("m57", .planetaryNebula, ["starting unfiltered", "UHC or OIII"]),
            ("ngc7009", .planetaryNebula, ["Start unfiltered", "UHC or OIII"]),
            ("ngc7293", .planetaryNebula, ["OIII filter is usually the strongest", "UHC also effective"])
        ]

        for (id, type, phrases) in expected {
            let content = Self.detailContent(id: id, name: id, type: type)
            let equipment = Self.section(.bestEquipment, in: content)
            for phrase in phrases {
                XCTAssertTrue(equipment.contains(phrase), "\(id): \(phrase)")
            }
        }
    }

    func testHighRiskVisualExpectationsRemainRestrained() {
        let m45 = Self.detailContent(id: "m45", name: "M45 Pleiades", type: .openCluster)
        XCTAssertTrue(Self.section(.observingNotes, in: m45).contains("stars is the normal visual result"))
        XCTAssertTrue(Self.section(.observingNotes, in: m45).contains("glare can imitate it"))

        let m16 = Self.detailContent(id: "m16", name: "M16 Eagle Nebula", type: .diffuseNebula)
        XCTAssertTrue(Self.section(.observingNotes, in: m16).contains("cluster is much easier"))
        XCTAssertTrue(Self.section(.observingNotes, in: m16).contains("not a routine visual expectation"))

        let saturnNebula = Self.detailContent(id: "ngc7009", name: "NGC 7009", type: .planetaryNebula)
        XCTAssertTrue(Self.section(.observingNotes, in: saturnNebula).contains("tiny, bright oval"))
        XCTAssertTrue(Self.section(.observingNotes, in: saturnNebula).contains("ansae are difficult"))
    }

    func testFullMoonFindingAndAppearanceDoNotPromiseTerminatorRelief() {
        let content = Self.detailContent(
            name: "Moon",
            targetType: .moon,
            reasons: [.brightFullMoonDeepSkyImpact]
        )

        XCTAssertTrue(Self.section(.findingTips, in: content).contains("terminator is not prominent"))
        XCTAssertTrue(Self.section(.observingNotes, in: content).contains("relief looks flatter"))
    }

    func testChangeFiveAddsCuratedGuidesWithoutRequiringFullCatalogCoverage() {
        for id in ["m57", "ngc7293", "m92"] {
            let guide = TargetObservingGuideCatalog.guide(for: id)
            XCTAssertNotNil(guide, id)
            XCTAssertNotNil(guide?.findingTips, id)
            XCTAssertNotNil(guide?.bestEquipment, id)
            XCTAssertNotNil(guide?.observingNotes, id)
        }
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
