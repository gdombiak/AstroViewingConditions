import SwiftUI
import SharedCode

struct WatchSunMoonCard: View {
    let sunEvents: SunEvents
    let moonInfo: MoonInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sunrise")
                Text(sunEvents.sunrise, style: .time)
                    .font(.caption)
            }

            HStack {
                Image(systemName: "sunset")
                Text(sunEvents.sunset, style: .time)
                    .font(.caption)
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
}
