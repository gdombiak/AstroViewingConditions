"""Finite-number, timestamp, and IANA timezone checks for scoring inputs."""

from __future__ import annotations

import math
import re
from datetime import datetime, timezone
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from astro_engine.errors import ValidationError

UTC_Z_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def require_finite_number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValidationError(f"{name} must be a finite JSON number")
    number = float(value)
    if not math.isfinite(number):
        raise ValidationError(f"{name} must be a finite JSON number")
    return number


def optional_finite_number(value: Any, name: str) -> float | None:
    if value is None:
        return None
    return require_finite_number(value, name)


def require_int(value: Any, name: str) -> int:
    number = require_finite_number(value, name)
    if number != math.trunc(number):
        raise ValidationError(f"{name} must be an integral number")
    return int(number)


def optional_int(value: Any, name: str) -> int | None:
    if value is None:
        return None
    return require_int(value, name)


def trunc_toward_zero(value: float) -> int:
    """Swift `Int(Double)` / Python `int(float)`: truncate toward zero."""
    return int(value)


def parse_utc_z(value: Any, name: str) -> datetime:
    if not isinstance(value, str) or not UTC_Z_PATTERN.fullmatch(value):
        raise ValidationError(f"{name} is required")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:
        raise ValidationError(f"{name} is required") from exc
    if parsed.tzinfo is None:
        raise ValidationError(f"{name} is required")
    return parsed.astimezone(timezone.utc)


def format_utc_z(value: datetime) -> str:
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def require_iana_timezone(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise ValidationError("time_zone is required")
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, KeyError) as exc:
        raise ValidationError("time_zone is required") from exc
    return value
