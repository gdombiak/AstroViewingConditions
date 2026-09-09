"""Thin typed adapter over in-process Astro Engine module APIs.

This module converts DTOs only. Acquisition, caching, fallback and composition
remain in ``ConditionsService``.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from pathlib import Path
from typing import Mapping, Sequence

from astro_engine.astronomy import evaluate_astronomy
from astro_engine.cloud_timing import classify_cloud_timing
from astro_engine.contracts import ContractsRootError, engine_semver
from astro_engine.errors import ValidationError
from astro_engine.light_pollution import LightPollutionArtifact, LightPollutionArtifactError
from astro_engine.night_conditions import analyze_night_conditions
from astro_engine.night_forecast import derive_night_forecast_window
from astro_engine.observing_night import resolve_active_observing_night
from astro_engine.observing_quality import ObservingQualityError, assess_observing_quality
from astro_engine.observing_window import select_observing_window
from astro_engine.weather import decode_weather

from astro_host.errors import EngineCallError
from astro_host.models import (
    ActiveNightResolution,
    HourlyRating,
    HourlyWeather,
    Location,
    MoonSample,
    NightAnalysis,
    ObservingQualityFacts,
    SunEventsFacts,
    TimeWindow,
)


class ConditionsEngine:
    """Typed anti-corruption boundary; it contains no host policy."""

    @property
    def semver(self) -> str:
        try:
            return engine_semver()
        except (ContractsRootError, OSError, UnicodeError):
            return "unknown"

    def decode_weather(self, payload: Mapping[str, object]) -> tuple[
        tuple[HourlyWeather, ...], str | None, int
    ]:
        capability = "weather.decode"
        try:
            result = decode_weather(payload)
            rows = tuple(_hourly_weather(row) for row in result["hourly"])
            return rows, result["timezone"], int(result["utc_offset_seconds"])
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def sun_events(
        self,
        location: Location,
        *,
        day: date,
        start: datetime,
        end: datetime,
    ) -> SunEventsFacts:
        capability = "astronomy.sun_events"
        try:
            result = evaluate_astronomy(capability, {
                "latitude": location.latitude,
                "longitude": location.longitude,
                "start": _utc_z(start),
                "end": _utc_z(end),
            })
            return SunEventsFacts(
                day=day,
                sunrise=_optional_instant(result.get("sunrise")),
                sunset=_optional_instant(result.get("sunset")),
                civil_twilight_begin=_optional_instant(result.get("civil_twilight_begin")),
                civil_twilight_end=_optional_instant(result.get("civil_twilight_end")),
                nautical_twilight_begin=_optional_instant(result.get("nautical_twilight_begin")),
                nautical_twilight_end=_optional_instant(result.get("nautical_twilight_end")),
                astronomical_twilight_begin=_optional_instant(
                    result.get("astronomical_twilight_begin")
                ),
                astronomical_twilight_end=_optional_instant(
                    result.get("astronomical_twilight_end")
                ),
            )
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def resolve_active_night(
        self,
        *,
        reference_time: datetime,
        time_zone: str,
        forecast_start_time: datetime | None,
        daily_sun_events: Sequence[SunEventsFacts],
    ) -> ActiveNightResolution:
        capability = "observing_night.resolve_active"
        try:
            result = resolve_active_observing_night({
                "reference_time": _utc_z(reference_time),
                "time_zone": time_zone,
                "forecast_start_time": (
                    None if forecast_start_time is None else _utc_z(forecast_start_time)
                ),
                "daily_sun_events": [
                    {
                        "astronomical_twilight_end": _utc_z_required(
                            row.astronomical_twilight_end
                        ),
                        "astronomical_twilight_begin": _utc_z_required(
                            row.astronomical_twilight_begin
                        ),
                    }
                    for row in daily_sun_events
                ],
                "daily_moon_count": len(daily_sun_events),
            })
            return ActiveNightResolution(
                state=str(result["state"]),
                observing_date=(
                    None if result["observing_date"] is None
                    else date.fromisoformat(result["observing_date"])
                ),
                observing_day_start=_optional_instant(result["observing_day_start"]),
                astronomical_night_start=_optional_instant(
                    result["astronomical_night_start"]
                ),
                astronomical_night_end=_optional_instant(
                    result["astronomical_night_end"]
                ),
                day_index=result["day_index"],
                day_offset=result["day_offset"],
            )
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def derive_window(
        self,
        *,
        observing_time: datetime,
        time_zone: str,
        sun_today: SunEventsFacts,
        sun_tomorrow: SunEventsFacts,
    ) -> TimeWindow:
        capability = "night_forecast.derive_window"
        try:
            result = derive_night_forecast_window({
                "observing_time": _utc_z(observing_time),
                "time_zone": time_zone,
                "astronomical_twilight_end": _utc_z_required(
                    sun_today.astronomical_twilight_end
                ),
                "astronomical_twilight_begin": _utc_z_required(
                    sun_today.astronomical_twilight_begin
                ),
                "tomorrow_astronomical_twilight_begin": _utc_z_required(
                    sun_tomorrow.astronomical_twilight_begin
                ),
            })
            return TimeWindow(
                start=_instant(result["start"]),
                end=_instant(result["end"]),
            )
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def moon_series(
        self, location: Location, times: Sequence[datetime]
    ) -> tuple[MoonSample, ...]:
        capability = "astronomy.moon_series"
        try:
            result = evaluate_astronomy(capability, {
                "latitude": location.latitude,
                "longitude": location.longitude,
                "times": [_utc_z(value) for value in times],
            })
            return tuple(
                MoonSample(
                    time=_instant(row["time"]),
                    altitude_deg=float(row["altitude"]),
                    illumination_pct=int(row["illumination"]),
                )
                for row in result["samples"]
            )
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def analyze_night(
        self,
        *,
        reference_time: datetime,
        time_zone: str,
        window: TimeWindow,
        forecasts: Sequence[HourlyWeather],
        moon_samples: Sequence[MoonSample],
    ) -> NightAnalysis:
        capability = "night_conditions.analyze"
        try:
            result = analyze_night_conditions({
                "clock": _utc_z(reference_time),
                "time_zone": time_zone,
                "injected": {
                    "night_window": {
                        "start": _utc_z(window.start),
                        "end": _utc_z(window.end),
                    },
                    "forecasts": [_weather_mapping(row) for row in forecasts],
                    "moon_series": [
                        {
                            "time": _utc_z(row.time),
                            "altitude_deg": row.altitude_deg,
                            "illumination_pct": row.illumination_pct,
                        }
                        for row in moon_samples
                    ],
                },
            })
            return NightAnalysis(
                rating=str(result["rating"]),
                public_score=int(result["public_score"]),
                details=dict(result["details"]),
                hourly_ratings=tuple(_hourly_rating(row) for row in result["hourly_ratings"]),
                night_start=_instant(result["night_start"]),
                night_end=_instant(result["night_end"]),
                trend=str(result["trend"]),
                first_half_score=_optional_float(result["first_half_score"]),
                second_half_score=_optional_float(result["second_half_score"]),
            )
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def select_best_window(self, ratings: Sequence[HourlyRating]) -> TimeWindow | None:
        capability = "observing_window.select"
        try:
            result = select_observing_window({
                "hourly_ratings": [
                    {"time": _utc_z(row.time), "score": row.score} for row in ratings
                ]
            })
            raw = result["best_window"]
            if raw is None:
                return None
            return TimeWindow(start=_instant(raw["start"]), end=_instant(raw["end"]))
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def classify_cloud_timing(self, ratings: Sequence[HourlyRating]) -> str:
        capability = "night_conditions.classify_cloud_timing"
        try:
            result = classify_cloud_timing({
                "hourly_ratings": [
                    {
                        "time": _utc_z(row.time),
                        "score": row.score,
                        "cloud_cover": row.cloud_cover,
                    }
                    for row in ratings
                ]
            })
            return str(result["cloud_timing"])
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def lookup_brightness(self, atlas_path: Path, location: Location) -> float | None:
        capability = "light_pollution.lookup"
        try:
            artifact = LightPollutionArtifact.from_bytes(atlas_path.read_bytes())
            return artifact.lookup(location.latitude, location.longitude)
        except Exception as exc:
            raise _engine_error(capability, exc) from exc

    def assess_observing_quality(
        self, night_conditions_score: int, brightness: float | None
    ) -> ObservingQualityFacts:
        capability = "observing_quality.assess"
        try:
            result = assess_observing_quality(night_conditions_score, brightness)
            light = result["light_pollution"]
            return ObservingQualityFacts(
                score=int(result["score"]),
                night_conditions_score=int(result["night_conditions_score"]),
                modeled_zenith_sky_brightness=(
                    None if light is None else float(light["modeled_zenith_sky_brightness"])
                ),
                base_penalty=None if light is None else float(light["base_penalty"]),
                applied_penalty=None if light is None else float(light["applied_penalty"]),
                light_pollution_available=light is not None,
            )
        except Exception as exc:
            raise _engine_error(capability, exc) from exc


def _engine_error(capability: str, error: Exception) -> EngineCallError:
    code = getattr(error, "code", None)
    if code is None:
        if isinstance(error, (ValidationError, ObservingQualityError)):
            code = "validation"
        elif isinstance(error, LightPollutionArtifactError):
            code = "atlas_invalid"
        else:
            code = "engine_failure"
    details = getattr(error, "details", {})
    if not isinstance(details, Mapping):
        details = {"engine_details": str(details)}
    return EngineCallError(capability, str(code), str(error), details)


def _hourly_weather(row: Mapping[str, object]) -> HourlyWeather:
    return HourlyWeather(
        time=_instant(row["time"]),
        cloud_cover=int(row["cloud_cover"]),
        humidity=int(row["humidity"]),
        wind_speed=float(row["wind_speed"]),
        wind_direction=int(row["wind_direction"]),
        temperature=float(row["temperature"]),
        dew_point=_optional_float(row.get("dew_point")),
        visibility=_optional_float(row.get("visibility")),
        low_cloud_cover=_optional_int(row.get("low_cloud_cover")),
        mid_cloud_cover=_optional_int(row.get("mid_cloud_cover")),
        high_cloud_cover=_optional_int(row.get("high_cloud_cover")),
        wind_speed_200hpa=_optional_float(row.get("wind_speed_200hpa")),
    )


def _hourly_rating(row: Mapping[str, object]) -> HourlyRating:
    return HourlyRating(
        time=_instant(row["time"]),
        score=float(row["score"]),
        cloud_cover=int(row["cloud_cover"]),
        fog_score=int(row["fog_score"]),
        moon_illumination=int(row["moon_illumination"]),
        moon_altitude=float(row["moon_altitude"]),
        wind_speed=float(row["wind_speed"]),
        seeing_score=_optional_float(row.get("seeing_score")),
        transparency_score=_optional_float(row.get("transparency_score")),
    )


def _weather_mapping(row: HourlyWeather) -> dict[str, object]:
    result: dict[str, object] = {
        "time": _utc_z(row.time),
        "cloud_cover": row.cloud_cover,
        "humidity": row.humidity,
        "wind_speed": row.wind_speed,
        "wind_direction": row.wind_direction,
        "temperature": row.temperature,
    }
    for key, value in (
        ("dew_point", row.dew_point),
        ("visibility", row.visibility),
        ("low_cloud_cover", row.low_cloud_cover),
        ("mid_cloud_cover", row.mid_cloud_cover),
        ("high_cloud_cover", row.high_cloud_cover),
        ("wind_speed_200hpa", row.wind_speed_200hpa),
    ):
        if value is not None:
            result[key] = value
    return result


def _utc_z(value: datetime) -> str:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("expected aware datetime")
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _utc_z_required(value: datetime | None) -> str:
    if value is None:
        raise ValueError("required astronomical twilight event is missing")
    return _utc_z(value)


def _instant(value: object) -> datetime:
    if not isinstance(value, str):
        raise ValueError("expected UTC instant string")
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def _optional_instant(value: object) -> datetime | None:
    return None if value is None else _instant(value)


def _optional_float(value: object) -> float | None:
    return None if value is None else float(value)


def _optional_int(value: object) -> int | None:
    return None if value is None else int(value)
