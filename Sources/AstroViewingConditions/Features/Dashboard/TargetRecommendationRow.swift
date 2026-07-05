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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(targetName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Text(recommendation.target.displayTypeName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TargetIntentBadge(intent: recommendation.target.observingIntent)

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
