import SharedCode
import SwiftUI

struct TonightsBestTargetsCard: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appPalette) private var palette
    let recommendations: [TargetRecommendation]
    let timeZone: TimeZone?
    let nightQualityScore: Int?
    let hasAdditionalTargets: Bool
    let equipmentCapabilities: [EquipmentCapability]
    @Binding var sessionSelection: EquipmentSessionSelection
    @Binding var minimumFit: EquipmentFitThreshold
    let hasUnfilteredVisibleTargets: Bool
    let onViewAll: (() -> Void)?
    @State private var selectedRecommendation: TargetRecommendation?
    @State private var showingEquipmentSelector = false

    init(
        recommendations: [TargetRecommendation],
        timeZone: TimeZone?,
        nightQualityScore: Int?,
        hasAdditionalTargets: Bool = false,
        equipmentCapabilities: [EquipmentCapability],
        sessionSelection: Binding<EquipmentSessionSelection>,
        minimumFit: Binding<EquipmentFitThreshold>,
        hasUnfilteredVisibleTargets: Bool,
        onViewAll: (() -> Void)? = nil
    ) {
        self.recommendations = recommendations
        self.timeZone = timeZone
        self.nightQualityScore = nightQualityScore
        self.hasAdditionalTargets = hasAdditionalTargets
        self.equipmentCapabilities = equipmentCapabilities
        _sessionSelection = sessionSelection
        _minimumFit = minimumFit
        self.hasUnfilteredVisibleTargets = hasUnfilteredVisibleTargets
        self.onViewAll = onViewAll
    }

    static func showsPoorConditionsNote(for nightQualityScore: Int?) -> Bool {
        guard let nightQualityScore else { return false }
        return nightQualityScore < 30
    }

    static func showsViewAll(hasAdditionalTargets: Bool) -> Bool {
        hasAdditionalTargets
    }

    static func equipmentControlAccessibilityValue(
        selectionSummary: String,
        minimumFit: EquipmentFitThreshold
    ) -> String {
        "\(selectionSummary). \(minimumFit.dashboardAccessibilitySummary)"
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if Self.showsPoorConditionsNote(for: nightQualityScore) {
                Label("Poor sky conditions; targets shown for planning.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !equipmentCapabilities.isEmpty {
                equipmentControl
            }

            if recommendations.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(recommendations.prefix(5)) { recommendation in
                        TargetRecommendationRow(
                            recommendation: recommendation,
                            timeZone: timeZone,
                            equipmentFit: equipmentFit(for: recommendation.target)
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
        .dashboardCardStyle()
        .sheet(item: $selectedRecommendation) { recommendation in
            TargetDetailView(
                recommendation: recommendation,
                timeZone: timeZone,
                equipmentFit: sessionSelection.equipmentFit(
                    for: recommendation.target,
                    inventory: equipmentCapabilities
                )
            )
                .adaptiveTargetSheet(
                    horizontalSizeClass: horizontalSizeClass,
                    prefersTallerPresentation: true
                )
        }
        .sheet(isPresented: $showingEquipmentSelector) {
            EquipmentSessionSelectorView(
                selection: $sessionSelection,
                inventory: equipmentCapabilities,
                minimumFit: $minimumFit
            )
        }
    }

    private var equipmentControl: some View {
        Button {
            showingEquipmentSelector = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: EquipmentSessionSelectorView.equipmentControlIconName)
                    .font(.title3)
                    .foregroundStyle(palette.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(EquipmentSessionSelectorView.equipmentControlTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(selectionSummary)
                        .font(.footnote)
                        .appSecondaryForeground()
                    Text(minimumFit.dashboardSummary)
                        .font(.footnote)
                        .appSecondaryForeground()
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .appSecondaryForeground()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EquipmentSessionSelectorView.equipmentControlAccessibilityLabel)
        .accessibilityValue(
            Self.equipmentControlAccessibilityValue(
                selectionSummary: selectionSummary,
                minimumFit: minimumFit
            )
        )
        .accessibilityHint(EquipmentSessionSelectorView.equipmentControlAccessibilityHint)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isEquipmentFilterActive {
            VStack(spacing: 8) {
                Text(BestTargetsListView.equipmentFilterEmptyTitle)
                    .font(.subheadline.weight(.semibold))
                Text(BestTargetsListView.equipmentFilterEmptyDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(BestTargetsListView.removeEquipmentFilterActionTitle) {
                    minimumFit = BestTargetsListView.clearedEquipmentFilterThreshold
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            Text("No target recommendations available tonight")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }

    private var selectionSummary: String {
        if sessionSelection.mode == .allEquipment {
            return "All My Equipment"
        }
        let capabilities = sessionSelection.selectedCapabilities(from: equipmentCapabilities)
        if capabilities == [.nakedEye] {
            return "Naked Eye Only"
        }
        return capabilities.map(\.displayName).joined(separator: ", ")
    }

    private var isEquipmentFilterActive: Bool {
        !equipmentCapabilities.isEmpty
            && minimumFit != .any
            && hasUnfilteredVisibleTargets
    }

    private func equipmentFit(for target: ObservableTarget) -> EquipmentFitResult? {
        sessionSelection.equipmentFit(for: target, inventory: equipmentCapabilities)
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
        equipmentCapabilities: [],
        sessionSelection: .constant(EquipmentSessionSelection()),
        minimumFit: .constant(.any),
        hasUnfilteredVisibleTargets: false,
        onViewAll: {}
    )
    .padding()
}
