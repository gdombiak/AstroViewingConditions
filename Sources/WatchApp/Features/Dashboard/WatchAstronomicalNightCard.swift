import SwiftUI
import SharedCode

struct WatchAstronomicalNightCard: View {
    let sunEvents: SunEvents
    let tomorrowSunEvents: SunEvents?
    let moonInfo: MoonInfo
    let timeZone: TimeZone?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Astronomical Night")
                .font(.caption)
                .foregroundStyle(.secondary)

            let nightEnd = sunEvents.astronomicalNightEnd(using: tomorrowSunEvents)

            if sunEvents.astronomicalNightStart < nightEnd {
                HStack(spacing: 4) {
                    Text(DateFormatters.formatTime(sunEvents.astronomicalNightStart, in: timeZone))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("to")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(DateFormatters.formatTime(nightEnd, in: timeZone))
                        .font(.caption)
                        .fontWeight(.medium)
                }

                let duration = sunEvents.astronomicalNightDuration(using: tomorrowSunEvents)
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
