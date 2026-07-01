import SharedCode
import SwiftUI

struct TonightsBestTargetsCard: View {
    let recommendations: [TargetRecommendation]
    let timeZone: TimeZone?
    let nightQualityScore: Int?
    let hasAdditionalTargets: Bool
    let onViewAll: (() -> Void)?

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
    }
}

struct TargetRecommendationRow: View {
    let recommendation: TargetRecommendation
    let timeZone: TimeZone?

    private var windowText: String {
        DateFormatters.formatDashboardObservingTimeRange(
            from: recommendation.visibilityWindow.start,
            to: recommendation.visibilityWindow.end,
            in: timeZone
        )
    }

    private var targetName: String {
        switch recommendation.target.id.lowercased() {
        case "venus":
            return "Venus"
        case "mars":
            return "Mars"
        case "jupiter":
            return "Jupiter"
        case "saturn":
            return "Saturn"
        default:
            return recommendation.target.name
        }
    }

    private var positionText: String? {
        let direction = recommendation.visibilityWindow.direction
        let altitude = recommendation.visibilityWindow.maxAltitude.map { "\(Int(round($0)))°" }

        switch (direction, altitude) {
        case let (direction?, altitude?):
            return "\(direction) · \(altitude)"
        case let (direction?, nil):
            return direction
        case let (nil, altitude?):
            return altitude
        case (nil, nil):
            return nil
        }
    }

    private var scoreColor: Color {
        switch recommendation.score {
        case 80...100:
            return .green
        case 60..<80:
            return .blue
        case 40..<60:
            return .orange
        default:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(targetName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(recommendation.target.displayTypeName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text("\(recommendation.score)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor)
                    Text("/100")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Score \(recommendation.score) out of 100")
            }

            Text(recommendation.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(windowText)
                    .font(.caption)
                    .fontWeight(.medium)

                if let positionText {
                    Text(positionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }
}

struct BestTargetsListView: View {
    @Environment(\.dismiss) private var dismiss
    let presentation: BestTargetsListPresentation
    let timeZone: TimeZone?
    @State private var filter: BestTargetsFilter = .all

    private var sections: [BestTargetsSection] {
        presentation.sections(for: filter)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Targets", selection: $filter) {
                        ForEach(BestTargetsFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if sections.isEmpty {
                    ContentUnavailableView(
                        "No Targets",
                        systemImage: "scope",
                        description: Text("No targets in this category score 45 or higher.")
                    )
                } else {
                    ForEach(sections) { section in
                        Section(section.band.rawValue) {
                            ForEach(section.recommendations) { recommendation in
                                TargetRecommendationRow(
                                    recommendation: recommendation,
                                    timeZone: timeZone
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Best Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
