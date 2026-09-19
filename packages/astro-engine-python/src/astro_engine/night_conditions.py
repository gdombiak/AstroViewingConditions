"""night_conditions.analyze and night_conditions.score.

1.0 analyze uses injected night_window + 1:1 moon_series + clock/time_zone.
It does not call SunCalc, NightForecastFilter, or the system clock.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Mapping, Sequence

from astro_engine.contracts import (
    night_quality_calibration,
    seeing_calibration,
    transparency_calibration,
)
from astro_engine.errors import ValidationError
from astro_engine.fog import score_fog
from astro_engine.seeing import seeing_penalty_value
from astro_engine.tables import score_upper_bound
from astro_engine.transparency import transparency_penalty_value
from astro_engine.validate import (
    format_utc_z,
    optional_finite_number,
    optional_int,
    parse_utc_z,
    require_finite_number,
    require_iana_timezone,
    require_int,
    trunc_toward_zero,
)

ANALYZE_CAPABILITY_ID = "night_conditions.analyze"
SCORE_CAPABILITY_ID = "night_conditions.score"

_RATINGS = ("excellent", "good", "fair", "poor")


@dataclass(frozen=True)
class _Hour:
    time: datetime
    cloud_cover: int
    humidity: int
    wind_speed: float
    temperature: float
    dew_point: float | None
    visibility: float | None
    low_cloud_cover: int | None
    mid_cloud_cover: int | None
    high_cloud_cover: int | None
    wind_speed_200hpa: float | None


@dataclass(frozen=True)
class _Moon:
    altitude_deg: float
    illumination_pct: int


def public_night_score(
    rating: Any,
    hourly_scores: Any,
    *,
    calibration: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return `{score}` — the public 0–100 integer."""
    cal = dict(calibration) if calibration is not None else night_quality_calibration()
    return {"score": _public_score_int(rating, hourly_scores, cal["public_score"])}


