import SharedCode
import XCTest
import Foundation
@testable import AstroViewingConditions

@MainActor
final class DashboardViewModelTests: XCTestCase {

    func testImageViewerAppearanceDoesNotOverrideTargetDetailsTheme() {
        XCTAssertTrue(TargetImagePresentationAppearance.viewerUsesBlackBackground)
        XCTAssertFalse(TargetImagePresentationAppearance.viewerOverridesContentColorScheme)
        XCTAssertTrue(TargetImagePresentationAppearance.targetDetailsUsesSystemGroupedBackground)
        XCTAssertTrue(TargetImagePresentationAppearance.viewerAttributionUsesGradient)
        XCTAssertFalse(TargetImagePresentationAppearance.viewerAttributionUsesMaterialPanel)
    }

    func testZoomableImageViewerSupportsFitZoomPanAndDoubleTap() {
        XCTAssertEqual(ZoomableImageInteractionPolicy.minimumZoomScale, 1)
        XCTAssertGreaterThan(ZoomableImageInteractionPolicy.maximumZoomScale, 1)
        XCTAssertGreaterThan(ZoomableImageInteractionPolicy.doubleTapZoomScale, 1)
        XCTAssertTrue(ZoomableImageInteractionPolicy.supportsPanning)
    }

    func testTargetImageRenderingKeepsHeroesFittedAndThumbnailsFilled() {
        XCTAssertEqual(TargetImageRenderingPolicy.heroContentMode, .fit)
        XCTAssertEqual(TargetImageRenderingPolicy.thumbnailContentMode, .fill)
        XCTAssertEqual(TargetImageRenderingPolicy.heroMaxHeight, 260)
    }

    func testImageViewerAvailabilityMatchesVerifiedHeroAvailability() {
        let repository = TargetImageRepository()
        let moon = repository.heroImage(for: "moon")

        XCTAssertNotNil(moon)
        XCTAssertEqual(moon?.record.attributionText, "Image: NASA Johnson Space Center · NASA Public Domain")
        XCTAssertNotNil(moon?.record.licenseURL)
        XCTAssertNil(repository.heroImage(for: "no-image"))
    }

    func testImageViewerPresentationCanOpenAndDismiss() throws {
        let image = try XCTUnwrap(TargetImageRepository().heroImage(for: "moon"))
        var presentation = TargetImageViewerPresentationState()

        XCTAssertNil(presentation.image)
        presentation.present(image)
        XCTAssertEqual(presentation.image?.id, "moon")
        presentation.dismiss()
        XCTAssertNil(presentation.image)
    }

    func testTargetSheetWidthOnlyExpandsForRegularSizeClass() {
        XCTAssertEqual(TargetSheetLayout.preferredWidth(for: .regular), 720)
        XCTAssertNil(TargetSheetLayout.preferredWidth(for: .compact))
        XCTAssertNil(TargetSheetLayout.preferredWidth(for: nil))
    }

    func testCuratedTargetImagesHaveCompleteAuditableMetadata() {
        XCTAssertEqual(TargetImageManifest.imagesByTargetID.count, 21)
        for (targetID, image) in TargetImageManifest.imagesByTargetID {
            XCTAssertEqual(image.targetID, targetID)
            XCTAssertTrue(image.isVerified, targetID)
            XCTAssertTrue(image.hasCompleteMetadata, targetID)
            XCTAssertFalse(image.assetName.isEmpty, targetID)
            XCTAssertFalse(image.sourceName.isEmpty, targetID)
            XCTAssertFalse(image.sourceURL.absoluteString.isEmpty, targetID)
            XCTAssertFalse(image.credit.isEmpty, targetID)
            XCTAssertFalse(image.licenseName.isEmpty, targetID)
            XCTAssertFalse(image.licenseURL.absoluteString.isEmpty, targetID)
        }
    }

