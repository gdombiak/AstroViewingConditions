import SharedCode
import SwiftUI

struct TargetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appPalette) private var palette
    @State private var viewerPresentation = TargetImageViewerPresentationState()
    let recommendation: TargetRecommendation
    let timeZone: TimeZone?
    let equipmentFit: EquipmentFitResult?

    init(
        recommendation: TargetRecommendation,
        timeZone: TimeZone?,
        equipmentFit: EquipmentFitResult? = nil
    ) {
        self.recommendation = recommendation
        self.timeZone = timeZone
        self.equipmentFit = equipmentFit
    }

    private var content: TargetDetailContent {
        TargetDetailContentBuilder().build(from: recommendation, timeZone: timeZone)
    }

    private let imageRepository = TargetImageRepository()

    private var shouldHideBestEquipment: Bool {
        Self.shouldHideBestEquipment(for: equipmentFit?.level)
    }

    static func shouldHideBestEquipment(for fitLevel: EquipmentFitLevel?) -> Bool {
        guard let fitLevel else { return false }
        return fitLevel != .poor
    }

    private var identityLeadingColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.name)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(content.displayType)
                    .foregroundStyle(.secondary)
                TargetIntentBadge(intent: recommendation.target.observingIntent)
            }
        }
    }

    /// Trailing score block: secondary label above star + prominent N / 100.
    private var identityScoreBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(TargetScorePresentation.conciseLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.body)
                    .foregroundStyle(TargetScoreColorProvider.color(for: content.score, palette: palette))
                    .accessibilityHidden(true)
                Text("\(content.score) / 100")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TargetScoreColorProvider.color(for: content.score, palette: palette))
                    .monospacedDigit()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TargetScorePresentation.accessibilityLabel(score: content.score))
    }

    var body: some View {
        NavigationStack {
            List {
                if let resolvedImage = imageRepository.heroImage(for: recommendation.target.id) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            TargetHeroImage(
                                image: resolvedImage.image,
                                accessibilityName: content.name,
                                action: { viewerPresentation.present(resolvedImage) }
                            )
                            TargetImageAttributionView(info: resolvedImage.record)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        // Name/type leading; target score trailing — uses card width at normal sizes.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                identityLeadingColumn
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .layoutPriority(1)
                                identityScoreBlock
                            }
                            // Large Dynamic Type: stack rather than truncate.
                            VStack(alignment: .leading, spacing: 8) {
                                identityLeadingColumn
                                identityScoreBlock
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let guidance = TargetIntentPresentation.detailGuidance(for: recommendation.target.observingIntent) {
                            Text(guidance)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("When & Where") {
                    LabeledContent("Best time", value: content.bestTime)
                    if let direction = content.directionText { LabeledContent("Direction", value: direction) }
                    if let altitude = content.altitudeText { LabeledContent("Altitude", value: altitude) }
                }

                if let equipmentFit {
                    Section("Equipment Suitability") {
                        Text(equipmentFit.explanation)
                    }
                }

                ForEach(content.sections(hidingBestEquipment: shouldHideBestEquipment)) { section in
                    Section(section.title) { Text(section.text) }
                }
            }
            .appListBackground()
            .appNavigationTitle("Target Details", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .fullScreenCover(item: $viewerPresentation.image) { resolvedImage in
            TargetImageViewer(resolvedImage: resolvedImage, targetName: content.name)
        }
    }
}
