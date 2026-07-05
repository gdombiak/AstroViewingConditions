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
            .navigationTitle("Best Targets")
            .navigationBarTitleDisplayMode(.inline)
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
