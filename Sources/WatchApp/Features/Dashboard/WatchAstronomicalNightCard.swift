import SwiftUI
import SharedCode

struct WatchAstronomicalNightCard: View {
    let sunEvents: SunEvents
    let moonInfo: MoonInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Astronomical Night")
                .font(.caption)
                .foregroundStyle(.secondary)

            if sunEvents.astronomicalNightStart > sunEvents.astronomicalNightEnd {
                HStack(spacing: 4) {
                    Text(DateFormatters.formatTime(sunEvents.astronomicalNightStart))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("to")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(DateFormatters.formatTime(sunEvents.astronomicalNightEnd))
                        .font(.caption)
                        .fontWeight(.medium)
                }

                let duration = sunEvents.astronomicalNightDuration
                Text(formatDuration(duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not available tonight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text(moonInfo.emoji)
                Text(moonInfo.phaseName)
                    .font(.caption)
                Text("\(moonInfo.illumination)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return String(format: "%dh %dm", hours, minutes)
    }
}