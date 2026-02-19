import SwiftUI

struct HourlyForecastView: View {
    let forecasts: [HourlyForecast]
    let unitConverter: UnitConverter
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
        let calendar = Calendar.current
        
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
                    .foregroundStyle(.secondary)
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
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var cardBackground: some View {
        #if os(iOS)
        return Color(.systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
    
    private func isCurrentHour(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date) &&
        Calendar.current.component(.hour, from: date) == Calendar.current.component(.hour, from: Date())
    }
}

struct MetricLabel: View {
    let icon: String
    let label: String
    let color: Color
    var fontScale: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11 * fontScale, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(height: 20 * fontScale)
    }
}

struct HourlyColumn: View {
    let forecast: HourlyForecast
    let unitConverter: UnitConverter
    let isNow: Bool
    var fontScale: CGFloat = 1.0
    var columnWidth: CGFloat = 60
    
    private var fogScore: FogScore {
        FogCalculator.calculate(from: forecast)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Time header
            Text(DateFormatters.formatTime(forecast.time))
                .font(.system(size: 12 * fontScale, weight: isNow ? .bold : .medium))
                .foregroundStyle(isNow ? Color.accentColor : .primary)
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
                .foregroundStyle(.primary)
                .frame(height: 20 * fontScale)
            
            // Humidity
            Text("\(forecast.humidity)%")
                .font(.system(size: 13 * fontScale, weight: .medium))
                .foregroundStyle(.primary)
                .frame(height: 20 * fontScale)
            
            // Wind speed
            Text(unitConverter.formatWindSpeed(forecast.windSpeed))
                .font(.system(size: 12 * fontScale, weight: .medium))
                .foregroundStyle(.primary)
                .frame(height: 20 * fontScale)
            
            // Wind direction
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10 * fontScale))
                    .rotationEffect(.degrees(Double(forecast.windDirection)))
                Text("\(forecast.windDirection)")
                    .font(.system(size: 11 * fontScale))
            }
            .foregroundStyle(.secondary)
            .frame(height: 20 * fontScale)
            
            // Fog risk
            if fogScore.percentage > 0 {
                Text("\(fogScore.percentage)%")
                    .font(.system(size: 13 * fontScale, weight: .semibold))
                    .foregroundStyle(fogColor)
                    .frame(height: 20 * fontScale)
                    .frame(maxWidth: .infinity)
                    .background(fogBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text("—")
                    .font(.system(size: 13 * fontScale))
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .frame(height: 20 * fontScale)
            }
        }
        .frame(width: columnWidth)
        .padding(.horizontal, 4 * fontScale)
        .background(isNow ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // Astronomy-friendly: Dark blue = good (clear), lighter = bad (cloudy)
    private var cloudBackgroundColor: Color {
        let coverage = Double(forecast.cloudCover) / 100.0
        // Interpolate from dark blue (0%) to light gray/white (100%)
        let red = 10 + (230 * coverage)
        let green = 20 + (220 * coverage)
        let blue = 80 + (155 * coverage)
        return Color(red: red/255, green: green/255, blue: blue/255)
    }
    
    // Text color that contrasts with the background
    private var cloudTextColor: Color {
        forecast.cloudCover > 60 ? .black : .white
    }
    
    // Fog background: similar gradient to clouds (dark = low fog risk, light = high fog risk)
    private var fogBackgroundColor: Color {
        let percentage = Double(fogScore.percentage) / 100.0
        // Interpolate from dark blue (0%) to light gray/white (100%)
        let red = 10 + (230 * percentage)
        let green = 20 + (220 * percentage)
        let blue = 80 + (155 * percentage)
        return Color(red: red/255, green: green/255, blue: blue/255)
    }
    
    // Fog color: for text contrast (dark background → white, light background → black)
    private var fogColor: Color {
        fogScore.percentage > 60 ? .black : .white
    }
    
    // Legacy fog color for compatibility
    private var fogLevelColor: Color {
        switch fogScore.percentage {
        case 0..<30:
            return .green
        case 30..<60:
            return .yellow
        case 60..<80:
            return .orange
        default:
            return .red
        }
    }
    
    // Visibility color: green for good (>10km), yellow for moderate (5-10km), orange/red for poor
    private func visibilityColor(for meters: Double) -> Color {
        switch meters {
        case 0..<1000:
            return .red
        case 1000..<5000:
            return .orange
        case 5000..<10000:
            return .yellow
        default:
            return .green
        }
    }
}

#Preview {
    let sampleForecasts = (0..<12).map { hour in
        HourlyForecast(
            time: Calendar.current.date(byAdding: .hour, value: hour, to: Date())!,
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
        unitConverter: UnitConverter(unitSystem: .metric)
    )
    .padding()
}
