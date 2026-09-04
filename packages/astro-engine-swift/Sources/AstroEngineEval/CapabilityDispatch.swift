import Foundation
import AstroEngine

enum CapabilityDispatch {
    static func run(capability: String, document: [String: Any]) throws -> [String: Any] {
        if let declared = document["capability"] as? String, declared != capability {
            throw EvalValidationError(
                code: "validation",
                message: "input capability does not match the invoked capability-id"
            )
        }

        switch capability {
        case "observing_quality.assess":
            return try observingQuality(document)
        case "night_conditions.analyze":
            return try nightConditionsAnalyze(document)
        case "night_conditions.score":
            return try nightConditionsScore(document)
        case "fog.score":
            return try fogScore(document)
        case "seeing.penalty":
            return try seeingPenalty(document)
        case "transparency.penalty":
            return try transparencyPenalty(document)
        default:
            throw EvalValidationError(code: "capability_unknown", message: "unknown capability: \(capability)")
        }
    }

    private static func injected(_ document: [String: Any]) throws -> [String: Any] {
        guard let injected = document["injected"] as? [String: Any] else {
            throw EvalValidationError(code: "validation", message: "input JSON must contain an 'injected' object")
        }
        return injected
    }

    private static func observingQuality(_ document: [String: Any]) throws -> [String: Any] {
        let injected = try injected(document)
        guard let night = jsonInt(injected["night_conditions_score"]) else {
            throw EvalValidationError(
                code: "validation",
                message: "injected.night_conditions_score is required"
            )
        }
        let brightness: Double?
        if injected["modeled_zenith_sky_brightness"] == nil || injected["modeled_zenith_sky_brightness"] is NSNull {
            brightness = nil
        } else if let value = jsonDouble(injected["modeled_zenith_sky_brightness"]) {
            brightness = value
        } else {
            throw EvalValidationError(
                code: "validation",
                message: "modeled_zenith_sky_brightness must be a finite JSON number or null"
            )
        }
        let assessment = ObservingQualityCalculator.assess(
            nightConditionsScore: night,
            modeledZenithSkyBrightness: brightness
        )
        var result: [String: Any] = [
            "score": assessment.score,
            "night_conditions_score": assessment.nightConditionsScore,
        ]
        if let lightPollution = assessment.lightPollution {
            result["light_pollution"] = [
                "modeled_zenith_sky_brightness": lightPollution.modeledZenithSkyBrightness,
                "base_penalty": lightPollution.basePenalty,
                "applied_penalty": lightPollution.appliedPenalty,
            ]
        } else {
            result["light_pollution"] = NSNull()
        }
        return result
    }

    private static func nightConditionsAnalyze(_ document: [String: Any]) throws -> [String: Any] {
        try NightConditionsEnvelope.requireClockAndTimeZone(document)
        let injected = try injected(document)
        guard let windowObject = injected["night_window"] as? [String: Any],
              let start = jsonDate(windowObject["start"]),
              let end = jsonDate(windowObject["end"]) else {
            throw EvalValidationError(code: "validation", message: "injected.night_window.start/end are required")
        }
        let forecasts = try jsonForecasts(injected["forecasts"])
        let moonSeries = try jsonMoonSeries(injected["moon_series"])
        let assessment = try NightQualityAnalyzer.analyzeNight(
            forecasts: forecasts,
            nightWindow: NightWindow(start: start, end: end),
            moonSeries: moonSeries
        )
        return encodeNightAssessment(assessment)
    }

