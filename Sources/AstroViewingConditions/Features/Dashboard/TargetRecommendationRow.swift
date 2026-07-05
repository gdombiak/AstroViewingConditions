import SharedCode
import SwiftUI

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
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            TargetIntentBadge(intent: recommendation.target.observingIntent)
        }
    }

    private var scoreView: some View {
        HStack(spacing: 4) {
            Text("\(recommendation.score)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(TargetScoreColorProvider.color(for: recommendation.score))
            Text("/100")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
