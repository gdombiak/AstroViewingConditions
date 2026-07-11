import Foundation

public struct SeeingCalculator {
    public static func penalty(
        currentTemperature: Double,
        previousTemperature: Double?,
        windSpeed200hPa: Double?
    ) -> Double? {
        let temperatureComponent = previousTemperature.map {
            component(forTemperatureChange: abs(currentTemperature - $0))
        }
        let upperWindComponent = windSpeed200hPa.map(component(forUpperWind:))
        let components = [temperatureComponent, upperWindComponent].compactMap { $0 }

        guard !components.isEmpty else { return nil }
        return min(max(components.reduce(0, +) / Double(components.count), 0), 2)
    }

    private static func component(forTemperatureChange delta: Double) -> Double {
        switch delta {
        case ...1: return 0
        case ...2: return 0.5
        case ...3: return 1
        case ...5: return 1.5
        default: return 2
        }
    }

    private static func component(forUpperWind windSpeed: Double) -> Double {
        switch windSpeed {
        case ...50: return 0
        case ...100: return 0.5
        case ...150: return 1
        case ...200: return 1.5
        default: return 2
        }
    }
}
