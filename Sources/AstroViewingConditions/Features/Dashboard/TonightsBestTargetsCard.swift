import SharedCode
import SwiftUI

enum TargetScoreColorProvider {
    enum Category: Equatable {
        case excellent
        case good
        case fair
        case poor
    }

    static func category(for score: Int) -> Category {
        switch score {
        case 80...100: return .excellent
        case 60..<80: return .good
        case 40..<60: return .fair
        default: return .poor
        }
    }

    static func color(for score: Int) -> Color {
        switch category(for: score) {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

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

struct TargetRecommendationRow: View {
    let recommendation: TargetRecommendation
    let timeZone: TimeZone?
    var showsThumbnail = false
    private let imageRepository = TargetImageRepository()

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

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsThumbnail,
               let image = imageRepository.thumbnailImage(for: recommendation.target.id) {
                TargetThumbnail(image: image, size: 48)
            }

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
                        .foregroundStyle(TargetScoreColorProvider.color(for: recommendation.score))
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
        }
        .padding(.vertical, 4)
    }
}

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

struct TargetDetailContent: Equatable {
    struct Section: Equatable, Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    let name: String
    let displayType: String
    let score: Int
    let bestTime: String
    let compassDirectionLabel: String?
    let directionText: String?
    let altitudeDegrees: Double?
    let altitudeText: String?
    let azimuthDegrees: Double?
    let azimuthText: String?
    let imageAttribution: String?
    let sections: [Section]

    // Compatibility conveniences for call sites that only need display text.
    var direction: String? { directionText }
    var altitude: String? { altitudeText }

    var sectionsText: String {
        sections.map { "\($0.title) \($0.text)" }.joined(separator: " ")
    }

    var whyRecommended: String {
        sections.first(where: { $0.title == "Why recommended" })?.text ?? ""
    }
}

struct TargetDetailContentBuilder {
    func build(
        from recommendation: TargetRecommendation,
        timeZone: TimeZone? = nil
    ) -> TargetDetailContent {
        let target = recommendation.target
        let window = recommendation.visibilityWindow
        let windowText = DateFormatters.formatDashboardObservingTimeRange(
            from: window.start,
            to: window.end,
            in: timeZone
        )

        return TargetDetailContent(
            name: target.name,
            displayType: target.displayTypeName,
            score: recommendation.score,
            bestTime: windowText,
            compassDirectionLabel: window.direction,
            directionText: window.direction.map(Self.directionText),
            altitudeDegrees: window.maxAltitude,
            altitudeText: window.maxAltitude.map(Self.altitudeText),
            azimuthDegrees: window.azimuth,
            azimuthText: window.azimuth.map(Self.azimuthText),
            imageAttribution: target.image?.attributionText,
            sections: [
                .init(title: "Why recommended", text: whyRecommended(recommendation)),
                .init(title: "How to find it", text: howToFind(target, window: window, windowText: windowText)),
                .init(title: "Best equipment", text: equipment(for: target)),
                .init(title: "Observing notes", text: observingNotes(for: target))
            ]
        )
    }

    private func whyRecommended(_ recommendation: TargetRecommendation) -> String {
        let target = recommendation.target
        let reasons = Set(recommendation.reasons)
        let summary = recommendation.summary
        let summaryLower = summary.lowercased()
        let hasBrightMoonImpact = reasons.contains(.moonInterference)
            || reasons.contains(.brightFullMoonDeepSkyImpact)
            || summaryLower.contains("bright moon")

        if target.type == .moon, reasons.contains(.brightFullMoonDeepSkyImpact) {
            return "The bright full Moon is a good lunar target for this night, though it will make faint deep-sky objects harder to see."
        }

        if target.type == .planet, reasons.contains(.lowAltitude) {
            let obstruction = "This planet is visible, but it stays low in the sky, so trees, hills, or buildings may get in the way."
            if reasons.contains(.outsideAstronomicalDarkness) {
                return "\(obstruction) Its best window is in twilight rather than full darkness."
            }
            return obstruction
        }

        if hasBrightMoonImpact {
            if target.id.lowercased() == "m27" {
                return "This large, bright planetary nebula is well placed during this observing window. The bright Moon may reduce contrast, but M27 is still worth trying because its dumbbell shape can stand out better than many faint nebulae."
            }

            switch target.deepSkyObjectType {
            case .doubleStar:
                return Self.joinSentences(
                    "This is a good target even under a bright Moon.",
                    placementSentence(reasons: reasons)
                )
            case .planetaryNebula:
                return "This small bright nebula is well placed during this observing window. The bright Moon may reduce contrast, but it should still be worth trying."
            case .globularCluster:
                return "This cluster is high in the sky during the best window. The bright Moon has a moderate impact, but it remains a useful telescope target."
            case .galaxy:
                return "This galaxy is well placed, but the bright Moon will wash out much of its detail."
            default:
                break
            }
        }

        var sentences: [String] = []
        if summaryLower != "visible tonight." {
            sentences.append(Self.dateNeutralized(summary))
        }
        if let placement = placementSentence(reasons: reasons),
           !sentences.contains(where: { Self.overlapsPlacement($0, placement) }) {
            sentences.append(placement)
        }
        if sentences.isEmpty {
            sentences.append("This target should be worth observing during its best window.")
        }
        return sentences.prefix(3).joined(separator: " ")
    }

