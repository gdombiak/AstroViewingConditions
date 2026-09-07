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
        case "weather.decode":
            return try weatherDecode(document)
        case "iss.decode":
            return try issDecode(document)
        case "location.grid":
            return try locationGrid(document)
        case "targets.requirements", "catalog.solar_system", "targets.moon_sensitivity":
            do {
                return try TargetMetadataContract.evaluate(capability, input: injected(document))
            } catch let error as TargetMetadataInputError {
                throw EvalValidationError(code: "validation", message: error.message)
            }
        case "observing_window.select":
            do {
                return try ObservingWindowContract.evaluate(injected(document))
            } catch let error as ObservingWindowInputError {
                throw EvalValidationError(code: "validation", message: error.message)
            }
        case "targets.recommend", "equipment.match":
            do {
                let input = try injected(document)
                return try capability == "targets.recommend" ? Phase15Contracts.targets(input) : Phase15Contracts.equipment(input)
            } catch let error as Phase15InputError {
                throw EvalValidationError(code: "validation", message: error.message)
            }
        case "astronomy.sun_events", "astronomy.moon_info", "astronomy.moon_series":
            guard Set(document.keys).isSubset(of: ["capability", "injected"]),
                  document["capability"] == nil || document["capability"] as? String == capability else {
                throw EvalValidationError(code: "validation", message: "invalid astronomy envelope")
            }
            do {
                return try LiveAstronomy.evaluate(capability, input: injected(document))
            } catch let error as AstronomyInputError {
                throw EvalValidationError(code: "validation", message: error.message)
            }
        case "astronomy.horizontal_position", "targets.deep_sky_windows":
            do {
                let catalog = capability == "targets.deep_sky_windows"
                    ? try DeepSkyCatalog.loadResolved()
                    : []
                return try DeepSkyObservationContract.evaluate(
                    capability,
                    input: try injected(document),
                    catalog: catalog
                )
            } catch let error as DeepSkyObservationInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            } catch let error as DeepSkyCatalogError {
                throw EvalValidationError(code: "engine_failure", message: error.message)
            }
        case "astronomy.moon_observation":
            guard Set(document.keys).isSubset(of: ["capability", "injected"]) else {
                throw EvalValidationError(code: "validation", message: "invalid astronomy envelope")
            }
            do {
                return try MoonObservationContract.evaluate(injected(document))
            } catch let error as MoonObservationInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "targets.moon_recommendation":
            do {
                return try MoonRecommendationContract.evaluate(injected(document))
            } catch let error as MoonRecommendationInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "astronomy.planet_observation":
            guard Set(document.keys).isSubset(of: ["capability", "injected"]) else {
                throw EvalValidationError(code: "validation", message: "invalid astronomy envelope")
            }
            do {
                return try PlanetObservationContract.evaluate(injected(document))
            } catch let error as PlanetObservationInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "targets.planet_recommendation":
            do {
                return try PlanetRecommendationContract.evaluate(injected(document))
            } catch let error as PlanetRecommendationInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "targets.compose_recommendations":
            do {
                return try RecommendationCompositionContract.evaluate(injected(document))
            } catch let error as RecommendationCompositionInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "targets.filter_recommendations_by_equipment":
            do {
                return try RecommendationEquipmentFilterContract.evaluate(injected(document))
            } catch let error as RecommendationEquipmentFilterInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "observing_night.resolve_active":
            do {
                return try ObservingNightContract.evaluate(injected(document))
            } catch let error as ObservingNightInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "night_forecast.derive_window":
            do {
                return try NightForecastWindowContract.evaluate(injected(document))
            } catch let error as NightForecastWindowInputError {
                throw EvalValidationError(code: error.code, message: error.message)
            }
        case "location.compare":
            return try locationCompare(document)
        case "catalog.deep_sky":
            return try catalogDeepSky(document)
        default:
            throw EvalValidationError(code: "capability_unknown", message: "unknown capability: \(capability)")
        }
    }

    private static func injected(_ document: [String: Any]) throws -> [String: Any] {
        guard let injected = document["injected"] as? [String: Any] else {
            throw EvalValidationError(code: "validation", message: "input JSON must contain an 'injected' object")
        }
        return try resolveInjectedRef(injected)
    }

    private static func resolveInjectedRef(_ injected: [String: Any]) throws -> [String: Any] {
        guard injected.count == 1, let ref = injected["$ref"] as? String else {
            return injected
        }
        let data = try fixtureRefData(ref)
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw EvalValidationError(code: "validation", message: "malformed JSON in $ref fixture")
        }
        guard let object = raw as? [String: Any] else {
            throw EvalValidationError(code: "validation", message: "injected.$ref must resolve to an object")
        }
        return object
    }

    private static func injectedJSONData(_ document: [String: Any]) throws -> Data {
        guard let injected = document["injected"] as? [String: Any] else {
            throw EvalValidationError(code: "validation", message: "input JSON must contain an 'injected' object")
        }
        if injected.count == 1, let ref = injected["$ref"] as? String {
            return try fixtureRefData(ref)
        }
        guard JSONSerialization.isValidJSONObject(injected) else {
            throw EvalValidationError(code: "validation", message: "injected must be a JSON object")
        }
        return try JSONSerialization.data(withJSONObject: injected)
    }

    private static func fixtureRefData(_ ref: String) throws -> Data {
        let url: URL
        do {
            url = try FixtureRoot.url(ref)
        } catch let error as FixtureRootError {
            throw evalError(from: error)
        }
        return try Data(contentsOf: url)
    }

    private static func evalError(from error: FixtureRootError) -> EvalValidationError {
        switch error {
        case .refEscape:
            return EvalValidationError(code: "ref_escape", message: error.message)
        case .fixtureMissing:
            return EvalValidationError(code: "fixture_missing", message: error.message)
        case .fixturesDirectoryMissing:
            return EvalValidationError(code: "engine_failure", message: error.message)
        }
    }

    private static func locationGrid(_ document: [String: Any]) throws -> [String: Any] {
        let injected = try injected(document)
        guard let centerObject = injected["center"] as? [String: Any] else {
            throw EvalValidationError(code: "validation", message: "center must be an object")
        }
        guard let latitude = jsonDouble(centerObject["latitude"]) else {
            throw EvalValidationError(code: "validation", message: "center.latitude must be a finite JSON number")
        }
        guard let longitude = jsonDouble(centerObject["longitude"]) else {
            throw EvalValidationError(code: "validation", message: "center.longitude must be a finite JSON number")
        }
        guard let radiusMiles = jsonDouble(injected["radius_miles"]) else {
            throw EvalValidationError(code: "validation", message: "radius_miles is required")
        }
        guard let spacingMiles = jsonDouble(injected["spacing_miles"]) else {
            throw EvalValidationError(code: "validation", message: "spacing_miles is required")
        }
        if GeographicGridGenerator.exceedsContractPointCap(
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles
        ) {
            throw EvalValidationError(
                code: "grid_cap",
                message: "grid exceeds the 1.0 cap (50 mi radius / 3 mi spacing)"
            )
        }
        let samples = GeographicGridGenerator.generateContractGrid(
            around: Coordinate(latitude: latitude, longitude: longitude),
            radiusMiles: radiusMiles,
            spacingMiles: spacingMiles
        )
        return [
            "points": samples.map { sample -> [String: Any] in
                [
                    "north_step": sample.northStep as Any? ?? NSNull(),
                    "east_step": sample.eastStep as Any? ?? NSNull(),
                    "is_center": sample.isCenter,
                    "bearing_deg": sample.bearingDegrees,
                    "distance_miles": sample.distanceMiles,
                    "latitude": sample.latitude,
                    "longitude": sample.longitude,
                ]
            }
        ]
    }

    private static func locationCompare(_ document: [String: Any]) throws -> [String: Any] {
        do {
            return try LocationCompare.evaluate(injected: try injected(document))
        } catch let error as LocationCompareError {
            throw EvalValidationError(code: "validation", message: error.message)
        }
    }

    private static func catalogDeepSky(_ document: [String: Any]) throws -> [String: Any] {
        _ = try injected(document)
        let entries: [DeepSkyCatalogEntry]
        do {
            entries = try DeepSkyCatalog.loadResolved()
        } catch let error as DeepSkyCatalogError {
            throw EvalValidationError(code: "engine_failure", message: error.message)
        }
        return DeepSkyCatalog.contractResult(from: entries)
    }

    private static func weatherDecode(_ document: [String: Any]) throws -> [String: Any] {
        let data = try injectedJSONData(document)
        let response: OpenMeteoResponse
        do {
            response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            throw EvalValidationError(code: "validation", message: "malformed Open-Meteo forecast envelope")
        }
        let forecasts = OpenMeteoForecastDecoder.parseHourlyForecasts(from: response)
        var result: [String: Any] = [
            "hourly": forecasts.map { encodeHour($0) },
            "utc_offset_seconds": response.utcOffsetSeconds,
        ]
        if let timezone = response.timezone {
            result["timezone"] = timezone
        } else {
            result["timezone"] = NSNull()
        }
        return result
    }

    private static func issDecode(_ document: [String: Any]) throws -> [String: Any] {
        let data = try injectedJSONData(document)
        let passes: [ISSPass]
        do {
            passes = try N2YOPassDecoder.decodePasses(from: data)
        } catch {
            throw EvalValidationError(code: "validation", message: "malformed N2YO visualpasses envelope")
        }
        return ["passes": passes.map { encodePass($0) }]
    }

    private static func encodeHour(_ forecast: HourlyForecast) -> [String: Any] {
        var row: [String: Any] = [
            "time": formatUTC(forecast.time),
            "cloud_cover": forecast.cloudCover,
            "humidity": forecast.humidity,
            "wind_speed": forecast.windSpeed,
            "wind_direction": forecast.windDirection,
            "temperature": forecast.temperature,
        ]
        if let dewPoint = forecast.dewPoint {
            row["dew_point"] = dewPoint
        }
        if let visibility = forecast.visibility {
            row["visibility"] = visibility
        }
        if let low = forecast.lowCloudCover {
            row["low_cloud_cover"] = low
        }
        if let mid = forecast.midCloudCover {
            row["mid_cloud_cover"] = mid
        }
        if let high = forecast.highCloudCover {
            row["high_cloud_cover"] = high
        }
        if let wind200 = forecast.windSpeed200hPa {
            row["wind_speed_200hpa"] = wind200
        }
        return row
    }

    private static func encodePass(_ pass: ISSPass) -> [String: Any] {
        var row: [String: Any] = [
            "id": pass.id,
            "rise_time": formatUTC(pass.riseTime),
            "duration": pass.duration,
            "max_elevation": pass.maxElevation,
        ]
        if let maxTime = pass.maxTime {
            row["max_time"] = formatUTC(maxTime)
        }
        if let endTime = pass.endTime {
            row["end_time"] = formatUTC(endTime)
        }
        if let startDirection = pass.startDirection {
            row["start_direction"] = startDirection
        }
        if let maxDirection = pass.maxDirection {
            row["max_direction"] = maxDirection
        }
        if let endDirection = pass.endDirection {
            row["end_direction"] = endDirection
        }
        if let startElevation = pass.startElevation {
            row["start_elevation"] = startElevation
        }
        if let endElevation = pass.endElevation {
            row["end_elevation"] = endElevation
        }
        return row
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
