import SwiftUI

struct CurrentConditionsCard: View {
    let forecast: HourlyForecast?
    let unitConverter: UnitConverter
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Conditions", systemImage: "eye.fill")
                    .font(.headline)
                Spacer()
                if let time = forecast?.time {
                    Text(DateFormatters.formatTime(time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let forecast = forecast {
                HStack(spacing: 16) {
                    // Cloud Cover
                    ConditionItem(
                        icon: "cloud.fill",
                        iconColor: cloudIconColor(for: forecast.cloudCover),
                        value: "\(forecast.cloudCover)%",
                        label: "Cloud"
                    )
                    
                    // Temperature
                    ConditionItem(
                        icon: "thermometer",
                        iconColor: .orange,
                        value: unitConverter.formatTemperature(forecast.temperature),
                        label: "Temp"
                    )
                    
                    // Humidity
                    ConditionItem(
                        icon: "humidity.fill",
                        iconColor: .blue,
                        value: "\(forecast.humidity)%",
                        label: "Humidity"
                    )
                    
                    // Wind
                    ConditionItem(
                        icon: "wind",
                        iconColor: .gray,
                        value: unitConverter.formatWindSpeed(forecast.windSpeed),
                        label: "Wind"
                    )
                }
                
                // Visibility & Fog
                HStack(spacing: 20) {
                    if let visibility = forecast.visibility {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .foregroundStyle(.secondary)
                            Text("Visibility:")
                                .font(.subheadline)
                            Text(unitConverter.formatVisibility(visibility))
                                .font(.subheadline)
                                .foregroundStyle(visibilityColor(for: visibility))
                        }
                    }
                    
                    let fogScore = FogCalculator.calculate(from: forecast)
                    if fogScore.percentage > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "cloud.fog.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(fogTextColor(for: fogScore.percentage))
                            Text("\(fogScore.percentage)%")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(fogTextColor(for: fogScore.percentage))
                        }
                        .frame(width: 60, height: 28)
                        .background(fogBackgroundColor(for: fogScore.percentage))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
            } else {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .background(cardBackground(for: forecast?.cloudCover ?? 0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func cardBackground(for cloudCover: Int) -> Color {
        #if os(iOS)
        // Use darker background in light mode when clouds are high (>90%)
        // to provide contrast for the whitish cloud icon
        if colorScheme == .light && cloudCover > 90 {
            return Color(.systemGray5)
        }
        return Color(.systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }
    
    // Cloud background: dark blue (clear) to whitish (cloudy)
    private func cloudBackgroundColor(for percentage: Int) -> Color {
        let coverage = Double(percentage) / 100.0
        let red = 10 + (230 * coverage)
        let green = 20 + (220 * coverage)
        let blue = 80 + (155 * coverage)
        return Color(red: red/255, green: green/255, blue: blue/255)
    }
    
    // Cloud icon color: dark blue (clear) to whitish (cloudy)
    private func cloudIconColor(for percentage: Int) -> Color {
        let coverage = Double(percentage) / 100.0
        let red = 10 + (230 * coverage)
        let green = 20 + (220 * coverage)
        let blue = 80 + (155 * coverage)
        return Color(red: red/255, green: green/255, blue: blue/255)
    }
    
    private func cloudTextColor(for percentage: Int) -> Color {
        percentage > 60 ? .black : .white
    }
    
    // Fog background: same gradient as clouds
    private func fogBackgroundColor(for percentage: Int) -> Color {
        let coverage = Double(percentage) / 100.0
        let red = 10 + (230 * coverage)
        let green = 20 + (220 * coverage)
        let blue = 80 + (155 * coverage)
        return Color(red: red/255, green: green/255, blue: blue/255)
    }
    
    private func fogTextColor(for percentage: Int) -> Color {
        percentage > 60 ? .black : .white
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

struct ConditionItem: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    CurrentConditionsCard(
        forecast: HourlyForecast(
            time: Date(),
            cloudCover: 25,
            humidity: 65,
            windSpeed: 12.5,
            windDirection: 180,
            temperature: 15.5,
            dewPoint: 10.0,
            visibility: 10000,
            lowCloudCover: 20
        ),
        unitConverter: UnitConverter(unitSystem: .metric)
    )
    .padding()
}
