import Foundation

public struct OpenMeteoResponse: Codable {
    public let utcOffsetSeconds: Int
    public let timezone: String?
    public let hourly: HourlyData

    public enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case timezone
        case hourly
    }

    public init(utcOffsetSeconds: Int, timezone: String? = nil, hourly: HourlyData) {
        self.utcOffsetSeconds = utcOffsetSeconds
        self.timezone = timezone
        self.hourly = hourly
    }
}

public struct HourlyData: Codable {
    public let time: [String]
    public let cloudcover: [Int]
    public let cloudcoverLow: [Int]?
    public let midCloudCover: [Int]?
    public let highCloudCover: [Int]?
    public let relativehumidity2M: [Int]
    public let windspeed10M: [Double]
    public let winddirection10M: [Int]
    public let temperature2M: [Double]
    public let dewpoint2M: [Double]?
    public let precipitation: [Double]?
    public let visibility: [Double]?
    public let windSpeed200hPa: [Double]?

    public enum CodingKeys: String, CodingKey {
        case time
        case cloudcover
        case cloudcoverLow = "cloudcover_low"
        case midCloudCover = "cloud_cover_mid"
        case highCloudCover = "cloud_cover_high"
        case relativehumidity2M = "relativehumidity_2m"
        case windspeed10M = "windspeed_10m"
        case winddirection10M = "winddirection_10m"
        case temperature2M = "temperature_2m"
        case dewpoint2M = "dewpoint_2m"
        case precipitation
        case visibility
        case windSpeed200hPa = "wind_speed_200hPa"
    }

    public init(
        time: [String],
        cloudcover: [Int],
        cloudcoverLow: [Int]?,
        midCloudCover: [Int]? = nil,
        highCloudCover: [Int]? = nil,
        relativehumidity2M: [Int],
        windspeed10M: [Double],
        winddirection10M: [Int],
        temperature2M: [Double],
        dewpoint2M: [Double]?,
        precipitation: [Double]?,
        visibility: [Double]?,
        windSpeed200hPa: [Double]? = nil
    ) {
        self.time = time
        self.cloudcover = cloudcover
        self.cloudcoverLow = cloudcoverLow
        self.midCloudCover = midCloudCover
        self.highCloudCover = highCloudCover
        self.relativehumidity2M = relativehumidity2M
        self.windspeed10M = windspeed10M
        self.winddirection10M = winddirection10M
        self.temperature2M = temperature2M
        self.dewpoint2M = dewpoint2M
        self.precipitation = precipitation
        self.visibility = visibility
        self.windSpeed200hPa = windSpeed200hPa
    }
}

public enum OpenMeteoForecastDecoder: Sendable {
    public static func parseHourlyForecasts(from response: OpenMeteoResponse) -> [HourlyForecast] {
        let hourly = response.hourly
        let timeZone = response.timezone
            .flatMap(TimeZone.init(identifier:))
            ?? TimeZone(secondsFromGMT: response.utcOffsetSeconds)
            ?? TimeZone(secondsFromGMT: 0)
            ?? TimeZone.current
        let formatter = DateFormatter.openMeteoLocalDateFormatter(timeZone: timeZone)
        var forecasts: [HourlyForecast] = []

        for index in hourly.time.indices {
            guard let date = formatter.date(from: hourly.time[index]) else {
                continue
            }

            let forecast = HourlyForecast(
                time: date,
                cloudCover: hourly.cloudcover[safe: index] ?? 0,
                humidity: hourly.relativehumidity2M[safe: index] ?? 0,
                windSpeed: hourly.windspeed10M[safe: index] ?? 0,
                windDirection: hourly.winddirection10M[safe: index] ?? 0,
                temperature: hourly.temperature2M[safe: index] ?? 0,
                dewPoint: hourly.dewpoint2M?[safe: index],
                visibility: hourly.visibility?[safe: index],
                lowCloudCover: hourly.cloudcoverLow?[safe: index],
                midCloudCover: hourly.midCloudCover?[safe: index],
                highCloudCover: hourly.highCloudCover?[safe: index],
                windSpeed200hPa: hourly.windSpeed200hPa?[safe: index]
            )
            forecasts.append(forecast)
        }

        return forecasts
    }
}

extension Array {
    public subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension DateFormatter {
    public static func openMeteoLocalDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timeZone
        return formatter
    }
}
