import SharedCode
import SwiftUI

struct BestTargetsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let presentation: BestTargetsListPresentation
    let timeZone: TimeZone?
    @State private var filter: BestTargetsFilter = .all
    @State private var selectedRecommendation: TargetRecommendation?

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
                                    timeZone: timeZone,
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecommendation) { recommendation in
                TargetDetailView(recommendation: recommendation, timeZone: timeZone)
                    .adaptiveTargetSheet(
                        horizontalSizeClass: horizontalSizeClass,
                        prefersTallerPresentation: true
                    )
            }
        }
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
        timeZone: .current
    )
    .appAppearance(fieldModeEnabled: true)
}
