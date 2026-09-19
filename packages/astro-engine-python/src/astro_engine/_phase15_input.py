"""Shared strict JSON primitives for the frozen Phase 15 contracts."""
from typing import Any
from astro_engine.errors import ValidationError
from astro_engine.validate import require_finite_number


def obj(value: Any) -> dict:
    if not isinstance(value, dict):
        raise ValidationError("object required")
    return value


def array(value: Any) -> list:
    if not isinstance(value, list):
        raise ValidationError("array required")
    return value


def number(value: Any) -> float:
    if isinstance(value, (int, float)) and abs(value) > 1_000_000_000:
        raise ValidationError("number out of profile")
    return require_finite_number(value, "number")


def optional_number(value: Any) -> float | None:
    return None if value is None else number(value)


def boolean(value: Any) -> bool:
    if not isinstance(value, bool):
        raise ValidationError("boolean required")
    return value


def enum(value: Any, values: tuple[str, ...]) -> str:
    if not isinstance(value, str) or value not in values:
        raise ValidationError("invalid enum")
    return value


def key(value: Any, seen: set[str]) -> str:
    if not isinstance(value, str) or not value or value in seen:
        raise ValidationError("unique nonempty key required")
    seen.add(value)
    return value