def analyze_night_conditions(
    document: Mapping[str, Any],
    *,
    fog_cal: Mapping[str, Any] | None = None,
    seeing_cal: Mapping[str, Any] | None = None,
    transparency_cal: Mapping[str, Any] | None = None,
    night_cal: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return the night_conditions.analyze result DTO (not the envelope)."""
    if not isinstance(document, Mapping):
        raise ValidationError("input JSON must be an object")
    if "capability" in document and document["capability"] != ANALYZE_CAPABILITY_ID:
        raise ValidationError("input capability does not match the invoked capability-id")

    parse_utc_z(document.get("clock"), "clock")
    require_iana_timezone(document.get("time_zone"))

    injected = document.get("injected")
    if not isinstance(injected, Mapping):
        raise ValidationError("input JSON must contain an 'injected' object")

    window = injected.get("night_window")
    if not isinstance(window, Mapping):
        raise ValidationError("injected.night_window.start/end are required")
    start = parse_utc_z(window.get("start"), "injected.night_window.start")
    end = parse_utc_z(window.get("end"), "injected.night_window.end")

    forecasts = _parse_forecasts(injected.get("forecasts"))
    moon_by_time = _parse_moon_series(injected.get("moon_series"))

    included = [hour for hour in forecasts if start <= hour.time < end]
    included.sort(key=lambda hour: hour.time)

    night = dict(night_cal) if night_cal is not None else night_quality_calibration()
    fog_calibration = fog_cal
    seeing_resolved = seeing_cal if seeing_cal is not None else seeing_calibration()
    transparency_resolved = (
        transparency_cal if transparency_cal is not None else transparency_calibration()
    )

    if not included:
        return _empty_night(start, end, night)

    hourly_ratings: list[dict[str, Any]] = []
    for index, hour in enumerate(included):
        moon = moon_by_time.get(hour.time)
        if moon is None:
            raise ValidationError(
                f"moon_series missing timestamp {format_utc_z(hour.time)}"
            )
        previous_temp = included[index - 1].temperature if index > 0 else None
        hourly_ratings.append(
            _score_hour(
                hour,
                moon=moon,
                previous_temperature=previous_temp,
                night=night,
                fog_cal=fog_calibration,
                seeing_cal=seeing_resolved,
                transparency_cal=transparency_resolved,
            )
        )

    scores = [float(row["score"]) for row in hourly_ratings]
    raw_average = sum(scores) / float(len(scores))
    avg_cloud = (
        float(sum(int(row["cloud_cover"]) for row in hourly_ratings))
        / float(len(hourly_ratings))
    )
    cloud_floor = night["cloud_floor"]
    if avg_cloud >= float(cloud_floor["cloud_cover_min"]):
        avg_score = max(raw_average, float(cloud_floor["fair_max"]))
    else:
        avg_score = raw_average

    rating = _rating_from_score(avg_score, night["rating_thresholds"])
    fog_scores = [int(row["fog_score"]) for row in hourly_ratings]
    illuminations = [int(row["moon_illumination"]) for row in hourly_ratings]
    wind_speeds = [float(row["wind_speed"]) for row in hourly_ratings]
    seeing_scores = [
        float(row["seeing_score"]) for row in hourly_ratings if "seeing_score" in row
    ]
    transparency_scores = [
        float(row["transparency_score"])
        for row in hourly_ratings
        if "transparency_score" in row
    ]

    details: dict[str, Any] = {
        "cloud_cover_score": avg_cloud,
        "fog_score_avg": float(sum(fog_scores) // len(fog_scores)),
        "moon_illumination_avg": sum(illuminations) // len(illuminations),
        "wind_speed_avg": sum(wind_speeds) / float(len(wind_speeds)),
    }
    if seeing_scores:
        details["seeing_score_avg"] = sum(seeing_scores) / float(len(seeing_scores))
    if transparency_scores:
        details["transparency_score_avg"] = sum(transparency_scores) / float(
            len(transparency_scores)
        )

    trend, first_half, second_half = _trend(scores, night["trend"])
    return {
        "rating": rating,
        "details": details,
        "hourly_ratings": hourly_ratings,
        "night_start": format_utc_z(included[0].time),
        "night_end": format_utc_z(included[-1].time),
        "trend": trend,
        "first_half_score": first_half,
        "second_half_score": second_half,
        "public_score": _public_score_int(rating, scores, night["public_score"]),
    }


def _empty_night(start: datetime, end: datetime, night: Mapping[str, Any]) -> dict[str, Any]:
    rating = "poor"
    return {
        "rating": rating,
        "details": {
            "cloud_cover_score": 0,
            "fog_score_avg": 0,
            "moon_illumination_avg": 0,
            "wind_speed_avg": 0,
        },
        "hourly_ratings": [],
        "night_start": format_utc_z(start),
        "night_end": format_utc_z(end),
        "trend": "stable",
        "first_half_score": None,
        "second_half_score": None,
        "public_score": _public_score_int(rating, [], night["public_score"]),
    }


def _score_hour(
    hour: _Hour,
    *,
    moon: _Moon,
    previous_temperature: float | None,
    night: Mapping[str, Any],
    fog_cal: Mapping[str, Any] | None,
    seeing_cal: Mapping[str, Any],
    transparency_cal: Mapping[str, Any],
) -> dict[str, Any]:
    fog = score_fog(
        {
            "humidity": hour.humidity,
            "temperature": hour.temperature,
            "wind_speed": hour.wind_speed,
            "dew_point": hour.dew_point,
            "visibility": hour.visibility,
            "low_cloud_cover": hour.low_cloud_cover,
        },
        calibration=fog_cal,
    )
    cloud_score = score_upper_bound(
        float(hour.cloud_cover),
        night["cloud_cover_score_table"],
        name="night-quality cloud_cover_score_table",
    )
    seeing = seeing_penalty_value(
        current_temperature=hour.temperature,
        previous_temperature=previous_temperature,
        wind_speed_200hpa=hour.wind_speed_200hpa,
        calibration=seeing_cal,
    )
    has_transparency = (
        hour.low_cloud_cover is not None
        and hour.mid_cloud_cover is not None
        and hour.high_cloud_cover is not None
    )
    transparency = (
        transparency_penalty_value(
            total_cloud_cover=hour.cloud_cover,
            low_cloud_cover=hour.low_cloud_cover,
            mid_cloud_cover=hour.mid_cloud_cover,
            high_cloud_cover=hour.high_cloud_cover,
            visibility_meters=hour.visibility,
            calibration=transparency_cal,
        )
        if has_transparency
        else None
    )
    moon_score = _moon_penalty(moon.illumination_pct, moon.altitude_deg, night)
    wind_score = score_upper_bound(
        hour.wind_speed,
        night["wind_penalty_table"],
        name="night-quality wind_penalty_table",
    )
    fog_penalty = float(fog["score"]) / float(night["fog_penalty_divisor"])
    regimes = night["weight_regimes"]
    if transparency is not None and seeing is not None:
        weights = regimes["transparency_and_seeing"]
        weighted = (
            transparency * _required_weight(weights, "transparency")
            + seeing * _required_weight(weights, "seeing")
            + fog_penalty * float(weights["fog"])
            + moon_score * float(weights["moon"])
            + wind_score * float(weights["wind"])
        )
    elif transparency is not None:
        weights = regimes["transparency_only"]
        weighted = (
            transparency * _required_weight(weights, "transparency")
            + fog_penalty * float(weights["fog"])
            + moon_score * float(weights["moon"])
            + wind_score * float(weights["wind"])
        )
    elif seeing is not None:
        weights = regimes["seeing_only"]
        weighted = (
            cloud_score * _required_weight(weights, "cloud")
            + seeing * _required_weight(weights, "seeing")
            + fog_penalty * float(weights["fog"])
            + moon_score * float(weights["moon"])
            + wind_score * float(weights["wind"])
        )
    else:
        weights = regimes["neither"]
        weighted = (
            cloud_score * _required_weight(weights, "cloud")
            + fog_penalty * float(weights["fog"])
            + moon_score * float(weights["moon"])
            + wind_score * float(weights["wind"])
        )

    cloud_floor = night["cloud_floor"]
    if hour.cloud_cover >= int(cloud_floor["cloud_cover_min"]):
        final_score = max(weighted, float(cloud_floor["fair_max"]))
    else:
        final_score = weighted

    row: dict[str, Any] = {
        "time": format_utc_z(hour.time),
        "score": final_score,
        "cloud_cover": hour.cloud_cover,
        "fog_score": fog["score"],
        "moon_illumination": moon.illumination_pct,
        "moon_altitude": moon.altitude_deg,
        "wind_speed": hour.wind_speed,
    }
    if seeing is not None:
        row["seeing_score"] = seeing
    if transparency is not None:
        row["transparency_score"] = transparency
    return row


def _moon_penalty(illumination: int, altitude: float, night: Mapping[str, Any]) -> float:
    if altitude <= 0:
        return 0.0
    illumination_score = score_upper_bound(
        float(illumination),
        night["moon_illumination_buckets"],
        name="night-quality moon_illumination_buckets",
    )
    altitude_factor = min(max(altitude / 90.0, 0.0), 1.0)
    return illumination_score * (0.5 + 0.5 * altitude_factor)


def _required_weight(weights: Mapping[str, Any], key: str) -> float:
    value = weights.get(key)
    if value is None:
        raise ValidationError(f"night-quality weight_regimes missing {key}")
    return float(value)


def _rating_from_score(avg_score: float, thresholds: Mapping[str, Any]) -> str:
    if avg_score < float(thresholds["excellent_max"]):
        return "excellent"
    if avg_score < float(thresholds["good_max"]):
        return "good"
    if avg_score < float(thresholds["fair_max"]):
        return "fair"
    return "poor"


def _trend(
    scores: Sequence[float], trend_cal: Mapping[str, Any]
) -> tuple[str, float | None, float | None]:
    min_hours = int(trend_cal["min_hours"])
    if len(scores) < min_hours:
        return "stable", 0.0, 0.0
    mid = len(scores) // 2
    first = sum(scores[:mid]) / float(mid)
    second = sum(scores[mid:]) / float(len(scores) - mid)
    diff = second - first
    threshold = float(trend_cal["diff_threshold"])
    if diff > threshold:
        trend = "degrading"
    elif diff < -threshold:
        trend = "improving"
    else:
        trend = "stable"
    return trend, first, second


def _public_score_int(
    rating: Any, hourly_scores: Any, public_cal: Mapping[str, Any]
) -> int:
    if rating not in _RATINGS:
        raise ValidationError("injected.rating is required")
    if not isinstance(hourly_scores, list):
        raise ValidationError("injected.hourly_scores is required")
    scores = [require_finite_number(value, "hourly_scores") for value in hourly_scores]
    bases = {
        "excellent": int(public_cal["excellent_base"]),
        "good": int(public_cal["good_base"]),
        "fair": int(public_cal["fair_base"]),
        "poor": int(public_cal["poor_base"]),
    }
    adjustment = 0
    if scores:
        avg = sum(scores) / float(len(scores))
        adjustment = trunc_toward_zero((1.0 - avg) * float(public_cal["adjustment_scale"]))
    final = bases[rating] + adjustment
    return min(int(public_cal["score_max"]), max(int(public_cal["score_min"]), final))


def _parse_forecasts(value: Any) -> list[_Hour]:
    if not isinstance(value, list):
        raise ValidationError("injected.forecasts must be an array")
    hours: list[_Hour] = []
    for row in value:
        if not isinstance(row, Mapping):
            raise ValidationError("forecast time is required")
        hours.append(
            _Hour(
                time=parse_utc_z(row.get("time"), "forecast time"),
                cloud_cover=require_int(row.get("cloud_cover"), "cloud_cover")
                if "cloud_cover" in row and row.get("cloud_cover") is not None
                else 0,
                humidity=require_int(row.get("humidity"), "humidity")
                if "humidity" in row and row.get("humidity") is not None
                else 0,
                wind_speed=require_finite_number(row.get("wind_speed"), "wind_speed")
                if "wind_speed" in row and row.get("wind_speed") is not None
                else 0.0,
                temperature=require_finite_number(row.get("temperature"), "temperature")
                if "temperature" in row and row.get("temperature") is not None
                else 0.0,
                dew_point=optional_finite_number(row.get("dew_point"), "dew_point"),
                visibility=optional_finite_number(row.get("visibility"), "visibility"),
                low_cloud_cover=optional_int(row.get("low_cloud_cover"), "low_cloud_cover"),
                mid_cloud_cover=optional_int(row.get("mid_cloud_cover"), "mid_cloud_cover"),
                high_cloud_cover=optional_int(row.get("high_cloud_cover"), "high_cloud_cover"),
                wind_speed_200hpa=optional_finite_number(
                    row.get("wind_speed_200hpa"), "wind_speed_200hpa"
                ),
            )
        )
    return hours


def _parse_moon_series(value: Any) -> dict[datetime, _Moon]:
    if not isinstance(value, list):
        raise ValidationError("injected.moon_series must be an array")
    by_time: dict[datetime, _Moon] = {}
    for row in value:
        if not isinstance(row, Mapping):
            raise ValidationError(
                "moon_series entries need time, altitude_deg, illumination_pct"
            )
        time = parse_utc_z(row.get("time"), "moon_series time")
        if time in by_time:
            continue
        by_time[time] = _Moon(
            altitude_deg=require_finite_number(row.get("altitude_deg"), "altitude_deg"),
            illumination_pct=require_int(row.get("illumination_pct"), "illumination_pct"),
        )
    return by_time
