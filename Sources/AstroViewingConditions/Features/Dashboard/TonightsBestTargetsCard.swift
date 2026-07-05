import SharedCode
import SwiftUI

struct TonightsBestTargetsCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let recommendations: [TargetRecommendation]
    let timeZone: TimeZone?
    let nightQualityScore: Int?
    let hasAdditionalTargets: Bool
    let onViewAll: (() -> Void)?
    @State private var selectedRecommendation: TargetRecommendation?

    init(
        recommendations: [TargetRecommendation],
        timeZone: TimeZone?,
        nightQualityScore: Int?,
        hasAdditionalTargets: Bool = false,
        onViewAll: (() -> Void)? = nil
    ) {
        self.recommendations = recommendations
        self.timeZone = timeZone
        self.nightQualityScore = nightQualityScore
        self.hasAdditionalTargets = hasAdditionalTargets
        self.onViewAll = onViewAll
    }

    static func showsPoorConditionsNote(for nightQualityScore: Int?) -> Bool {
        guard let nightQualityScore else { return false }
        return nightQualityScore < 30
    }

    static func showsViewAll(hasAdditionalTargets: Bool) -> Bool {
        hasAdditionalTargets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Best Targets", systemImage: "scope")
                    .font(.headline)
                Spacer()
                if Self.showsViewAll(hasAdditionalTargets: hasAdditionalTargets), let onViewAll {
                    Button("View All", action: onViewAll)
                        .font(.subheadline)
                } else if !recommendations.isEmpty {
                    Text("\(recommendations.count) picks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if Self.showsPoorConditionsNote(for: nightQualityScore) {
                Label("Poor sky conditions; targets shown for planning.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if recommendations.isEmpty {
                Text("No target recommendations available tonight")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(recommendations.prefix(5)) { recommendation in
                        TargetRecommendationRow(
                            recommendation: recommendation,
                            timeZone: timeZone
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRecommendation = recommendation }
                        .accessibilityAddTraits(.isButton)

                        if recommendation.id != recommendations.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $selectedRecommendation) { recommendation in
            TargetDetailView(recommendation: recommendation, timeZone: timeZone)
                .adaptiveTargetSheet(
                    horizontalSizeClass: horizontalSizeClass,
                    prefersTallerPresentation: true
                )
        }
    }
}

#Preview {
    TonightsBestTargetsCard(
        recommendations: [
            TargetRecommendation(
                target: ObservableTarget(
                    id: "m13",
                    name: "M13 Hercules Cluster",
                    type: .deepSky,
                    preferredEquipment: .binoculars,
                    difficulty: 0.5
                ),
                score: 84,
                visibilityWindow: TargetVisibilityWindow(
                    start: Date().addingTimeInterval(3600),
                    end: Date().addingTimeInterval(10800),
                    bestTime: Date().addingTimeInterval(7200),
                    maxAltitude: 72,
                    direction: "W"
                ),
                reasons: [.highAltitude, .astronomicalDarkness],
                summary: "High in the sky during astronomical darkness."
            )
        ],
        timeZone: nil,
        nightQualityScore: 85,
        hasAdditionalTargets: true,
        onViewAll: {}
    )
    .padding()
}
