import SwiftUI

struct SunMoonCard: View {
    let sunEvents: SunEvents
    let moonInfo: MoonInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sun Section
            VStack(alignment: .leading, spacing: 12) {
                Label("Sun", systemImage: "sun.max.fill")
                    .font(.headline)
                
                HStack(spacing: 20) {
                    SunEventItem(
                        icon: "sunrise.fill",
                        time: sunEvents.sunrise,
                        label: "Sunrise"
                    )
                    
                    SunEventItem(
                        icon: "sunset.fill",
                        time: sunEvents.sunset,
                        label: "Sunset"
                    )
                }
                
                // Astronomical Night
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(.indigo)
                        Text("Astronomical Night")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start: \(DateFormatters.formatTime(sunEvents.astronomicalNightStart))")
                                .font(.caption)
                            Text("End: \(DateFormatters.formatTime(sunEvents.astronomicalNightEnd))")
                                .font(.caption)
                        }
                        Spacer()
                        Text(formatDuration(sunEvents.astronomicalNightDuration(on: Date())))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.indigo)
                    }
                }
                .padding(.top, 4)
            }
            
            Divider()
            
            // Moon Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Moon", systemImage: "moon.fill")
                        .font(.headline)
                    Spacer()
                    Text(moonInfo.phaseName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 16) {
                    // Moon emoji and phase
                    VStack(spacing: 4) {
                        Text(moonInfo.emoji)
                            .font(.system(size: 48))
                        Text("\(moonInfo.illumination)%")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.up")
                                .foregroundStyle(.secondary)
                            Text("Altitude: \(String(format: "%.1f°", moonInfo.altitude))")
                                .font(.subheadline)
                        }
                        
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("Phase: \(String(format: "%.1f", moonInfo.phase * 100))%")
                                .font(.subheadline)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var cardBackgroundColor: Color {
        #if os(iOS)
        return Color(uiColor: .systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return String(format: "%dh %dm", hours, minutes)
    }
}

struct SunEventItem: View {
    let icon: String
    let time: Date
    let label: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatters.formatTime(time))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SunMoonCard(
        sunEvents: SunEvents(
            sunrise: Date().addingTimeInterval(-3600),
            sunset: Date().addingTimeInterval(3600 * 8),
            civilTwilightBegin: Date().addingTimeInterval(-3600 * 1.5),
            civilTwilightEnd: Date().addingTimeInterval(3600 * 8.5),
            nauticalTwilightBegin: Date().addingTimeInterval(-3600 * 2),
            nauticalTwilightEnd: Date().addingTimeInterval(3600 * 9),
            astronomicalTwilightBegin: Date().addingTimeInterval(-3600 * 2.5),
            astronomicalTwilightEnd: Date().addingTimeInterval(3600 * 9.5)
        ),
        moonInfo: MoonInfo(
            phase: 0.25,
            phaseName: "First Quarter",
            altitude: 45.5,
            illumination: 50,
            emoji: "🌓"
        )
    )
    .padding()
}