    private static func nightConditionsScore(_ document: [String: Any]) throws -> [String: Any] {
        let injected = try injected(document)
        guard let ratingRaw = injected["rating"] as? String,
              let rating = NightQualityAssessment.Rating(rawValue: ratingRaw) else {
            throw EvalValidationError(code: "validation", message: "injected.rating is required")
        }
        guard let scores = injected["hourly_scores"] as? [Any] else {
            throw EvalValidationError(code: "validation", message: "injected.hourly_scores is required")
        }
        let hourlyScores = try scores.map { value -> Double in
            guard let number = jsonDouble(value) else {
                throw EvalValidationError(code: "validation", message: "hourly_scores must be finite numbers")
            }
            return number
        }
        let ratings = hourlyScores.enumerated().map { index, score in
            NightQualityAssessment.HourlyRating(
                time: Date(timeIntervalSince1970: Double(index)),
                score: score,
                cloudCover: 0,
                fogScore: 0,
                moonIllumination: 0,
                moonAltitude: 0,
                windSpeed: 0
            )
        }
        let assessment = NightQualityAssessment(
            rating: rating,
            summary: "",
            details: NightQualityAssessment.Details(
                cloudCoverScore: 0,
                fogScoreAvg: 0,
                moonIlluminationAvg: 0,
                windSpeedAvg: 0
            ),
            bestWindow: nil,
            hourlyRatings: ratings,
            nightStart: Date(timeIntervalSince1970: 0),
            nightEnd: Date(timeIntervalSince1970: 0)
        )
        return ["score": NightConditionsScoring.publicScore(assessment)]
    }

    private static func fogScore(_ document: [String: Any]) throws -> [String: Any] {
        let injected = try injected(document)
        let forecast = HourlyForecast(
            time: Date(timeIntervalSince1970: 0),
            cloudCover: jsonInt(injected["cloud_cover"]) ?? 0,
            humidity: try requiredInt(injected["humidity"], name: "humidity"),
            windSpeed: try requiredDouble(injected["wind_speed"], name: "wind_speed"),
            windDirection: jsonInt(injected["wind_direction"]) ?? 0,
            temperature: try requiredDouble(injected["temperature"], name: "temperature"),
            dewPoint: optionalDouble(injected["dew_point"]),
            visibility: optionalDouble(injected["visibility"]),
            lowCloudCover: optionalInt(injected["low_cloud_cover"])
        )
        let score = FogCalculator.calculate(from: forecast)
        return [
            "score": score.score,
            "factors": score.factors.map(\.contractID),
        ]
    }

    private static func seeingPenalty(_ document: [String: Any]) throws -> [String: Any] {
        let injected = try injected(document)
        let penalty = SeeingCalculator.penalty(
            currentTemperature: try requiredDouble(injected["current_temperature"], name: "current_temperature"),
            previousTemperature: optionalDouble(injected["previous_temperature"]),
            windSpeed200hPa: optionalDouble(injected["wind_speed_200hpa"])
        )
        return ["penalty": penalty as Any? ?? NSNull()]
    }

    private static func transparencyPenalty(_ document: [String: Any]) throws -> [String: Any] {
        let injected = try injected(document)
        let penalty = TransparencyCalculator.penalty(
            totalCloudCover: try requiredInt(injected["total_cloud_cover"], name: "total_cloud_cover"),
            lowCloudCover: optionalInt(injected["low_cloud_cover"]),
            midCloudCover: optionalInt(injected["mid_cloud_cover"]),
            highCloudCover: optionalInt(injected["high_cloud_cover"]),
            visibilityMeters: optionalDouble(injected["visibility_meters"])
        )
        return ["penalty": penalty as Any? ?? NSNull()]
    }

    private static func encodeNightAssessment(_ assessment: NightQualityAssessment) -> [String: Any] {
        var details: [String: Any] = [
            "cloud_cover_score": assessment.details.cloudCoverScore,
            "fog_score_avg": assessment.details.fogScoreAvg,
            "moon_illumination_avg": assessment.details.moonIlluminationAvg,
            "wind_speed_avg": assessment.details.windSpeedAvg,
        ]
        if let seeing = assessment.details.seeingScoreAvg {
            details["seeing_score_avg"] = seeing
        }
        if let transparency = assessment.details.transparencyScoreAvg {
            details["transparency_score_avg"] = transparency
        }

        let hours: [[String: Any]] = assessment.hourlyRatings.map { rating in
            var hour: [String: Any] = [
                "time": formatUTC(rating.time),
                "score": rating.score,
                "cloud_cover": rating.cloudCover,
                "fog_score": rating.fogScore,
                "moon_illumination": rating.moonIllumination,
                "moon_altitude": rating.moonAltitude,
                "wind_speed": rating.windSpeed,
            ]
            if let seeing = rating.seeingScore {
                hour["seeing_score"] = seeing
            }
            if let transparency = rating.transparencyScore {
                hour["transparency_score"] = transparency
            }
            return hour
        }

        return [
            "rating": assessment.rating.rawValue,
            "details": details,
            "hourly_ratings": hours,
            "night_start": formatUTC(assessment.nightStart),
            "night_end": formatUTC(assessment.nightEnd),
            "trend": assessment.trend.rawValue,
            "first_half_score": assessment.firstHalfScore as Any? ?? NSNull(),
            "second_half_score": assessment.secondHalfScore as Any? ?? NSNull(),
            "public_score": NightConditionsScoring.publicScore(assessment),
        ]
    }