    private func placementSentence(reasons: Set<TargetRecommendationReason>) -> String? {
        let isHigh = reasons.contains(.highAltitude)
        let isDark = reasons.contains(.astronomicalDarkness)
        let goodWeather = reasons.contains(.goodNightQuality)
        let poorWeather = reasons.contains(.poorWeather)

        var clause: String?
        if isHigh && isDark {
            clause = "It will be high in the sky during astronomical darkness"
        } else if isHigh {
            clause = "It will be high in the sky during the best window"
        } else if isDark {
            clause = "It will be visible during astronomical darkness"
        }

        if goodWeather {
            return clause.map { "\($0), and the weather looks favorable." }
                ?? "The weather looks favorable during the best window."
        }
        if poorWeather {
            return clause.map { "\($0), though clouds or haze may interfere." }
                ?? "Clouds or haze may make it harder to see."
        }
        return clause.map { "\($0)." }
    }

    private func howToFind(
        _ target: ObservableTarget,
        window: TargetVisibilityWindow,
        windowText: String
    ) -> String {
        var instructions: [String] = []
        if target.id.lowercased() == "m27" {
            if let direction = window.direction {
                instructions.append("Look \(Self.directionName(direction)), in Vulpecula near Sagitta and Cygnus.")
            } else {
                instructions.append("Look in Vulpecula near Sagitta and Cygnus.")
            }
        } else if let direction = window.direction {
            instructions.append(Self.directionText(direction))
        }
        if let altitude = window.maxAltitude {
            if target.id.lowercased() == "m27" {
                instructions.append("It is about \(Int(round(altitude)))° high.")
            } else {
                instructions.append(Self.altitudeText(altitude))
            }
        }
        if target.id.lowercased() == "m27" {
            instructions.append("Use low power first, then increase magnification once found.")
        }
        instructions.append("Best from \(windowText.replacingOccurrences(of: " – ", with: " to ")).")
        return instructions.joined(separator: " ")
    }

    private func equipment(for target: ObservableTarget) -> String {
        if target.id.lowercased() == "m27" {
            return "Use a telescope at low to moderate magnification. A nebula filter may help if available."
        }

        switch (target.type, target.deepSkyObjectType) {
        case (.moon, _):
            return "Use the naked eye, binoculars, or a telescope. A Moon filter can reduce brightness and improve comfort."
        case (.planet, _):
            return "Use the naked eye to locate it, then a telescope for detail."
        case (.deepSky, .doubleStar):
            return "For this double star, use a telescope with medium or high magnification to separate the stars."
        case (.deepSky, .globularCluster):
            return "A telescope or smart telescope is best."
        case (.deepSky, .openCluster):
            return "Use binoculars for wide clusters or a telescope for smaller ones."
        case (.deepSky, .planetaryNebula):
            return "Use a telescope; a nebula filter may help if available."
        case (.deepSky, .galaxy):
            return "Use a smart telescope, or observe visually from dark skies. Moonlight can wash out faint galaxy detail."
        case (.deepSky, .diffuseNebula):
            return "Use a telescope or smart telescope. A UHC or OIII filter may help, depending on the object."
        default:
            return "Recommended equipment: \(target.preferredEquipment.displayName)."
        }
    }

    private func observingNotes(for target: ObservableTarget) -> String {
        if target.id.lowercased() == "m27" {
            return "Visually, M27 usually appears as a grayish fuzzy patch with a dumbbell or apple-core shape. Photos show much more color than you should expect at the eyepiece."
        }

        if target.id.lowercased() == "ngc7009" {
            return "Small bright planetary nebula. In a telescope it may look like a tiny blue-green oval; the Saturn-like extensions need higher magnification and good seeing."
        }

        switch (target.type, target.deepSkyObjectType) {
        case (.moon, _): return "Very bright; reduce brightness with a Moon filter if needed."
        case (.planet, _): return "Atmospheric steadiness matters; wait for moments of sharp seeing."
        case (.deepSky, .doubleStar):
            return "Use steady moments of seeing and medium or high magnification to split the pair cleanly."
        case (.deepSky, .planetaryNebula):
            return "Small target; use moderate or high magnification. A nebula filter may help."
        case (.deepSky, .globularCluster):
            return "Higher magnification may begin to resolve stars around the edges."
        case (.deepSky, .galaxy):
            return "Best under dark, moonless skies; use averted vision."
        case (.deepSky, .openCluster):
            return "Use lower magnification to frame the cluster."
        case (.deepSky, .diffuseNebula): return "Dark adaptation and low magnification can make faint structure easier to see."
        default: return "Allow your eyes time to adapt and keep direct lights out of view."
        }
    }

    private static func directionText(_ direction: String) -> String {
        "Look \(directionName(direction))."
    }

    private static func directionName(_ direction: String) -> String {
        let names = ["N": "north", "NE": "northeast", "E": "east", "SE": "southeast",
                     "S": "south", "SW": "southwest", "W": "west", "NW": "northwest"]
        return names[direction.uppercased()] ?? direction.lowercased()
    }

    private static func altitudeText(_ altitude: Double) -> String {
        "About \(Int(round(altitude)))° high."
    }

    private static func azimuthText(_ azimuth: Double) -> String {
        "Azimuth \(Int(round(azimuth)))°"
    }

    private static func joinSentences(_ first: String, _ second: String?) -> String {
        [first, second].compactMap { $0 }.joined(separator: " ")
    }

    private static func dateNeutralized(_ text: String) -> String {
        text.replacingOccurrences(of: "tonight", with: "for this night", options: .caseInsensitive)
    }

    private static func overlapsPlacement(_ existing: String, _ placement: String) -> Bool {
        let existing = existing.lowercased()
        let placement = placement.lowercased()
        return (existing.contains("high in the sky") && placement.contains("high in the sky"))
            || (existing.contains("astronomical darkness") && placement.contains("astronomical darkness"))
            || (existing.contains("weather") && placement.contains("weather"))
    }
}

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
                        Text(content.displayType).foregroundStyle(.secondary)
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
            TargetImageViewer(
                resolvedImage: resolvedImage,
                targetName: content.name
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
