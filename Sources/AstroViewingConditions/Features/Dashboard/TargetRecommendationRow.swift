import SharedCode
import SwiftUI

struct TargetRecommendationRow: View {
    @Environment(\.appPalette) private var palette
    let recommendation: TargetRecommendation
    let timeZone: TimeZone?
    var equipmentFit: EquipmentFitResult? = nil
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
        case "venus": return "Venus"
        case "mars": return "Mars"
        case "jupiter": return "Jupiter"
        case "saturn": return "Saturn"
        default: return recommendation.target.name
        }
    }

    private var positionText: String? {
        let direction = recommendation.visibilityWindow.direction
        let altitude = recommendation.visibilityWindow.maxAltitude.map { "\(Int(round($0)))°" }

        switch (direction, altitude) {
        case let (direction?, altitude?): return "\(direction) · \(altitude)"
        case let (direction?, nil): return direction
        case let (nil, altitude?): return altitude
        case (nil, nil): return nil
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showsThumbnail,
               let image = imageRepository.thumbnailImage(for: recommendation.target.id) {
                TargetThumbnail(image: image, size: 48)
            }

            VStack(alignment: .leading, spacing: 6) {
                if showsThumbnail {
                    compactListHeader
                } else {
                    dashboardHeader
                }

                Text(recommendation.summary)
                    .font(.footnote)
                    .appSecondaryForeground()
                    .fixedSize(horizontal: false, vertical: true)

                if let equipmentFit {
                    HStack(spacing: 0) {
                        Text(equipmentFit.level.displayName)
                            .foregroundStyle(Self.suitabilityColor(for: equipmentFit.level, palette: palette))
                        Text(" · \(equipmentFit.bestCapability.displayName)")
                            .appSecondaryForeground()
                    }
                        .font(.footnote)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.equipmentSuitabilityAccessibilityLabel(
                            level: equipmentFit.level,
                            capabilityName: equipmentFit.bestCapability.displayName
                        ))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(windowText)
                        .font(.footnote)
                        .fontWeight(.medium)

                    if let positionText {
                        Text(positionText)
                            .font(.footnote)
                            .appTertiaryForeground()
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 4)
    }

    static func equipmentSuitabilitySummary(
        level: EquipmentFitLevel,
        capabilityName: String
    ) -> String {
        "\(level.displayName) · \(capabilityName)"
    }

    static func equipmentSuitabilityAccessibilityLabel(
        level: EquipmentFitLevel,
        capabilityName: String
    ) -> String {
        "Equipment suitability: \(level.displayName) with \(capabilityName)."
    }

    static func suitabilityColor(for level: EquipmentFitLevel, palette: AppPalette) -> Color {
        if palette.appearance == .field {
            switch level {
            case .excellent: return palette.primaryText
            case .good: return palette.secondaryText
            case .challenging: return palette.tertiaryText
            case .poor: return palette.disabledText
            }
        }

        let tone: AppStatusTone
        switch level {
        case .excellent: tone = .positive
        case .good: tone = .informational
        case .challenging: tone = .caution
        case .poor: tone = .negative
        }
        return palette.statusColor(tone).opacity(0.82)
    }

    private var targetTitle: some View {
        Text(targetName)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var targetMetadata: some View {
        HStack(spacing: 8) {
            Text(recommendation.target.displayTypeName)
                .font(.footnote)
                .fontWeight(.medium)
                .appSecondaryForeground()
                .lineLimit(1)

            TargetIntentBadge(intent: recommendation.target.observingIntent)
        }
    }

    private var scoreView: some View {
        HStack(spacing: 4) {
            Text("\(recommendation.score)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(TargetScoreColorProvider.color(for: recommendation.score, palette: palette))
            Text("/100")
                .font(.footnote)
                .appTertiaryForeground()
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Score \(recommendation.score) out of 100")
    }

    private var compactListHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                targetTitle
                targetMetadata
            }

            Spacer(minLength: 4)
            scoreView
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            targetTitle
            targetMetadata
            Spacer(minLength: 8)
            scoreView
        }
    }
}

#Preview("Compact Best Targets Rows") {
    let targets: [(String, String, TargetObservingIntent, Int)] = [
        ("m101", "M101 Pinwheel Galaxy", .challenge, 79),
        ("ngc7293", "NGC 7293 Helix Nebula", .challenge, 72),
        ("m30", "M30 Globular Cluster", .standard, 68),
        ("m51", "M51 Whirlpool Galaxy", .challenge, 65)
    ]

    List(targets, id: \.0) { target in
        TargetRecommendationRow(
            recommendation: TargetRecommendation(
                target: ObservableTarget(
                    id: target.0,
                    name: target.1,
                    type: .deepSky,
                    preferredEquipment: .smallTelescope,
                    difficulty: 0.7,
                    observingIntent: target.2
                ),
                score: target.3,
                visibilityWindow: TargetVisibilityWindow(
                    start: Date(),
                    end: Date().addingTimeInterval(7200),
                    bestTime: Date().addingTimeInterval(3600),
                    maxAltitude: 48,
                    direction: "S"
                ),
                reasons: [.highAltitude],
                summary: "Well placed during the observing window."
            ),
            timeZone: nil,
            showsThumbnail: true
        )
    }
    .frame(width: 320)
}