    private static func jsonForecasts(_ value: Any?) throws -> [HourlyForecast] {
        guard let rows = value as? [Any] else {
            throw EvalValidationError(code: "validation", message: "injected.forecasts must be an array")
        }
        return try rows.map { row in
            guard let object = row as? [String: Any], let time = jsonDate(object["time"]) else {
                throw EvalValidationError(code: "validation", message: "forecast time is required")
            }
            return HourlyForecast(
                time: time,
                cloudCover: jsonInt(object["cloud_cover"]) ?? 0,
                humidity: jsonInt(object["humidity"]) ?? 0,
                windSpeed: jsonDouble(object["wind_speed"]) ?? 0,
                windDirection: jsonInt(object["wind_direction"]) ?? 0,
                temperature: jsonDouble(object["temperature"]) ?? 0,
                dewPoint: optionalDouble(object["dew_point"]),
                visibility: optionalDouble(object["visibility"]),
                lowCloudCover: optionalInt(object["low_cloud_cover"]),
                midCloudCover: optionalInt(object["mid_cloud_cover"]),
                highCloudCover: optionalInt(object["high_cloud_cover"]),
                windSpeed200hPa: optionalDouble(object["wind_speed_200hpa"])
            )
        }
    }

    private static func jsonMoonSeries(_ value: Any?) throws -> [MoonSample] {
        guard let rows = value as? [Any] else {
            throw EvalValidationError(code: "validation", message: "injected.moon_series must be an array")
        }
        return try rows.map { row in
            guard let object = row as? [String: Any],
                  let time = jsonDate(object["time"]),
                  let altitude = jsonDouble(object["altitude_deg"]),
                  let illumination = jsonInt(object["illumination_pct"]) else {
                throw EvalValidationError(code: "validation", message: "moon_series entries need time, altitude_deg, illumination_pct")
            }
            return MoonSample(time: time, altitudeDegrees: altitude, illuminationPercent: illumination)
        }
    }
}

private func makeUTCFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}

private func formatUTC(_ date: Date) -> String {
    makeUTCFormatter().string(from: date)
}

private func jsonDate(_ value: Any?) -> Date? {
    NightConditionsEnvelope.parseUTCInstant(value)
}

private func jsonInt(_ value: Any?) -> Int? {
    guard let number = jsonDouble(value), number.rounded(.towardZero) == number else { return nil }
    let asInt = Int(number)
    guard Double(asInt) == number else { return nil }
    return asInt
}

private func jsonDouble(_ value: Any?) -> Double? {
    if value is NSNull { return nil }
    if let number = value as? NSNumber {
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        let doubleValue = number.doubleValue
        return doubleValue.isFinite ? doubleValue : nil
    }
    if let number = value as? Double { return number.isFinite ? number : nil }
    if let number = value as? Int { return Double(number) }
    return nil
}

private func optionalDouble(_ value: Any?) -> Double? {
    if value == nil || value is NSNull { return nil }
    return jsonDouble(value)
}

private func optionalInt(_ value: Any?) -> Int? {
    if value == nil || value is NSNull { return nil }
    return jsonInt(value)
}

private func requiredDouble(_ value: Any?, name: String) throws -> Double {
    guard let number = jsonDouble(value) else {
        throw EvalValidationError(code: "validation", message: "\(name) is required")
    }
    return number
}

private func requiredInt(_ value: Any?, name: String) throws -> Int {
    guard let number = jsonInt(value) else {
        throw EvalValidationError(code: "validation", message: "\(name) is required")
    }
    return number
}
