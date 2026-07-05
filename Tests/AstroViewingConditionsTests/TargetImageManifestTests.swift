import SharedCode
import UIKit
import XCTest
@testable import AstroViewingConditions

@MainActor
final class TargetImageManifestTests: XCTestCase {

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

    func testCuratedTargetImagesHaveCompleteAuditableMetadata() {
        XCTAssertEqual(TargetImageManifest.imagesByTargetID.count, 31)
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
        for id in ["m45", "m42", "m5", "m3", "m33", "m101", "double-cluster"] {
            let image = try XCTUnwrap(TargetImageManifest.image(for: id), id)
            XCTAssertTrue(image.isVerified, id)
            XCTAssertTrue(image.hasCompleteMetadata, id)
            XCTAssertNotNil(UIImage(named: image.assetName), id)
        }

        XCTAssertEqual(TargetImageManifest.image(for: "m33")?.thumbnailAssetName, "target-m33-thumbnail")
    }

    func testDoubleClusterUsesVerifiedESOWideFieldImageAndSeparateThumbnail() throws {
        let record = try XCTUnwrap(TargetImageManifest.image(for: "double-cluster"))
        XCTAssertTrue(record.isVerified)
        XCTAssertTrue(record.hasCompleteMetadata)
        XCTAssertTrue(record.requiresAttribution)
        XCTAssertEqual(record.displayName, "NGC 869/884 Double Cluster")
        XCTAssertEqual(record.objectName, "NGC 869, NGC 884, h and Chi Persei, Caldwell 14")
        XCTAssertEqual(record.sourceName, "ESO")
        XCTAssertEqual(record.sourcePageURL.absoluteString, "https://www.eso.org/public/images/b02/")
        XCTAssertEqual(record.creditText, "ESO/S. Brunier")
        XCTAssertEqual(record.licenseName, "CC BY 4.0")
        XCTAssertEqual(record.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
        XCTAssertEqual(record.assetName, "target-double-cluster")
        XCTAssertEqual(record.thumbnailAssetName, "target-double-cluster-thumbnail")
        XCTAssertNil(record.heroAssetName)
        XCTAssertEqual(record.attributionText, "Image: ESO/S. Brunier · CC BY 4.0")

        let repository = TargetImageRepository()
        let resolved = try XCTUnwrap(repository.heroImage(for: "double-cluster"))
        XCTAssertNotNil(repository.thumbnailImage(for: "double-cluster"))
        let thumbnail = try XCTUnwrap(UIImage(named: "target-double-cluster-thumbnail"))
        XCTAssertEqual(resolved.record.assetName, "target-double-cluster")
        XCTAssertEqual(resolved.uiImage.size, resolved.displayUIImage.size)
        XCTAssertEqual(thumbnail.size.width, thumbnail.size.height)
        XCTAssertNotEqual(thumbnail.size, resolved.uiImage.size)
    }

    func testRemainingCatalogTargetsUseVerifiedRecognitionImages() throws {
        let ids = ["ngc7293", "m51", "m64", "m81", "m82", "m16", "m20"]
        let repository = TargetImageRepository()

        for id in ids {
            let record = try XCTUnwrap(TargetImageManifest.image(for: id), id)
            XCTAssertTrue(record.isVerified, id)
            XCTAssertTrue(record.hasCompleteMetadata, id)
            XCTAssertTrue(record.requiresAttribution, id)
            XCTAssertEqual(record.thumbnailAssetName, "target-\(id)-thumbnail", id)
            XCTAssertNil(record.heroAssetName, id)
            XCTAssertNotNil(repository.thumbnailImage(for: id), id)

            let resolved = try XCTUnwrap(repository.heroImage(for: id), id)
            XCTAssertEqual(resolved.record.assetName, "target-\(id)", id)
            XCTAssertEqual(resolved.uiImage.size, resolved.displayUIImage.size, id)
            XCTAssertNotEqual(resolved.uiImage.size, .zero, id)
        }

        XCTAssertEqual(TargetImageManifest.image(for: "ngc7293")?.sourcePageURL.absoluteString, "https://www.eso.org/public/images/eso0907a/")
        XCTAssertEqual(TargetImageManifest.image(for: "m51")?.creditText, "NASA, ESA, S. Beckwith (STScI) and the Hubble Heritage Team (STScI/AURA)")
        XCTAssertEqual(TargetImageManifest.image(for: "m64")?.licenseName, "NASA Media Usage Guidelines")
        XCTAssertEqual(TargetImageManifest.image(for: "m81")?.sourceName, "NASA Science / Hubble")
        XCTAssertEqual(TargetImageManifest.image(for: "m82")?.objectName, "Cigar Galaxy, M82, NGC 3034")
        XCTAssertEqual(TargetImageManifest.image(for: "m16")?.sourcePageURL.absoluteString, "https://www.eso.org/public/images/eso0926a/")
        XCTAssertEqual(TargetImageManifest.image(for: "m20")?.sourcePageURL.absoluteString, "https://www.eso.org/public/images/eso0930a/")
    }

    func testNewImageNoticesIncludeEverySourceAndCredit() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let notices = try String(contentsOf: repositoryRoot.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)

        for id in ["ngc7293", "m51", "m64", "m81", "m82", "m16", "m20"] {
            let record = try XCTUnwrap(TargetImageManifest.image(for: id))
            XCTAssertTrue(notices.contains("`\(id)`"), id)
            XCTAssertTrue(notices.contains(record.creditText), id)
        }
    }

