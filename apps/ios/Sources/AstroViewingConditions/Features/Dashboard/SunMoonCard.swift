import SharedCode
import SwiftUI

struct SunMoonCard: View {
    @Environment(\.appPalette) private var palette
    let sunEvents: SunEvents
    let tomorrowSunEvents: SunEvents?
    let moonInfo: MoonInfo
    let timeZone: TimeZone?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var sunEventSpacing: CGFloat {
        isIPad ? 60 : 20
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sun Section
            VStack(alignment: .leading, spacing: 12) {
                Label("Sun", systemImage: "sun.max.fill")
                    .font(.headline)
                
                HStack(spacing: sunEventSpacing) {
                    SunEventItem(
                        icon: "sunrise.fill",
                        time: sunEvents.sunrise,
                        label: "Sunrise",
                        timeZone: timeZone
                    )
                    
                    SunEventItem(
                        icon: "sunset.fill",
                        time: sunEvents.sunset,
                        label: "Sunset",
                        timeZone: timeZone
                    )
                }
                
                // Astronomical Night
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(palette.appearance == .field ? palette.accent : .indigo)
                        Text("Astronomical Night")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    astronomicalNightDetails
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
                
                moonDetails
            }
        }
        .dashboardCardStyle()
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return String(format: "%dh %dm", hours, minutes)
    }

    private var usesExpandedLayout: Bool {
        dynamicTypeSize.requiresExpandedCompactLayout && !isIPad
    }

    private var astronomicalTimeRange: some View {
        HStack(spacing: usesExpandedLayout ? 8 : 16) {
            Text(DateFormatters.formatTime(sunEvents.astronomicalNightStart, in: timeZone))
                .font(.subheadline)
                .fontWeight(.semibold)
                .fixedSize(horizontal: true, vertical: false)
            Text("to")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text(DateFormatters.formatTime(sunEvents.astronomicalNightEnd(using: tomorrowSunEvents), in: timeZone))
                .font(.subheadline)
                .fontWeight(.semibold)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stackedAstronomicalTimeRange: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DateFormatters.formatTime(sunEvents.astronomicalNightStart, in: timeZone))
                .font(.subheadline)
                .fontWeight(.semibold)
                .fixedSize(horizontal: true, vertical: false)
            Text("to")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(DateFormatters.formatTime(sunEvents.astronomicalNightEnd(using: tomorrowSunEvents), in: timeZone))
                .font(.subheadline)
                .fontWeight(.semibold)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var durationView: some View {
        HStack(spacing: 4) {
            Text("Duration:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(formatDuration(sunEvents.astronomicalNightDuration(using: tomorrowSunEvents)))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(palette.appearance == .field ? palette.accent : .indigo)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var astronomicalNightDetails: some View {
        if usesExpandedLayout {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    astronomicalTimeRange
                    stackedAstronomicalTimeRange
                }
                durationView
            }
        } else {
            HStack {
                astronomicalTimeRange
                Spacer()
                durationView
            }
        }
    }

    @ViewBuilder
    private var moonDetails: some View {
        if usesExpandedLayout {
            VStack(alignment: .leading, spacing: 8) {
                Text(moonInfo.emoji)
                    .font(.system(size: 48))
                Text("Illumination: \(moonInfo.illumination)%")
                    .font(.footnote)
                    .fontWeight(.semibold)
                altitudeView
            }
        } else {
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(moonInfo.emoji)
                        .font(.system(size: 48))
                    Text("Illumination: \(moonInfo.illumination)%")
                        .font(.footnote)
                        .fontWeight(.semibold)
                }

                altitudeView
                Spacer()
            }
        }
    }

    private var altitudeView: some View {
        HStack {
            Image(systemName: "arrow.up")
                .foregroundStyle(.secondary)
            Text("Altitude: \(String(format: "%.1f°", moonInfo.altitude))")
                .font(.subheadline)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct SunEventItem: View {
    let icon: String
    let time: Date
    let label: String
    let timeZone: TimeZone?
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatters.formatTime(time, in: timeZone))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.footnote)
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
        tomorrowSunEvents: SunEvents(
            sunrise: Date().addingTimeInterval(3600 * 23),
            sunset: Date().addingTimeInterval(3600 * 32),
            civilTwilightBegin: Date().addingTimeInterval(3600 * 22.5),
            civilTwilightEnd: Date().addingTimeInterval(3600 * 32.5),
            nauticalTwilightBegin: Date().addingTimeInterval(3600 * 22),
            nauticalTwilightEnd: Date().addingTimeInterval(3600 * 33),
            astronomicalTwilightBegin: Date().addingTimeInterval(3600 * 21.5),
            astronomicalTwilightEnd: Date().addingTimeInterval(3600 * 33.5)
        ),
        moonInfo: MoonInfo(
            phase: 0.25,
            phaseName: "First Quarter",
            altitude: 45.5,
            illumination: 50,
            emoji: "🌓"
        ),
        timeZone: nil
    )
    .padding()
}
