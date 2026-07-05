import SharedCode
import SwiftUI

struct TargetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewerPresentation = TargetImageViewerPresentationState()
    let recommendation: TargetRecommendation
    let timeZone: TimeZone?

    private var content: TargetDetailContent {
        TargetDetailContentBuilder().build(from: recommendation, timeZone: timeZone)
    }

    private let imageRepository = TargetImageRepository()

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(content.name).font(.title2.bold())
                        HStack(spacing: 8) {
                            Text(content.displayType).foregroundStyle(.secondary)
                            TargetIntentBadge(intent: recommendation.target.observingIntent)
                        }
                        if let guidance = TargetIntentPresentation.detailGuidance(for: recommendation.target.observingIntent) {
                            Text(guidance)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Label("\(content.score) / 100", systemImage: "star.fill")
                            .foregroundStyle(TargetScoreColorProvider.color(for: content.score))
                            .accessibilityLabel("Score \(content.score) out of 100")
                    }
                    .padding(.vertical, 4)
                }

                Section("When & Where") {
                    LabeledContent("Best time", value: content.bestTime)
                    if let direction = content.directionText { LabeledContent("Direction", value: direction) }
                    if let altitude = content.altitudeText { LabeledContent("Altitude", value: altitude) }
                }

                ForEach(content.sections) { section in
                    Section(section.title) { Text(section.text) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Target Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .fullScreenCover(item: $viewerPresentation.image) { resolvedImage in
            TargetImageViewer(resolvedImage: resolvedImage, targetName: content.name)
        }
    }
}
