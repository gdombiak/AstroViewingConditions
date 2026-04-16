import SwiftUI
import SharedCode

struct WatchCurrentConditionsCard: View {
    let forecast: HourlyForecast

    private var unitConverter: AstroUnitConverter {
        AstroUnitConverter(unitSystem: UnitSystemStorage.loadSelectedUnitSystem())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current Conditions")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                VStack {
                    Image(systemName: "cloud")
                    Text("\(forecast.cloudCover)%")
                        .font(.caption)
                }

                VStack {
                    Image(systemName: "wind")
                    Text(unitConverter.formatWindSpeed(forecast.windSpeed))
                        .font(.caption)
                }

                VStack {
                    Image(systemName: "humidity")
                    Text("\(forecast.humidity)%")
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
