import SharedCode
import SwiftUI

struct HourlyForecastView: View {
    let forecasts: [HourlyForecast]
    let unitConverter: AstroUnitConverter
    let timeZone: TimeZone?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var compactColumnWidth: CGFloat = 60
    @ScaledMetric(relativeTo: .subheadline) private var regularColumnWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .footnote) private var accessibilityCompactColumnWidth: CGFloat = 86
    @ScaledMetric(relativeTo: .footnote) private var accessibilityRegularColumnWidth: CGFloat = 104
    @ScaledMetric(relativeTo: .caption) private var compactLabelColumnWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .caption) private var regularLabelColumnWidth: CGFloat = 90
    @ScaledMetric(relativeTo: .footnote) private var headerHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var columnPadding: CGFloat = 4
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var columnWidth: CGFloat {
        if dynamicTypeSize.requiresExpandedCompactLayout {
            return isIPad ? accessibilityRegularColumnWidth : accessibilityCompactColumnWidth
        }
        return isIPad ? regularColumnWidth : compactColumnWidth
    }
    
    private var labelColumnWidth: CGFloat {
        isIPad ? regularLabelColumnWidth : compactLabelColumnWidth
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
                            .frame(height: headerHeight)
                        MetricLabel(icon: "cloud.fill", label: "Cloud", color: .blue, rowHeight: rowHeight)
                        MetricLabel(icon: "thermometer", label: "Temp", color: .orange, rowHeight: rowHeight)
                        MetricLabel(icon: "humidity.fill", label: "Humidity", color: .cyan, rowHeight: rowHeight)
                        MetricLabel(icon: "wind", label: "Wind", color: .gray, rowHeight: rowHeight)
                        MetricLabel(icon: "arrow.up", label: "Dir", color: .gray, rowHeight: rowHeight)
                        MetricLabel(icon: "cloud.fog.fill", label: "Fog", color: .gray, rowHeight: rowHeight)
                        MetricLabel(icon: "eye", label: "Visibility", color: .gray, rowHeight: rowHeight)
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
                                    columnWidth: columnWidth,
                                    headerHeight: headerHeight,
                                    rowHeight: rowHeight,
                                    columnPadding: columnPadding
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
    let rowHeight: CGFloat
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(palette.appearance == .field ? palette.accent : color)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.appearance == .field ? palette.secondaryText : .primary)
        }
        .frame(height: rowHeight)
    }
}

struct HourlyColumn: View {
    @Environment(\.appPalette) private var palette
    let forecast: HourlyForecast
    let unitConverter: AstroUnitConverter
    let isNow: Bool
    let timeZone: TimeZone?
    let columnWidth: CGFloat
    let headerHeight: CGFloat
    let rowHeight: CGFloat
    let columnPadding: CGFloat
    
    private var fogScore: FogScore {
        FogCalculator.calculate(from: forecast)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Time header
            Text(DateFormatters.formatTime(forecast.time, in: timeZone))
                .font(.footnote.weight(isNow ? .bold : .medium))
                .foregroundStyle(timeTextColor)
                .frame(height: headerHeight)
            
            // Cloud cover with astronomy-friendly coloring
            Text("\(forecast.cloudCover)%")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cloudTextColor)
                .frame(height: rowHeight)
                .frame(maxWidth: .infinity)
                .background(cloudBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Temperature
            Text(unitConverter.formatTemperature(forecast.temperature))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.primaryText)
                .frame(height: rowHeight)
            
            // Humidity
            Text("\(forecast.humidity)%")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.primaryText)
                .frame(height: rowHeight)
            
            // Wind speed
            Text(unitConverter.formatWindSpeed(forecast.windSpeed))
                .font(.footnote.weight(.medium))
                .foregroundStyle(palette.primaryText)
                .frame(height: rowHeight)
            
            // Wind direction
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.footnote)
                    .rotationEffect(.degrees(Double(forecast.windDirection)))
                Text("\(forecast.windDirection)")
                    .font(.footnote)
            }
            .foregroundStyle(lowEmphasisTextColor)
            .frame(height: rowHeight)
            
            // Fog risk
            if fogScore.score > 0 {
                Text("\(fogScore.score)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(fogColor)
                    .frame(height: rowHeight)
                    .frame(maxWidth: .infinity)
                    .background(fogBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(lowEmphasisTextColor)
                    .frame(height: rowHeight)
            }

            // Visibility
            if let visibility = forecast.visibility {
                Text(unitConverter.formatShortVisibility(visibility))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(visibilityColor(for: visibility))
                    .frame(height: rowHeight)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(lowEmphasisTextColor)
                    .frame(height: rowHeight)
            }
        }
        .frame(width: columnWidth)
        .padding(.horizontal, columnPadding)
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
