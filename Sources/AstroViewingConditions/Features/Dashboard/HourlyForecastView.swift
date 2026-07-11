import SharedCode
import SwiftUI

struct HourlyForecastView: View {
    let forecasts: [HourlyForecast]
    let unitConverter: AstroUnitConverter
    let timeZone: TimeZone?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var fontScale: CGFloat {
        isIPad ? 1.3 : 1.0
    }
    
    private var columnWidth: CGFloat {
        isIPad ? 80 : 60
    }
    
    private var labelColumnWidth: CGFloat {
        isIPad ? 90 : 70
    }
    
    private var upcomingForecasts: [HourlyForecast] {
        let now = Date()
        let calendar = locationCalendar
        
        return forecasts.filter { forecast in
            guard let forecastHour = calendar.dateInterval(of: .hour, for: forecast.time)?.start,
                  let currentHour = calendar.dateInterval(of: .hour, for: now)?.start else {
                return false
            }
            return forecastHour >= currentHour
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hourly Forecast", systemImage: "clock")
                .font(.headline)
            
            if upcomingForecasts.isEmpty {
                Text("No upcoming forecast data available")
                    .appSecondaryForeground()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Header row with times
                HStack(spacing: 0) {
                    // Fixed labels column (spacer)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("")
                            .frame(height: 28 * fontScale)
                        MetricLabel(icon: "cloud.fill", label: "Cloud", color: .blue, fontScale: fontScale)
                        MetricLabel(icon: "thermometer", label: "Temp", color: .orange, fontScale: fontScale)
                        MetricLabel(icon: "humidity.fill", label: "Humidity", color: .cyan, fontScale: fontScale)
                        MetricLabel(icon: "wind", label: "Wind", color: .gray, fontScale: fontScale)
                        MetricLabel(icon: "arrow.up", label: "Dir", color: .gray, fontScale: fontScale)
                        MetricLabel(icon: "cloud.fog.fill", label: "Fog", color: .gray, fontScale: fontScale)
                        MetricLabel(icon: "eye", label: "Visibility", color: .gray, fontScale: fontScale)
                    }
                    .frame(width: labelColumnWidth)
                    
                    // Scrollable data
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(upcomingForecasts.prefix(24)) { forecast in
                                HourlyColumn(
                                    forecast: forecast,
                                    unitConverter: unitConverter,
                                    isNow: isCurrentHour(forecast.time),
                                    timeZone: timeZone,
                                    fontScale: fontScale,
                                    columnWidth: columnWidth
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .dashboardCardStyle()
    }
    
    private var locationCalendar: Calendar {
        if let timeZone {
            return LocationTimeZoneResolver.calendar(for: timeZone)
        }
        return LocationTimeZoneResolver.calendar(for: TimeZone(secondsFromGMT: 0) ?? TimeZone.current)
    }
    
    private func isCurrentHour(_ date: Date) -> Bool {
        let calendar = locationCalendar
        return calendar.isDateInToday(date) &&
        calendar.component(.hour, from: date) == calendar.component(.hour, from: Date())
    }
}

struct MetricLabel: View {
    @Environment(\.appPalette) private var palette
    let icon: String
    let label: String
    let color: Color
    var fontScale: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(palette.appearance == .field ? palette.accent : color)
            Text(label)
                .font(.system(size: 11 * fontScale, weight: .medium))
                .foregroundStyle(palette.appearance == .field ? palette.secondaryText : .primary)
        }
        .frame(height: 20 * fontScale)
    }
}

struct HourlyColumn: View {
    @Environment(\.appPalette) private var palette
    let forecast: HourlyForecast
    let unitConverter: AstroUnitConverter
    let isNow: Bool
    let timeZone: TimeZone?
    var fontScale: CGFloat = 1.0
    var columnWidth: CGFloat = 60
    
    private var fogScore: FogScore {
        FogCalculator.calculate(from: forecast)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Time header
            Text(DateFormatters.formatTime(forecast.time, in: timeZone))
                .font(.system(size: 12 * fontScale, weight: isNow ? .bold : .medium))
                .foregroundStyle(timeTextColor)
                .frame(height: 28 * fontScale)
            
            // Cloud cover with astronomy-friendly coloring
            Text("\(forecast.cloudCover)%")
                .font(.system(size: 13 * fontScale, weight: .semibold))
                .foregroundStyle(cloudTextColor)
                .frame(height: 20 * fontScale)
                .frame(maxWidth: .infinity)
                .background(cloudBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Temperature
            Text(unitConverter.formatTemperature(forecast.temperature))
                .font(.system(size: 13 * fontScale, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .frame(height: 20 * fontScale)
            
            // Humidity
            Text("\(forecast.humidity)%")
                .font(.system(size: 13 * fontScale, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .frame(height: 20 * fontScale)
            
            // Wind speed
            Text(unitConverter.formatWindSpeed(forecast.windSpeed))
                .font(.system(size: 12 * fontScale, weight: .medium))
                .foregroundStyle(palette.primaryText)
                .frame(height: 20 * fontScale)
            
            // Wind direction
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10 * fontScale))
                    .rotationEffect(.degrees(Double(forecast.windDirection)))
                Text("\(forecast.windDirection)")
                    .font(.system(size: 11 * fontScale))
            }
            .foregroundStyle(lowEmphasisTextColor)
            .frame(height: 20 * fontScale)
            
            // Fog risk
            if fogScore.score > 0 {
                Text("\(fogScore.score)%")
                    .font(.system(size: 13 * fontScale, weight: .semibold))
                    .foregroundStyle(fogColor)
                    .frame(height: 20 * fontScale)
                    .frame(maxWidth: .infinity)
                    .background(fogBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text("—")
                    .font(.system(size: 13 * fontScale))
                    .foregroundStyle(lowEmphasisTextColor)
                    .frame(height: 20 * fontScale)
            }

            // Visibility
            if let visibility = forecast.visibility {
                Text(unitConverter.formatShortVisibility(visibility))
                    .font(.system(size: 13 * fontScale, weight: .medium))
                    .foregroundStyle(visibilityColor(for: visibility))
                    .frame(height: 20 * fontScale)
            } else {
                Text("—")
                    .font(.system(size: 13 * fontScale))
                    .foregroundStyle(lowEmphasisTextColor)
                    .frame(height: 20 * fontScale)
            }
        }
        .frame(width: columnWidth)
        .padding(.horizontal, 4 * fontScale)
        .background(currentColumnBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isNow && palette.appearance == .field {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(palette.border, lineWidth: 1)
            }
        }
    }

    private var timeTextColor: Color {
        if palette.appearance == .field {
            return isNow ? palette.selectedControlText : palette.secondaryText
        }
        return isNow ? .accentColor : .primary
    }

    private var lowEmphasisTextColor: Color {
        palette.appearance == .field ? palette.tertiaryText : .secondary
    }

    private var currentColumnBackground: Color {
        guard isNow else { return .clear }
        return palette.appearance == .field
            ? palette.selectedControlBackground
            : Color.accentColor.opacity(0.08)
    }
    
    // Astronomy-friendly: Dark blue = good (clear), lighter = bad (cloudy)
    private var cloudBackgroundColor: Color {
        if palette.appearance == .field { return palette.subduedFill }
        return ConditionColorPalette.astronomyRiskBackground(for: forecast.cloudCover)
    }
    
    // Text color that contrasts with the background
    private var cloudTextColor: Color {
        if palette.appearance == .field { return palette.primaryText }
        return ConditionColorPalette.astronomyRiskText(for: forecast.cloudCover)
    }
    
    // Fog background: similar gradient to clouds (dark = low fog risk, light = high fog risk)
    private var fogBackgroundColor: Color {
        if palette.appearance == .field { return palette.subduedFill }
        return ConditionColorPalette.astronomyRiskBackground(for: fogScore.score)
    }
    
    // Fog color: for text contrast (dark background -> white, light background -> black)
    private var fogColor: Color {
        if palette.appearance == .field { return palette.primaryText }
        return ConditionColorPalette.astronomyRiskText(for: fogScore.score)
    }
    
    // Visibility color: green for good (>10km), yellow for moderate (5-10km), orange/red for poor
    private func visibilityColor(for meters: Double) -> Color {
        switch meters {
        case 0..<1000:
            return palette.statusColor(.negative)
        case 1000..<5000:
            return palette.statusColor(.caution)
        case 5000..<10000:
            return palette.statusColor(.informational)
        default:
            return palette.statusColor(.positive)
        }
    }
}

#Preview {
    let calendar = Calendar(identifier: .gregorian)
    let sampleForecasts = (0..<12).map { hour in
        HourlyForecast(
            time: calendar.date(byAdding: .hour, value: hour, to: Date()) ?? Date().addingTimeInterval(Double(hour) * 3600),
            cloudCover: Int.random(in: 0...100),
            humidity: Int.random(in: 40...90),
            windSpeed: Double.random(in: 5...25),
            windDirection: Int.random(in: 0...360),
            temperature: Double.random(in: 10...20),
            dewPoint: 10.0,
            visibility: 10000,
            lowCloudCover: 20
        )
    }
    
    HourlyForecastView(
        forecasts: sampleForecasts,
        unitConverter: AstroUnitConverter(unitSystem: .metric),
        timeZone: nil
    )
    .padding()
}

#Preview("Hourly Forecast Field Mode") {
    let calendar = Calendar(identifier: .gregorian)
    let sampleForecasts = (0..<12).map { hour in
        HourlyForecast(
            time: calendar.date(byAdding: .hour, value: hour, to: Date()) ?? Date(),
            cloudCover: (hour * 9) % 100,
            humidity: 45 + hour * 3,
            windSpeed: 5 + Double(hour),
            windDirection: hour * 30,
            temperature: 12,
            dewPoint: 8,
            visibility: 10_000,
            lowCloudCover: 20
        )
    }

    HourlyForecastView(
        forecasts: sampleForecasts,
        unitConverter: AstroUnitConverter(unitSystem: .metric),
        timeZone: nil
    )
    .padding()
    .appAppearance(fieldModeEnabled: true)
}
