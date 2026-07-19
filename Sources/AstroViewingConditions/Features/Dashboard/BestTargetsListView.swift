import SharedCode
import SwiftUI

struct BestTargetsListView: View {
    static let equipmentFilterEmptyTitle = "No Suitable Targets"
    static let equipmentFilterEmptyDescription = "No targets are suitable enough for the selected equipment and minimum level. Choose a lower level."
    static let removeEquipmentFilterActionTitle = "Set Suitability to Any"

    static var clearedEquipmentFilterThreshold: EquipmentFitThreshold { .any }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let presentation: BestTargetsListPresentation
    let timeZone: TimeZone?
    let equipmentCapabilities: [EquipmentCapability]
    @Binding var sessionSelection: EquipmentSessionSelection
    @Binding var minimumFit: EquipmentFitThreshold
    let unfilteredPresentation: BestTargetsListPresentation
    @State private var filter: BestTargetsFilter = .all
    @State private var selectedRecommendation: TargetRecommendation?
    @State private var showingEquipmentSelector = false

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
                    emptyState
                } else {
                    ForEach(sections) { section in
                        Section(section.band.rawValue) {
                            ForEach(section.recommendations) { recommendation in
                                TargetRecommendationRow(
                                    recommendation: recommendation,
                                    timeZone: timeZone,
                                    equipmentFit: equipmentFit(for: recommendation.target),
                                    showsThumbnail: true
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { selectedRecommendation = recommendation }
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                }
            }
            .appListBackground()
            .appNavigationTitle("Best Targets", displayMode: .inline)
            .toolbar {
                if !equipmentCapabilities.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingEquipmentSelector = true
                        } label: {
                            Label(EquipmentSessionSelectorView.equipmentControlTitle, systemImage: EquipmentSessionSelectorView.equipmentControlIconName)
                        }
                        .accessibilityLabel(EquipmentSessionSelectorView.equipmentControlAccessibilityLabel)
                        .accessibilityHint(EquipmentSessionSelectorView.equipmentControlAccessibilityHint)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecommendation) { recommendation in
                TargetDetailView(
                    recommendation: recommendation,
                    timeZone: timeZone,
                    equipmentFit: equipmentFit(for: recommendation.target)
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
    }

    private func equipmentFit(for target: ObservableTarget) -> EquipmentFitResult? {
        sessionSelection.equipmentFit(for: target, inventory: equipmentCapabilities)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isEquipmentFilterActive {
            ContentUnavailableView {
                Label(Self.equipmentFilterEmptyTitle, systemImage: "scope")
            } description: {
                Text(Self.equipmentFilterEmptyDescription)
            } actions: {
                Button(Self.removeEquipmentFilterActionTitle) { minimumFit = Self.clearedEquipmentFilterThreshold }
            }
        } else {
            ContentUnavailableView(
                "No Targets",
                systemImage: "scope",
                description: Text("No targets in this category score 45 or higher.")
            )
        }
    }

    private var isEquipmentFilterActive: Bool {
        Self.shouldShowEquipmentFilteredEmptyState(
            unfilteredPresentation: unfilteredPresentation,
            filteredPresentation: presentation,
            filter: filter,
            hasSavedEquipment: !equipmentCapabilities.isEmpty,
            minimumFit: minimumFit
        )
    }

    static func shouldShowEquipmentFilteredEmptyState(
        unfilteredPresentation: BestTargetsListPresentation,
        filteredPresentation: BestTargetsListPresentation,
        filter: BestTargetsFilter,
        hasSavedEquipment: Bool,
        minimumFit: EquipmentFitThreshold
    ) -> Bool {
        hasSavedEquipment
            && minimumFit != .any
            && !unfilteredPresentation.sections(for: filter).isEmpty
            && filteredPresentation.sections(for: filter).isEmpty
    }
}

struct EquipmentSessionSelectorView: View {
    static let equipmentControlIconName = "binoculars"
    static let equipmentControlTitle = "Observation Equipment"
    static let equipmentControlAccessibilityLabel = equipmentControlTitle
    static let equipmentControlAccessibilityHint = "Opens observation equipment and target suitability options."
    static let availableForObservationSectionTitle = "Available for Observation"
    static let minimumSuitabilitySectionTitle = "Target Suitability for Your Equipment"
    static let suitabilityPickerLabel = "Minimum level"
    static let suitabilityPickerAccessibilityLabel = "Minimum target suitability for selected equipment"
    static let suitabilityPickerAccessibilityHint = "Choose the lowest equipment suitability level a target must meet to be shown."
    static let footerText = "Targets below this equipment suitability level are hidden. Conditions scores do not change."

    @Environment(\.dismiss) private var dismiss
    @Binding var selection: EquipmentSessionSelection
    let inventory: [EquipmentCapability]
    @Binding var minimumFit: EquipmentFitThreshold

    private var capabilities: [EquipmentCapability] {
        [.nakedEye] + inventory
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Selection") {
                    Button("All My Equipment") {
                        selection.selectAllEquipment()
                    }
                    Button("Naked Eye Only") {
                        selection.selectNakedEyeOnly()
                    }
                }
                Section(Self.availableForObservationSectionTitle) {
                    ForEach(capabilities) { capability in
                        Toggle(capability.displayName, isOn: selectionBinding(for: capability.id))
                    }
                }

                Section {
                    Picker(Self.suitabilityPickerLabel, selection: $minimumFit) {
                        ForEach(EquipmentFitThreshold.presentationOrder, id: \.self) { threshold in
                            Text(threshold.displayName).tag(threshold)
                        }
                    }
                    .accessibilityLabel(Self.suitabilityPickerAccessibilityLabel)
                    .accessibilityValue(minimumFit.displayName)
                    .accessibilityHint(Self.suitabilityPickerAccessibilityHint)
                } header: {
                    Text(Self.minimumSuitabilitySectionTitle)
                } footer: {
                    Text(Self.footerText)
                }
            }
            .appListBackground()
            .appNavigationTitle(Self.equipmentControlTitle, displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func selectionBinding(for id: EquipmentCapabilityID) -> Binding<Bool> {
        Binding(
            get: { selection.isSelected(id, inventory: inventory) },
            set: { newValue in
                selection.setSelected(newValue, for: id, inventory: inventory)
            }
        )
    }
}

#Preview("Best Targets Field Mode") {
    BestTargetsListView(
        presentation: BestTargetsListPresentation(recommendations: [
            TargetRecommendation(
                target: ObservableTarget(
                    id: "m13",
                    name: "M13 Hercules Cluster",
                    type: .deepSky,
                    preferredEquipment: .smallTelescope,
                    difficulty: 0.5,
                    observingIntent: .standard
                ),
                score: 84,
                visibilityWindow: TargetVisibilityWindow(
                    start: Date(),
                    end: Date().addingTimeInterval(7_200),
                    bestTime: Date().addingTimeInterval(3_600),
                    maxAltitude: 68,
                    direction: "S"
                ),
                reasons: [.highAltitude, .astronomicalDarkness],
                summary: "High in the sky during astronomical darkness."
            )
        ]),
        timeZone: .current,
        equipmentCapabilities: [],
        sessionSelection: .constant(EquipmentSessionSelection()),
        minimumFit: .constant(.any),
        unfilteredPresentation: BestTargetsListPresentation(recommendations: [])
    )
    .appAppearance(fieldModeEnabled: true)
}