    func testNewVerifiedTargetImagesHaveCompleteMetadataAndLocalAssets() throws {
        for id in ["m45", "m42", "m5", "m3", "m33"] {
            let image = try XCTUnwrap(TargetImageManifest.image(for: id), id)
            XCTAssertTrue(image.isVerified, id)
            XCTAssertTrue(image.hasCompleteMetadata, id)
            XCTAssertNotNil(UIImage(named: image.assetName), id)
        }

        XCTAssertEqual(TargetImageManifest.image(for: "m33")?.thumbnailAssetName, "target-m33-thumbnail")
        XCTAssertNil(TargetImageManifest.image(for: "double-cluster"))
        XCTAssertNil(TargetImageManifest.image(for: "m16"))
        XCTAssertNil(TargetImageManifest.image(for: "m20"))
        XCTAssertNil(TargetImageManifest.image(for: "m101"))
    }

    func testM27AndSaturnUseSelectedCompleteSourceMetadata() throws {
        let m27 = try XCTUnwrap(TargetImageManifest.image(for: "m27"))
        XCTAssertTrue(m27.hasCompleteMetadata)
        XCTAssertEqual(m27.displayName, "M27 Dumbbell Nebula")
        XCTAssertEqual(m27.objectName, "Dumbbell Nebula, M27, NGC 6853")
        XCTAssertEqual(m27.sourceName, "NASA Science")
        XCTAssertEqual(m27.sourcePageURL.absoluteString, "https://science.nasa.gov/asset/hubble/vlt-image-of-dumbbell-nebula/")
        XCTAssertEqual(m27.creditText, "European Southern Observatory")
        XCTAssertEqual(m27.licenseName, "CC BY 4.0")
        XCTAssertFalse(m27.licenseURL.absoluteString.isEmpty)
        XCTAssertEqual(m27.attributionText, "Image: European Southern Observatory · CC BY 4.0")

        let saturn = try XCTUnwrap(TargetImageManifest.image(for: "saturn"))
        XCTAssertTrue(saturn.hasCompleteMetadata)
        XCTAssertEqual(saturn.displayName, "Saturn")
        XCTAssertEqual(saturn.sourceName, "NASA Photojournal")
        XCTAssertEqual(saturn.sourcePageURL.absoluteString, "https://science.nasa.gov/photojournal/saturn-in-color/")
        XCTAssertEqual(saturn.creditText, "NASA/JPL/Space Science Institute")
        XCTAssertEqual(saturn.licenseName, "NASA Public Domain")
        XCTAssertFalse(saturn.licenseURL.absoluteString.isEmpty)
        XCTAssertEqual(saturn.attributionText, "Image: NASA/JPL/Space Science Institute · NASA Public Domain")
    }

