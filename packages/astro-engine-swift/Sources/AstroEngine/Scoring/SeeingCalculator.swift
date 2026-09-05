import Foundation

public struct SeeingCalculator {
    public static func penalty(
        currentTemperature: Double,
        previousTemperature: Double?,
        windSpeed200hPa: Double?
    ) -> Double? {
        penalty(
            currentTemperature: currentTemperature,
            previousTemperature: previousTemperature,
            windSpeed200hPa: windSpeed200hPa,
            calibration: EngineCalibration.current.seeing
        )
    }

    public static func penalty(
        currentTemperature: Double,
        previousTemperature: Double?,
        windSpeed200hPa: Double?,
        calibration: SeeingCalibration
    ) -> Double? {
        let temperatureComponent = previousTemperature.map {
            CalibrationTables.score(
                for: abs(currentTemperature - $0),
                in: calibration.temperatureDeltaCelsius
            )
        }
        let upperWindComponent = windSpeed200hPa.map {
            CalibrationTables.score(for: $0, in: calibration.upperWind200hpa)
        }
        let components = [temperatureComponent, upperWindComponent].compactMap { $0 }

        guard !components.isEmpty else { return nil }
        return min(
            max(components.reduce(0, +) / Double(components.count), calibration.penaltyMin),
            calibration.penaltyMax
        )
    }
}