    func testM30UsesVerifiedHubbleImageWithSeparateRecognitionThumbnail() throws {
        let record = try XCTUnwrap(TargetImageManifest.image(for: "m30"))
        XCTAssertTrue(record.isVerified)
        XCTAssertTrue(record.hasCompleteMetadata)
        XCTAssertTrue(record.requiresAttribution)
        XCTAssertEqual(record.displayName, "M30 Globular Cluster")
        XCTAssertEqual(record.objectName, "M30, Messier 30, NGC 7099")
        XCTAssertEqual(record.sourceName, "NASA Science / Hubble Messier Catalog")
        XCTAssertEqual(record.sourcePageURL.absoluteString, "https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/messier-30/")
        XCTAssertEqual(record.creditText, "NASA/ESA")
        XCTAssertEqual(record.licenseName, "NASA Media Usage Guidelines")
        XCTAssertEqual(record.licenseURL.absoluteString, "https://www.nasa.gov/nasa-brand-center/images-and-media/")
        XCTAssertEqual(record.assetName, "target-m30")
        XCTAssertEqual(record.thumbnailAssetName, "target-m30-thumbnail")
        XCTAssertNil(record.heroAssetName)

        let repository = TargetImageRepository()
        XCTAssertNotNil(repository.thumbnailImage(for: "m30"))
        let resolved = try XCTUnwrap(repository.heroImage(for: "m30"))
        XCTAssertEqual(resolved.record.assetName, "target-m30")
        XCTAssertEqual(resolved.uiImage.size, resolved.displayUIImage.size)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let notices = try String(contentsOf: repositoryRoot.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        XCTAssertTrue(notices.contains("`m30`"))
        XCTAssertTrue(notices.contains("NASA/ESA"))
    }

    func testM101UsesVerifiedNOIRLabRecognitionImageAndSeparateThumbnail() throws {
        let record = try XCTUnwrap(TargetImageManifest.image(for: "m101"))
        XCTAssertTrue(record.isVerified)
        XCTAssertTrue(record.hasCompleteMetadata)
        XCTAssertTrue(record.requiresAttribution)
        XCTAssertEqual(record.displayName, "M101 Pinwheel Galaxy")
        XCTAssertEqual(record.objectName, "M101, Pinwheel Galaxy, NGC 5457")
        XCTAssertEqual(record.sourceName, "NOIRLab / Wikimedia Commons")
        XCTAssertEqual(record.sourcePageURL.absoluteString, "https://commons.wikimedia.org/wiki/File:M101;_Pinwheel_Galaxy_(noao-m101ubviha).jpg")
        XCTAssertEqual(record.originalSourceURL?.absoluteString, "https://noirlab.edu/public/images/noao-m101ubviha/")
        XCTAssertEqual(record.creditText, "T.A. Rector (University of Alaska Anchorage) and H. Schweiker (WIYN and NOIRLab/NSF/AURA)")
        XCTAssertEqual(record.licenseName, "CC BY 4.0")
        XCTAssertEqual(record.licenseURL.absoluteString, "https://creativecommons.org/licenses/by/4.0/")
        XCTAssertEqual(record.assetName, "target-m101")
        XCTAssertEqual(record.thumbnailAssetName, "target-m101-thumbnail")
        XCTAssertNil(record.heroAssetName)

        let repository = TargetImageRepository()
        let resolved = try XCTUnwrap(repository.heroImage(for: "m101"))
        XCTAssertNotNil(repository.thumbnailImage(for: "m101"))
        XCTAssertEqual(resolved.record.assetName, "target-m101")
        XCTAssertEqual(resolved.uiImage.size, resolved.displayUIImage.size)
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

}