    func testM11UsesVerifiedESOWideFieldImageMetadata() throws {
        let m11 = try XCTUnwrap(TargetImageManifest.image(for: "m11"))

        XCTAssertTrue(m11.isVerified)
        XCTAssertTrue(m11.hasCompleteMetadata)
        XCTAssertEqual(m11.displayName, "M11 Wild Duck Cluster")
        XCTAssertEqual(m11.objectName, "Wild Duck Cluster, M11, NGC 6705")
        XCTAssertEqual(m11.sourceName, "ESO")
        XCTAssertEqual(m11.sourcePageURL.absoluteString, "https://www.eso.org/public/images/eso1430a/")
        XCTAssertEqual(m11.creditText, "ESO")
        XCTAssertEqual(m11.licenseName, "CC BY 4.0")
        XCTAssertEqual(m11.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
        XCTAssertEqual(m11.thumbnailAssetName, "target-m11-thumbnail")
        XCTAssertEqual(m11.attributionText, "Image: ESO · CC BY 4.0")
    }

    func testM52UsesVerifiedNOIRLabImageMetadataAndAttribution() throws {
        let m52 = try XCTUnwrap(TargetImageManifest.image(for: "m52"))

        XCTAssertTrue(m52.isVerified)
        XCTAssertTrue(m52.hasCompleteMetadata)
        XCTAssertEqual(m52.displayName, "M52 Open Cluster")
        XCTAssertEqual(m52.objectName, "M52, NGC 7654")
        XCTAssertEqual(m52.sourceName, "NOIRLab / Wikimedia Commons")
        XCTAssertEqual(m52.sourcePageURL.absoluteString, "https://noirlab.edu/public/images/noao-m52/")
        XCTAssertEqual(m52.commonsPageURL?.absoluteString, "https://commons.wikimedia.org/wiki/File:M52,_NGC_7654_(noao-m52).jpg")
        XCTAssertEqual(m52.creditText, "NOIRLab")
        XCTAssertEqual(m52.licenseName, "CC BY 4.0")
        XCTAssertEqual(m52.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
        XCTAssertEqual(m52.thumbnailAssetName, "target-m52-thumbnail")
        XCTAssertEqual(m52.attributionText, "Image: NOIRLab · CC BY 4.0")
    }

    func testEveryCuratedTargetImageAssetExistsInAppBundle() {
        for (targetID, image) in TargetImageManifest.imagesByTargetID {
            XCTAssertNotNil(UIImage(named: image.assetName), "Missing hero asset for \(targetID)")
            if let thumbnailAssetName = image.thumbnailAssetName {
                XCTAssertNotNil(UIImage(named: thumbnailAssetName), "Missing thumbnail for \(targetID)")
            }
            if let heroAssetName = image.heroAssetName {
                XCTAssertNotNil(UIImage(named: heroAssetName), "Missing detail hero for \(targetID)")
            }
        }
    }

    func testTargetWithoutCuratedImageHasNoThumbnailOrHero() {
        let repository = TargetImageRepository()

        XCTAssertNil(repository.thumbnailImage(for: "no-image"))
        XCTAssertNil(repository.heroImage(for: "no-image"))
    }

    func testUnverifiedImageRecordIsNeverResolved() throws {
        let verified = try XCTUnwrap(TargetImageManifest.image(for: "moon"))
        let unverified = TargetImageCredit(
            targetID: verified.targetID,
            assetName: verified.assetName,
            thumbnailAssetName: verified.thumbnailAssetName,
            sourceName: verified.sourceName,
            sourceURL: verified.sourceURL,
            credit: verified.credit,
            licenseName: verified.licenseName,
            licenseURL: verified.licenseURL,
            requiresAttribution: verified.requiresAttribution,
            isVerified: false,
            verifiedAt: verified.verifiedAt
        )
        let repository = TargetImageRepository(recordsByTargetID: ["moon": unverified])

        XCTAssertNil(repository.record(for: "moon"))
        XCTAssertNil(repository.thumbnailImage(for: "moon"))
        XCTAssertNil(repository.heroImage(for: "moon"))
    }

    func testVerifiedImageWithIncompleteCreditIsNeverResolved() throws {
        let verified = try XCTUnwrap(TargetImageManifest.image(for: "moon"))
        let incomplete = TargetImageCredit(
            targetID: verified.targetID,
            assetName: verified.assetName,
            thumbnailAssetName: verified.thumbnailAssetName,
            sourceName: verified.sourceName,
            sourceURL: verified.sourceURL,
            credit: " ",
            licenseName: verified.licenseName,
            licenseURL: verified.licenseURL,
            requiresAttribution: verified.requiresAttribution,
            isVerified: true,
            verifiedAt: verified.verifiedAt
        )
        let repository = TargetImageRepository(recordsByTargetID: ["moon": incomplete])

        XCTAssertFalse(incomplete.hasCompleteMetadata)
        XCTAssertNil(repository.record(for: "moon"))
        XCTAssertNil(repository.thumbnailImage(for: "moon"))
        XCTAssertNil(repository.heroImage(for: "moon"))
    }

    func testRecognitionCropsUseSeparateAssetsAndPreserveFullZoomImages() throws {
        let repository = TargetImageRepository()

        for id in ["m13", "albireo", "epsilon-lyrae"] {
            let record = try XCTUnwrap(repository.record(for: id))
            let resolved = try XCTUnwrap(repository.heroImage(for: id))
            XCTAssertNotNil(repository.thumbnailImage(for: id), id)
            XCTAssertNotNil(record.heroAssetName, id)
            XCTAssertNotEqual(record.thumbnailAssetName, record.assetName, id)
            XCTAssertNotEqual(record.heroAssetName, record.assetName, id)
            XCTAssertNotEqual(resolved.uiImage.size, .zero, id)
            XCTAssertNotEqual(resolved.displayUIImage.size, .zero, id)
        }
    }

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

    func testOnlyChallengeTargetsRequestIntentBadges() {
        XCTAssertTrue(TargetIntentPresentation.showsBadge(for: .challenge))
        XCTAssertEqual(TargetIntentPresentation.badgeText(for: .challenge), "Challenge")
        XCTAssertNotNil(TargetIntentPresentation.detailGuidance(for: .challenge))
        XCTAssertFalse(TargetIntentPresentation.showsBadge(for: .easy))
        XCTAssertFalse(TargetIntentPresentation.showsBadge(for: .standard))
        XCTAssertNil(TargetIntentPresentation.badgeText(for: .easy))
        XCTAssertNil(TargetIntentPresentation.badgeText(for: .standard))
        XCTAssertNil(TargetIntentPresentation.detailGuidance(for: .easy))
        XCTAssertNil(TargetIntentPresentation.detailGuidance(for: .standard))
    }

    func testTargetDetailsExposeImageAttributionWhenPresent() {
        let content = Self.detailContent(name: "Moon", targetType: .moon, image: TargetImageManifest.image(for: "moon"))
        XCTAssertEqual(content.imageAttribution, "Image: NASA Johnson Space Center · NASA Public Domain")
    }

    func testTargetScoreColorsUseSharedCategories() {
        XCTAssertEqual(TargetScoreColorProvider.category(for: 84), .excellent)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 76), .good)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 55), .fair)
        XCTAssertEqual(TargetScoreColorProvider.category(for: 35), .poor)
    }

    func testBestTargetsPoorConditionsNoteThreshold() {
        XCTAssertTrue(TonightsBestTargetsCard.showsPoorConditionsNote(for: 29))
        XCTAssertFalse(TonightsBestTargetsCard.showsPoorConditionsNote(for: 30))
        XCTAssertFalse(TonightsBestTargetsCard.showsPoorConditionsNote(for: nil))
    }

    func testBestTargetsDashboardCapsAtFiveAndShowsViewAllForAdditionalTargets() {
        let recommendations = [90, 85, 80, 75, 70, 65].enumerated().map { index, score in
            Self.makeRecommendation(id: "target-\(index)", name: "Target \(index)", score: score)
        }
        let presentation = BestTargetsListPresentation(recommendations: recommendations)

        XCTAssertEqual(presentation.dashboardRecommendations.count, 5)
        XCTAssertTrue(presentation.hasAdditionalTargets)
        XCTAssertTrue(TonightsBestTargetsCard.showsViewAll(hasAdditionalTargets: true))
        XCTAssertFalse(TonightsBestTargetsCard.showsViewAll(hasAdditionalTargets: false))
    }

    func testBestTargetsFullListGroupsScoreBandsAndHidesScoresBelow45() {
        let recommendations = [90, 80, 79, 65, 64, 45, 44].enumerated().map { index, score in
            Self.makeRecommendation(id: "target-\(index)", name: "Target \(index)", score: score)
        }
        let sections = BestTargetsListPresentation(recommendations: recommendations).sections(for: .all)

        XCTAssertEqual(sections.map(\.band), [.excellent, .good, .fair])
        XCTAssertEqual(sections.map { $0.recommendations.map(\.score) }, [
            [90, 80],
            [79, 65],
            [64, 45]
        ])
        XCTAssertFalse(sections.flatMap(\.recommendations).contains { $0.score < 45 })
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

    func testCurrentTargetRecommendationsUseInjectedServiceOutput() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDate = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 29, hour: 12
        ))!
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let sunEvents = [
            Self.makeSunEvents(for: startOfDay, calendar: calendar),
            Self.makeSunEvents(for: tomorrow, calendar: calendar)
        ]
        let forecasts = (20...28).map { hour -> HourlyForecast in
            let date = calendar.date(
                bySettingHour: hour % 24,
                minute: 0,
                second: 0,
                of: hour >= 24 ? tomorrow : startOfDay
            )!
            return Self.makeForecast(at: date)
        }
        let expectedRecommendations = [
            Self.makeRecommendation(id: "saturn", name: "Saturn", score: 65),
            Self.makeRecommendation(id: "venus", name: "Venus", score: 62),
            Self.makeRecommendation(id: "jupiter", name: "Jupiter", score: 53),
            Self.makeRecommendation(id: "mars", name: "Mars", score: 45)
        ]
        let targetRecommendationService = FixedDashboardTargetRecommendationService(
            recommendations: expectedRecommendations
        )
        let viewModel = DashboardViewModel(
            targetRecommendationService: targetRecommendationService,
            now: { referenceDate }
        )
        viewModel.viewingConditions = ViewingConditions(
            fetchedAt: referenceDate,
            location: CachedLocation(name: "Cupertino", latitude: 37.323, longitude: -122.0322, elevation: 72),
            hourlyForecasts: forecasts,
            dailySunEvents: sunEvents,
            dailyMoonInfo: [
                MoonInfo(phase: 0.98, phaseName: "Full Moon", altitude: 20, illumination: 98, emoji: ""),
                MoonInfo(phase: 0.99, phaseName: "Full Moon", altitude: 18, illumination: 99, emoji: "")
            ],
            issPasses: [],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )

        let recommendations = viewModel.currentTargetRecommendations

        XCTAssertEqual(recommendations.map(\.target.name), ["Saturn", "Venus", "Jupiter", "Mars"])
        XCTAssertEqual(recommendations.map(\.score), [65, 62, 53, 45])
        XCTAssertEqual(targetRecommendationService.requestedLimits, [100])
    }

    func testCurrentISSPassesFollowSelectedLocationDay() {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.date(from: DateComponents(
            year: 2026, month: 6, day: 28, hour: 12
        ))!
        let startOfFirstDay = calendar.startOfDay(for: firstDay)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfFirstDay)!
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: startOfFirstDay)!
        let fourthDay = calendar.date(byAdding: .day, value: 3, to: startOfFirstDay)!
        let sunEvents = [startOfFirstDay, tomorrow, dayAfter, fourthDay].map {
            Self.makeSunEvents(for: $0, calendar: calendar)
        }
        let tonightBeforeMidnight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: startOfFirstDay
        )!
        let tonightAfterMidnight = calendar.date(
            bySettingHour: 2, minute: 28, second: 0, of: tomorrow
        )!
        let tomorrowNight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: tomorrow
        )!
        let dayAfterNight = calendar.date(
            bySettingHour: 22, minute: 0, second: 0, of: dayAfter
        )!
        let conditions = ViewingConditions(
            fetchedAt: firstDay,
            location: CachedLocation(name: "Test", latitude: 34, longitude: -118, elevation: 0),
            hourlyForecasts: [Self.makeForecast(at: firstDay)],
            dailySunEvents: sunEvents,
            dailyMoonInfo: [],
            issPasses: [
                ISSPass(riseTime: tonightBeforeMidnight, duration: 300, maxElevation: 30),
                ISSPass(riseTime: tonightAfterMidnight, duration: 300, maxElevation: 35),
                ISSPass(riseTime: tomorrowNight, duration: 300, maxElevation: 40),
                ISSPass(riseTime: dayAfterNight, duration: 300, maxElevation: 50)
            ],
            fogScore: FogScore(score: 0, factors: []),
            timeZoneIdentifier: timeZone.identifier
        )
        let viewModel = DashboardViewModel(now: { firstDay })
        viewModel.viewingConditions = conditions

        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [30, 35])
        viewModel.selectedDay = .tomorrow
        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [40])
        viewModel.selectedDay = .dayAfter
        XCTAssertEqual(viewModel.currentISSPasses.map(\.maxElevation), [50])
    }

    private static func makeForecast(at date: Date) -> HourlyForecast {
        HourlyForecast(
            time: date,
            cloudCover: 0,
            humidity: 0,
            windSpeed: 0,
            windDirection: 0,
            temperature: 0
        )
    }

    private static func makeSunEvents(for date: Date, calendar: Calendar) -> SunEvents {
        let sunrise = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date)!
        let sunset = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: date)!
        return SunEvents(
            sunrise: sunrise,
            sunset: sunset,
            civilTwilightBegin: sunrise.addingTimeInterval(-1_800),
            civilTwilightEnd: sunset.addingTimeInterval(1_800),
            nauticalTwilightBegin: sunrise.addingTimeInterval(-3_600),
            nauticalTwilightEnd: sunset.addingTimeInterval(3_600),
            astronomicalTwilightBegin: sunrise.addingTimeInterval(-5_400),
            astronomicalTwilightEnd: sunset.addingTimeInterval(5_400)
        )
    }

    private static func makeRecommendation(
        id: String,
        name: String,
        score: Int
    ) -> TargetRecommendation {
        let start = Date(timeIntervalSince1970: 1_782_790_000)
        let end = start.addingTimeInterval(3_600)
        return TargetRecommendation(
            target: ObservableTarget(
                id: id,
                name: name,
                type: .planet,
                preferredEquipment: .nakedEye,
                difficulty: 0.2
            ),
            score: score,
            visibilityWindow: TargetVisibilityWindow(
                start: start,
                end: end,
                bestTime: start.addingTimeInterval(1_800),
                maxAltitude: 35,
                direction: "SE"
            ),
            reasons: [.convenientPlanetWindow],
            summary: "\(name) summary"
        )
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
    
    func testScenario1_at11PM_tabLabelsMatchData() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var monday11PM = DateComponents()
        monday11PM.year = 2026
        monday11PM.month = 2
        monday11PM.day = 22
        monday11PM.hour = 23
        monday11PM.minute = 0
        let fetchDate = calendar.date(from: monday11PM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: fetchDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: fetchDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: fetchDate,
                    sunset: fetchDate.addingTimeInterval(43200),
                    civilTwilightBegin: fetchDate.addingTimeInterval(-1800),
                    civilTwilightEnd: fetchDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: fetchDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: fetchDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: fetchDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: fetchDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel(now: { fetchDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: fetchDate))!
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not fetch date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts")
        
        // Forecasts are based on fetch date, not current date
        let fetchDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: fetchDate))!
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, fetchDay2Date,
                "Tab 2 forecasts should be for the day after tomorrow based on fetch date")
        }
    }
    
    func testAt1AMStaleCacheTabsRemainAnchoredToCurrentDate() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var monday11PM = DateComponents()
        monday11PM.year = 2026
        monday11PM.month = 2
        monday11PM.day = 22
        monday11PM.hour = 23
        monday11PM.minute = 0
        let fetchDate = calendar.date(from: monday11PM)!
        
        var tuesday1AM = DateComponents()
        tuesday1AM.year = 2026
        tuesday1AM.month = 2
        tuesday1AM.day = 23
        tuesday1AM.hour = 1
        tuesday1AM.minute = 0
        let currentDate = calendar.date(from: tuesday1AM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: fetchDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: fetchDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: fetchDate,
                    sunset: fetchDate.addingTimeInterval(43200),
                    civilTwilightBegin: fetchDate.addingTimeInterval(-1800),
                    civilTwilightEnd: fetchDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: fetchDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: fetchDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: fetchDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: fetchDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel(now: { currentDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = fetchDate
        
        // Tab labels use current date, not fetch date
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: currentDate))!
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not fetch date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts for two days after the current date")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: currentDate))!,
                "Tab 2 forecasts should be based on the current date, not a stale cache date")
        }
        
        viewModel.selectedDay = .today
        let todayForecasts = viewModel.currentHourlyForecasts
        XCTAssertFalse(todayForecasts.isEmpty, "Tab 0 (Today) should use the actual current day")
        
        if let firstTodayForecast = todayForecasts.first {
            let forecastDate = calendar.startOfDay(for: firstTodayForecast.time)
            XCTAssertEqual(forecastDate, calendar.startOfDay(for: currentDate),
                "Tab 0 forecasts should not remain pinned to a stale cache's first day")
        }
    }
    
    func testScenario1_afterRefresh_labelsAndDataShouldMatchNewFetchDate() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        
        var tuesday1AM = DateComponents()
        tuesday1AM.year = 2026
        tuesday1AM.month = 2
        tuesday1AM.day = 23
        tuesday1AM.hour = 1
        tuesday1AM.minute = 0
        let refreshDate = calendar.date(from: tuesday1AM)!
        
        let location = CachedLocation(
            name: "Test",
            latitude: 45.0,
            longitude: -122.0,
            elevation: 100
        )
        
        var forecasts: [HourlyForecast] = []
        for hourOffset in 0..<72 {
            let time = calendar.date(byAdding: .hour, value: hourOffset, to: refreshDate)!
            forecasts.append(HourlyForecast(
                time: time,
                cloudCover: 50,
                humidity: 80,
                windSpeed: 10.0,
                windDirection: 180,
                temperature: 15.0,
                dewPoint: 12.0,
                visibility: 10000,
                lowCloudCover: 30
            ))
        }
        
        let conditions = ViewingConditions(
            fetchedAt: refreshDate,
            location: location,
            hourlyForecasts: forecasts,
            dailySunEvents: [
                SunEvents(
                    sunrise: refreshDate,
                    sunset: refreshDate.addingTimeInterval(43200),
                    civilTwilightBegin: refreshDate.addingTimeInterval(-1800),
                    civilTwilightEnd: refreshDate.addingTimeInterval(45000),
                    nauticalTwilightBegin: refreshDate.addingTimeInterval(-3600),
                    nauticalTwilightEnd: refreshDate.addingTimeInterval(46800),
                    astronomicalTwilightBegin: refreshDate.addingTimeInterval(-5400),
                    astronomicalTwilightEnd: refreshDate.addingTimeInterval(48600)
                )
            ],
            dailyMoonInfo: [
                MoonInfo(
                    phase: 0.5,
                    phaseName: "Full Moon",
                    altitude: 45.0,
                    illumination: 100,
                    emoji: "🌕"
                )
            ],
            issPasses: [],
            fogScore: FogScore(score: 25, factors: [])
        )
        
        let viewModel = DashboardViewModel(now: { refreshDate })
        viewModel.viewingConditions = conditions
        viewModel.lastSuccessfulFetch = refreshDate
        
        // Tab labels use current date, not refresh date
        let refreshStartOfDay0 = calendar.startOfDay(for: refreshDate)
        let currentDay2Date = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: refreshDate))!
        let currentDay2Formatted = DateFormatters.shortDateFormatter.string(from: currentDay2Date)
        
        let actualDay2Title = viewModel.titleForSelectedDay(.dayAfter)
        XCTAssertEqual(actualDay2Title, currentDay2Formatted, 
            "Tab 2 label should be based on current date, not refresh date")
        
        viewModel.selectedDay = .dayAfter
        let day2Forecasts = viewModel.currentHourlyForecasts
        
        XCTAssertFalse(day2Forecasts.isEmpty, "Tab 2 should have forecasts after refresh")
        
        if let firstForecast = day2Forecasts.first {
            let forecastDate = calendar.startOfDay(for: firstForecast.time)
            XCTAssertEqual(forecastDate, calendar.date(byAdding: .day, value: 2, to: refreshStartOfDay0)!,
                "Tab 2 forecasts should be for day after tomorrow based on refresh date")
        }
        
        viewModel.selectedDay = .today
        let todayForecasts = viewModel.currentHourlyForecasts
        XCTAssertFalse(todayForecasts.isEmpty, "Tab 0 should have forecasts after refresh")
        
        if let firstTodayForecast = todayForecasts.first {
            let forecastDate = calendar.startOfDay(for: firstTodayForecast.time)
            XCTAssertEqual(forecastDate, refreshStartOfDay0,
                "Tab 0 forecasts should be for refresh date")
        }
    }
}

private final class FixedDashboardTargetRecommendationService: TargetRecommendationProviding, @unchecked Sendable {
    let recommendations: [TargetRecommendation]
    private(set) var requestedLimits: [Int] = []

    init(recommendations: [TargetRecommendation]) {
        self.recommendations = recommendations
    }

    func recommendations(
        for context: TargetRecommendationContext,
        limit: Int
    ) -> [TargetRecommendation] {
        requestedLimits.append(limit)
        return Array(recommendations.prefix(limit))
    }
}
