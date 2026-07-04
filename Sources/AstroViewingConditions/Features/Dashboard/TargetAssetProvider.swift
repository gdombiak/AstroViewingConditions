import SharedCode
import SwiftUI
import UIKit

enum TargetImageRenderingPolicy {
    enum ContentMode: Equatable {
        case fit
        case fill
    }

    static let heroContentMode: ContentMode = .fit
    static let thumbnailContentMode: ContentMode = .fill
    static let heroMaxHeight: CGFloat = 260
}

struct ResolvedTargetImage: Identifiable {
    let record: TargetImageCredit
    let uiImage: UIImage
    let displayUIImage: UIImage

    var id: String { record.targetID }
    var image: Image { Image(uiImage: displayUIImage) }
}

protocol TargetImageRepositoryProtocol {
    func record(for targetID: String) -> TargetImageCredit?
    func heroImage(for targetID: String) -> ResolvedTargetImage?
    func thumbnailImage(for targetID: String) -> Image?
}

struct TargetImageRepository: TargetImageRepositoryProtocol {
    private let recordsByTargetID: [String: TargetImageCredit]

    init(recordsByTargetID: [String: TargetImageCredit] = TargetImageManifest.imagesByTargetID) {
        self.recordsByTargetID = recordsByTargetID
    }

    func record(for targetID: String) -> TargetImageCredit? {
        guard let record = recordsByTargetID[targetID.lowercased()],
              record.targetID == targetID.lowercased(),
              record.isVerified,
              record.hasCompleteMetadata else { return nil }
        return record
    }

    func heroImage(for targetID: String) -> ResolvedTargetImage? {
        guard let record = record(for: targetID),
              let image = UIImage(named: record.assetName),
              let displayImage = UIImage(named: record.heroAssetName ?? record.assetName) else { return nil }
        return ResolvedTargetImage(record: record, uiImage: image, displayUIImage: displayImage)
    }

    func thumbnailImage(for targetID: String) -> Image? {
        guard let record = record(for: targetID),
              let assetName = record.thumbnailAssetName,
              let image = UIImage(named: assetName) else { return nil }
        return Image(uiImage: image)
    }
}

struct TargetThumbnail: View {
    let image: Image
    var size: CGFloat = 52

    var body: some View {
        image
            .resizable()
            .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
        .accessibilityHidden(true)
    }
}

struct TargetHeroImage: View {
    let image: Image
    let accessibilityName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.black.opacity(0.9)

                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: TargetImageRenderingPolicy.heroMaxHeight)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("View full-screen image of \(accessibilityName)")
        .accessibilityHint("Opens a zoomable image viewer")
        .accessibilityIdentifier("targetHeroImageButton")
    }
}

struct TargetImageAttributionView: View {
    let info: TargetImageCredit
    var viewerOverlay = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(info.attributionText)
                .font(.footnote)
                .foregroundStyle(viewerOverlay ? Color.white.opacity(0.82) : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Image credit: \(info.credit). License: \(info.licenseName)")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    sourceLink
                    licenseLink
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 8) {
                    sourceLink
                    licenseLink
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.footnote)
            .tint(viewerOverlay ? Color.white : Color.accentColor)
        }
    }

    private var sourceLink: some View {
        Link("Image source", destination: info.sourceURL)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel("Open image source, \(info.sourceName)")
    }

    private var licenseLink: some View {
        Link("License", destination: info.licenseURL)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel("Open image license, \(info.licenseName)")
    }
}
