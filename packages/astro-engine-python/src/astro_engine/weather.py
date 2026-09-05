"""weather.decode — Open-Meteo forecast envelope → normalized hourly DTO.

Raw provider JSON in; no HTTP, no geocoding, no host timezone, no scoring.
Precipitation is present on the Open-Meteo envelope but is not a HourlyForecast
field; it is validated when present and then dropped, matching Swift.
"""

from __future__ import annotations

import math
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping, Sequence
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from astro_engine.errors import ValidationError
from astro_engine.validate import format_utc_z, require_finite_number, require_int

CAPABILITY_ID = "weather.decode"

# Exact provider keys from OpenMeteoForecastDecoder.HourlyData.CodingKeys.
_TIME = "time"
_CLOUDCOVER = "cloudcover"
_CLOUDCOVER_LOW = "cloudcover_low"
_CLOUD_COVER_MID = "cloud_cover_mid"
_CLOUD_COVER_HIGH = "cloud_cover_high"
_RELATIVEHUMIDITY_2M = "relativehumidity_2m"
_WINDSPEED_10M = "windspeed_10m"
_WINDDIRECTION_10M = "winddirection_10m"
_TEMPERATURE_2M = "temperature_2m"
_DEWPOINT_2M = "dewpoint_2m"
_PRECIPITATION = "precipitation"
_VISIBILITY = "visibility"
_WIND_SPEED_200HPA = "wind_speed_200hPa"

# OpenMeteoForecastDecoder / POSIX DateFormatter with format
# yyyy-MM-dd'T'HH:mm. Empirically: 4-digit year; 1-2 digit month/day/hour/minute;
# literal 'T'; hyphen separators; no seconds. Trailing seconds are skipped.
_LOCAL_TIME = re.compile(r"^(\d{4})-(\d{1,2})-(\d{1,2})T(\d{1,2}):(\d{1,2})$")

# Swift TimeZone(secondsFromGMT:) is nil outside ±18 hours, then the decoder
# falls back to TimeZone(secondsFromGMT: 0) for parsing.
_SWIFT_GMT_OFFSET_MAX_SECONDS = 18 * 60 * 60


def decode_weather(payload: Mapping[str, Any] | Any) -> dict[str, Any]:
    """Normalize a raw Open-Meteo forecast object into the weather.decode DTO."""
    if not isinstance(payload, Mapping):
        raise ValidationError("Open-Meteo forecast envelope must be an object")

    offset = require_int(payload.get("utc_offset_seconds"), "utc_offset_seconds")
    timezone_out = _optional_timezone_string(payload)
    zone = _parser_timezone(timezone_out, offset)

    hourly = payload.get("hourly")
    if not isinstance(hourly, Mapping):
        raise ValidationError("hourly must be an object")

    times = _require_string_array(hourly.get(_TIME), _TIME)
    cloudcover = _require_int_array(hourly.get(_CLOUDCOVER), _CLOUDCOVER)
    humidity = _require_int_array(hourly.get(_RELATIVEHUMIDITY_2M), _RELATIVEHUMIDITY_2M)
    wind_speed = _require_number_array(hourly.get(_WINDSPEED_10M), _WINDSPEED_10M)
    wind_direction = _require_int_array(hourly.get(_WINDDIRECTION_10M), _WINDDIRECTION_10M)
    temperature = _require_number_array(hourly.get(_TEMPERATURE_2M), _TEMPERATURE_2M)

    low_cloud = _optional_int_array(hourly, _CLOUDCOVER_LOW)
    mid_cloud = _optional_int_array(hourly, _CLOUD_COVER_MID)
    high_cloud = _optional_int_array(hourly, _CLOUD_COVER_HIGH)
    dew_point = _optional_number_array(hourly, _DEWPOINT_2M)
    visibility = _optional_number_array(hourly, _VISIBILITY)
    wind_200hpa = _optional_number_array(hourly, _WIND_SPEED_200HPA)
    # Decode so a structurally invalid precipitation array still fails closed.
    _optional_number_array(hourly, _PRECIPITATION)

    rows: list[dict[str, Any]] = []
    for index, raw_time in enumerate(times):
        parsed = _parse_open_meteo_local(raw_time, zone)
        if parsed is None:
            continue
        row: dict[str, Any] = {
            "time": format_utc_z(parsed),
            "cloud_cover": _required_at(cloudcover, index, default=0),
            "humidity": _required_at(humidity, index, default=0),
            "wind_speed": _required_at(wind_speed, index, default=0.0),
            "wind_direction": _required_at(wind_direction, index, default=0),
            "temperature": _required_at(temperature, index, default=0.0),
        }
        _put_optional(row, "dew_point", _optional_at(dew_point, index))
        _put_optional(row, "visibility", _optional_at(visibility, index))
        _put_optional(row, "low_cloud_cover", _optional_at(low_cloud, index))
        _put_optional(row, "mid_cloud_cover", _optional_at(mid_cloud, index))
        _put_optional(row, "high_cloud_cover", _optional_at(high_cloud, index))
        _put_optional(row, "wind_speed_200hpa", _optional_at(wind_200hpa, index))
        rows.append(row)

    return {
        "hourly": rows,
        "timezone": timezone_out,
        "utc_offset_seconds": offset,
    }


