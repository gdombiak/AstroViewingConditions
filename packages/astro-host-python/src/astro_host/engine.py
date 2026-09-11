"""Thin typed adapter over in-process Astro Engine module APIs.

This module converts DTOs only. Acquisition, caching, fallback and composition
remain in ``ConditionsService``.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from pathlib import Path
from typing import Mapping, Sequence

from astro_engine.astronomy import evaluate_astronomy
from astro_engine.catalog import catalog_deep_sky
from astro_engine.cloud_timing import classify_cloud_timing
from astro_engine.compose_recommendations import compose_recommendations
from astro_engine.contracts import ContractsRootError, engine_semver
from astro_engine.deep_sky_observation import evaluate_deep_sky_observation
from astro_engine.equipment import match_equipment
from astro_engine.errors import ValidationError
from astro_engine.filter_recommendations_by_equipment import (
    filter_recommendations_by_equipment,
)
from astro_engine.light_pollution import LightPollutionArtifact, LightPollutionArtifactError
from astro_engine.moon_observation import evaluate_moon_observation
from astro_engine.moon_recommendation import recommend_moon
from astro_engine.night_conditions import analyze_night_conditions
from astro_engine.night_forecast import derive_night_forecast_window
from astro_engine.observing_night import resolve_active_observing_night
from astro_engine.observing_quality import ObservingQualityError, assess_observing_quality
from astro_engine.observing_window import select_observing_window
from astro_engine.planet_observation import evaluate_planet_observation
from astro_engine.planet_recommendation import recommend_planet
from astro_engine.target_metadata import evaluate_metadata
from astro_engine.targets import recommend_targets
from astro_engine.weather import decode_weather

from astro_host.errors import EngineCallError
from astro_host.models import (
    ActiveEquipment,
    ActiveNightResolution,
    HourlyRating,
    HourlyWeather,
    Location,
    MoonSample,
    NightAnalysis,
    ObservingQualityFacts,
    SunEventsFacts,
    TimeWindow,
    VisibilityWindow,
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


CATALOG_OBJECT_TYPES = {
    "galaxy": "galaxy",
    "diffuse_nebula": "diffuseNebula",
    "globular_cluster": "globularCluster",
    "open_cluster": "openCluster",
    "double_star": "doubleStar",
    "planetary_nebula": "planetaryNebula",
}

_MOON_BUNDLE_KEYS = (
    "phase",
    "illumination",
    "rise",
    "set",
    "always_up",
    "always_down",
    "samples",
)


class RecommendationEngine:
    """Sole JSON-projection owner for recommendation capabilities."""

    def catalog_object_type(self, snake: str) -> str:
        try:
            return CATALOG_OBJECT_TYPES[snake]
        except KeyError as exc:
            raise EngineCallError(
                "targets.moon_sensitivity",
                "validation",
                f"unknown catalog object_type: {snake}",
            ) from exc

    def solar_system(self) -> list[dict[str, object]]:
        result = self._invoke(
            "catalog.solar_system",
            {},
            lambda payload: evaluate_metadata("catalog.solar_system", payload),
        )
        return list(result["entries"])

    def deep_sky(self) -> list[dict[str, object]]:
        result = self._invoke(
            "catalog.deep_sky",
            {},
            catalog_deep_sky,
        )
        return list(result["entries"])

    def moon_sensitivity(
        self, object_type: str, surface_brightness: float | None
    ) -> float:
        mapped = self.catalog_object_type(object_type)
        payload = {
            "object_type": mapped,
            "surface_brightness": surface_brightness,
        }
        result = self._invoke(
            "targets.moon_sensitivity",
            payload,
            lambda body: evaluate_metadata("targets.moon_sensitivity", body),
        )
        return float(result["sensitivity"])

    def moon_info(self, location: Location, instant: datetime) -> dict[str, object]:
        payload = {
            "latitude": location.latitude,
            "longitude": location.longitude,
            "time": _utc_z(instant),
        }
        result = self._invoke(
            "astronomy.moon_info",
            payload,
            lambda body: evaluate_astronomy("astronomy.moon_info", body),
        )
        return {
            "altitude": result["altitude"],
            "illumination": result["illumination"],
        }

    def moon_observation(
        self, location: Location, night_start: datetime, night_end: datetime
    ) -> dict[str, object]:
        payload = {
            "latitude": location.latitude,
            "longitude": location.longitude,
            "night_start": _utc_z(night_start),
            "night_end": _utc_z(night_end),
        }
        return self._invoke(
            "astronomy.moon_observation", payload, evaluate_moon_observation
        )

    def moon_recommendation(
        self,
        observation: Mapping[str, object],
        *,
        night_start: datetime,
        night_end: datetime,
        cloud_cover_score: object,
        hourly_ratings: Sequence[HourlyRating],
        best_window: TimeWindow | None,
    ) -> dict[str, object] | None:
        payload = {
            "night_start": _utc_z(night_start),
            "night_end": _utc_z(night_end),
            "best_window": (
                None
                if best_window is None
                else {"start": _utc_z(best_window.start), "end": _utc_z(best_window.end)}
            ),
            "moon": {key: observation[key] for key in _MOON_BUNDLE_KEYS},
            "cloud_cover_score": cloud_cover_score,
            "hourly_ratings": _hourly_scores(hourly_ratings),
        }
        result = self._invoke(
            "targets.moon_recommendation", payload, recommend_moon
        )
        raw = result["recommendation"]
        return None if raw is None else dict(raw)

    def planet_observation(
        self,
        target_id: str,
        location: Location,
        night_start: datetime,
        night_end: datetime,
    ) -> dict[str, object] | None:
        payload = {
            "target_id": target_id,
            "latitude": location.latitude,
            "longitude": location.longitude,
            "night_start": _utc_z(night_start),
            "night_end": _utc_z(night_end),
        }
        result = self._invoke(
            "astronomy.planet_observation", payload, evaluate_planet_observation
        )
        observation = result["observation"]
        return None if observation is None else dict(observation)

    def planet_recommendation(
        self,
        target_id: str,
        samples: Sequence[Mapping[str, object]],
        *,
        night_start: datetime,
        night_end: datetime,
        cloud_cover_score: object,
        hourly_ratings: Sequence[HourlyRating],
    ) -> dict[str, object] | None:
        payload = {
            "target_id": target_id,
            "night_start": _utc_z(night_start),
            "night_end": _utc_z(night_end),
            "samples": list(samples),
            "cloud_cover_score": cloud_cover_score,
            "hourly_ratings": _hourly_scores(hourly_ratings),
        }
        result = self._invoke(
            "targets.planet_recommendation", payload, recommend_planet
        )
        raw = result["recommendation"]
        return None if raw is None else dict(raw)

    def deep_sky_windows(
        self,
        target_id: str,
        location: Location,
        night_start: datetime,
        night_end: datetime,
    ) -> list[dict[str, object]]:
        payload = {
            "target_id": target_id,
            "latitude": location.latitude,
            "longitude": location.longitude,
            "night_start": _utc_z(night_start),
            "night_end": _utc_z(night_end),
        }
        result = self._invoke(
            "targets.deep_sky_windows",
            payload,
            lambda body: evaluate_deep_sky_observation(
                "targets.deep_sky_windows", body
            ),
        )
        return list(result["windows"])

    def recommend_deep_sky(
        self,
        *,
        darkness_start: datetime,
        darkness_end: datetime,
        moon: Mapping[str, object],
        cloud_cover_score: object,
        hourly_ratings: Sequence[HourlyRating],
        rows: Sequence[tuple[str, str, float, float, datetime, datetime, datetime, float]],
    ) -> dict[str, int]:
        candidates = [
            {
                "key": key,
                "type": "deepSky",
                "object_type": self.catalog_object_type(object_type),
                "difficulty": difficulty,
                "sensitivity": sensitivity,
                "window": {
                    "start": _utc_z(start),
                    "end": _utc_z(end),
                    "best_time": _utc_z(best_time),
                    "max_altitude": max_altitude,
                },
            }
            for (
                key,
                object_type,
                difficulty,
                sensitivity,
                start,
                end,
                best_time,
                max_altitude,
            ) in rows
        ]
        payload = {
            "darkness_window": {
                "start": _utc_z(darkness_start),
                "end": _utc_z(darkness_end),
            },
            "moon": {"altitude": moon["altitude"], "illumination": moon["illumination"]},
            "hourly_ratings": _hourly_scores(hourly_ratings),
            "cloud_cover_score": cloud_cover_score,
            "candidates": candidates,
            "limit": len(candidates),
        }
        result = self._invoke(
            "targets.recommend", payload, recommend_targets
        )
        return {
            str(row["key"]): int(row["score"])
            for row in result["recommendations"]
        }

    def compose_recommendations(
        self,
        rows: Sequence[tuple[str, int, datetime]],
        *,
        limit: int,
    ) -> list[int]:
        payload = {
            "candidates": [
                {
                    "key": key,
                    "score": score,
                    "best_time": _utc_z(best_time),
                }
                for key, score, best_time in rows
            ],
            "limit": limit,
        }
        result = self._invoke(
            "targets.compose_recommendations", payload, compose_recommendations
        )
        return [int(row["index"]) for row in result["selected"]]

    def requirements(self, target_id: str) -> dict[str, object]:
        payload = {"id": target_id}
        result = self._invoke(
            "targets.requirements",
            payload,
            lambda body: evaluate_metadata("targets.requirements", body),
        )
        return {
            "requirement": dict(result["requirement"]),
            "is_planet": bool(result["is_planet"]),
        }

    def filter_recommendations(
        self,
        rows: Sequence[tuple[str, bool, Mapping[str, object]]],
        equipment: ActiveEquipment,
        minimum_fit: str,
    ) -> list[int]:
        payload = {
            "candidates": [
                {
                    "key": key,
                    "is_planet": is_planet,
                    "requirement": dict(requirement),
                }
                for key, is_planet, requirement in rows
            ],
            "capabilities": [dict(row) for row in equipment.engine_capabilities()],
            "has_saved_inventory": equipment.engine_has_saved_inventory,
            "minimum_fit": minimum_fit,
        }
        result = self._invoke(
            "targets.filter_recommendations_by_equipment",
            payload,
            filter_recommendations_by_equipment,
        )
        return [int(row["index"]) for row in result["selected"]]

    def match_equipment(
        self,
        requirement: Mapping[str, object],
        is_planet: bool,
        equipment: ActiveEquipment,
    ) -> dict[str, object] | None:
        payload = {
            "requirement": dict(requirement),
            "is_planet": is_planet,
            "capabilities": [dict(row) for row in equipment.engine_capabilities()],
        }
        result = self._invoke("equipment.match", payload, match_equipment)
        raw = result["match"]
        return None if raw is None else dict(raw)

    def parse_visibility_window(self, raw: Mapping[str, object]) -> VisibilityWindow:
        return VisibilityWindow(
            start=_instant(raw["start"]),
            end=_instant(raw["end"]),
            best_time=_instant(raw["best_time"]),
            max_altitude=float(raw["max_altitude"]),
            direction=None if raw.get("direction") is None else str(raw["direction"]),
            azimuth=(
                None if raw.get("azimuth") is None else float(raw["azimuth"])
            ),
        )

    def _invoke(
        self,
        capability: str,
        payload: dict[str, object],
        fn,
    ) -> dict[str, object]:
        try:
            return fn(payload)
        except Exception as exc:
            raise _engine_error(capability, exc) from exc


def _hourly_scores(ratings: Sequence[HourlyRating]) -> list[dict[str, object]]:
    return [{"time": _utc_z(row.time), "score": row.score} for row in ratings]


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
