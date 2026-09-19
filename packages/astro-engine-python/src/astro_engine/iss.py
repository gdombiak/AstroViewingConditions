"""iss.decode — N2YO visualpasses envelope → deterministic ISSPass DTOs.

Raw provider JSON in; no HTTP, no API key, no URL construction.
`ISSPass.id` is the Swift `stableID` string: IEEE-754 bitPattern of
`riseTime.timeIntervalSince1970` and `duration`, joined by `-`.
"""

from __future__ import annotations

import struct
from datetime import datetime, timezone
from typing import Any, Mapping

from astro_engine.errors import ValidationError
from astro_engine.validate import format_utc_z, require_finite_number, require_int

CAPABILITY_ID = "iss.decode"


def decode_iss(payload: Mapping[str, Any] | Any) -> dict[str, Any]:
    """Normalize a raw N2YO visualpasses object into the iss.decode DTO."""
    if not isinstance(payload, Mapping):
        raise ValidationError("N2YO visualpasses envelope must be an object")
    _require_info(payload.get("info"))

    if "passes" not in payload or payload["passes"] is None:
        return {"passes": []}
    raw_passes = payload["passes"]
    if not isinstance(raw_passes, list):
        raise ValidationError("passes must be an array")
    return {"passes": [_decode_pass(item, index) for index, item in enumerate(raw_passes)]}


def iss_pass_id(*, rise_time_unix: float, duration: float) -> str:
    """Swift `ISSPass.stableID` — not Python `hash()`."""
    return f"{_ieee754_bit_pattern(rise_time_unix)}-{_ieee754_bit_pattern(duration)}"


def _ieee754_bit_pattern(value: float) -> int:
    return int.from_bytes(struct.pack(">d", float(value)), "big")


def _require_info(value: Any) -> None:
    if not isinstance(value, Mapping):
        raise ValidationError("info must be an object")
    require_int(value.get("satid"), "info.satid")
    satname = value.get("satname")
    if not isinstance(satname, str):
        raise ValidationError("info.satname must be a string")
    require_int(value.get("transactionscount"), "info.transactionscount")
    if "passescount" in value and value["passescount"] is not None:
        require_int(value["passescount"], "info.passescount")


def _decode_pass(value: Any, index: int) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise ValidationError(f"passes[{index}] must be an object")
    prefix = f"passes[{index}]"
    start_utc = require_int(value.get("startUTC"), f"{prefix}.startUTC")
    max_utc = require_int(value.get("maxUTC"), f"{prefix}.maxUTC")
    end_utc = require_int(value.get("endUTC"), f"{prefix}.endUTC")
    duration = require_int(value.get("duration"), f"{prefix}.duration")
    require_finite_number(value.get("startAz"), f"{prefix}.startAz")
    require_finite_number(value.get("maxAz"), f"{prefix}.maxAz")
    require_finite_number(value.get("endAz"), f"{prefix}.endAz")
    require_finite_number(value.get("mag"), f"{prefix}.mag")
    start_el = require_finite_number(value.get("startEl"), f"{prefix}.startEl")
    max_el = require_finite_number(value.get("maxEl"), f"{prefix}.maxEl")
    end_el = require_finite_number(value.get("endEl"), f"{prefix}.endEl")
    start_dir = _require_string(value.get("startAzCompass"), f"{prefix}.startAzCompass")
    max_dir = _require_string(value.get("maxAzCompass"), f"{prefix}.maxAzCompass")
    end_dir = _require_string(value.get("endAzCompass"), f"{prefix}.endAzCompass")

    rise = float(start_utc)
    duration_interval = float(duration)
    return {
        "id": iss_pass_id(rise_time_unix=rise, duration=duration_interval),
        "rise_time": _unix_z(rise),
        "duration": duration,
        "max_elevation": max_el,
        "max_time": _unix_z(float(max_utc)),
        "end_time": _unix_z(float(end_utc)),
        "start_direction": start_dir,
        "max_direction": max_dir,
        "end_direction": end_dir,
        "start_elevation": start_el,
        "end_elevation": end_el,
    }


def _require_string(value: Any, name: str) -> str:
    if not isinstance(value, str):
        raise ValidationError(f"{name} must be a string")
    return value


def _unix_z(epoch_seconds: float) -> str:
    return format_utc_z(datetime.fromtimestamp(epoch_seconds, tz=timezone.utc))