def _optional_timezone_string(payload: Mapping[str, Any]) -> str | None:
    if "timezone" not in payload or payload["timezone"] is None:
        return None
    value = payload["timezone"]
    if not isinstance(value, str):
        raise ValidationError("timezone must be a string or null")
    return value


def _parser_timezone(raw: str | None, offset_seconds: int) -> timezone | ZoneInfo:
    if raw:
        try:
            return ZoneInfo(raw)
        except (ZoneInfoNotFoundError, ValueError, KeyError):
            pass
    return _fixed_offset(offset_seconds)


def _fixed_offset(offset_seconds: int) -> timezone:
    """Match Swift `TimeZone(secondsFromGMT:)` then `secondsFromGMT: 0`.

    In-range offsets are quantized to the nearest minute, rounding half away
    from zero. Values outside ±18 hours fall back to GMT+0 for parsing.
    """
    if abs(offset_seconds) > _SWIFT_GMT_OFFSET_MAX_SECONDS:
        return timezone.utc
    minutes = _round_half_away_from_zero(offset_seconds / 60.0)
    try:
        return timezone(timedelta(minutes=minutes))
    except ValueError:
        return timezone.utc


def _round_half_away_from_zero(value: float) -> int:
    if value == 0:
        return 0
    return int(math.copysign(math.floor(abs(value) + 0.5), value))


def _parse_open_meteo_local(value: str, zone: timezone | ZoneInfo) -> datetime | None:
    match = _LOCAL_TIME.fullmatch(value)
    if match is None:
        return None
    year, month, day, hour, minute = (int(part) for part in match.groups())
    if not 1 <= year <= 9999:
        return None
    if not 1 <= month <= 12:
        return None
    if not 1 <= day <= 31:
        return None
    if not 0 <= hour <= 24:
        return None
    if not 0 <= minute <= 59:
        return None
    try:
        naive = datetime(year, month, 1) + timedelta(
            days=day - 1, hours=hour, minutes=minute
        )
    except ValueError:
        return None
    return naive.replace(tzinfo=zone)


def _require_string_array(value: Any, name: str) -> list[str]:
    if not isinstance(value, list):
        raise ValidationError(f"{name} must be an array of strings")
    rows: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str):
            raise ValidationError(f"{name}[{index}] must be a string")
        rows.append(item)
    return rows


def _require_int_array(value: Any, name: str) -> list[int]:
    if not isinstance(value, list):
        raise ValidationError(f"{name} must be an array of integers")
    return [require_int(item, f"{name}[{index}]") for index, item in enumerate(value)]


def _require_number_array(value: Any, name: str) -> list[float]:
    if not isinstance(value, list):
        raise ValidationError(f"{name} must be an array of numbers")
    return [
        require_finite_number(item, f"{name}[{index}]")
        for index, item in enumerate(value)
    ]


def _optional_int_array(hourly: Mapping[str, Any], name: str) -> list[int] | None:
    if name not in hourly or hourly[name] is None:
        return None
    return _require_int_array(hourly[name], name)


def _optional_number_array(hourly: Mapping[str, Any], name: str) -> list[float] | None:
    if name not in hourly or hourly[name] is None:
        return None
    return _require_number_array(hourly[name], name)


def _required_at(values: Sequence[Any], index: int, *, default: Any) -> Any:
    if 0 <= index < len(values):
        return values[index]
    return default


def _optional_at(values: Sequence[Any] | None, index: int) -> Any:
    if values is None or index < 0 or index >= len(values):
        return None
    return values[index]


def _put_optional(row: dict[str, Any], key: str, value: Any) -> None:
    if value is not None:
        row[key] = value
