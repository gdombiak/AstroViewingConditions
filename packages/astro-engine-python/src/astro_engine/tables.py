"""Inclusive upper/lower-bound calibration tables."""

from __future__ import annotations

from typing import Any, Mapping, Sequence

from astro_engine.errors import ValidationError


def score_upper_bound(value: float, buckets: Sequence[Mapping[str, Any]], *, name: str) -> float:
    """First row with `value <= max`. A null `max` is the catch-all last row."""
    if not buckets:
        raise ValidationError(f"{name} must not be empty")
    for bucket in buckets:
        maximum = bucket.get("max")
        score = float(bucket["score"])
        if maximum is None:
            return score
        if value <= float(maximum):
            return score
    return float(buckets[-1]["score"])


def score_lower_bound(value: float, buckets: Sequence[Mapping[str, Any]], *, name: str) -> float:
    """First row with `value >= min`. A null `min` is the catch-all last row."""
    if not buckets:
        raise ValidationError(f"{name} must not be empty")
    for bucket in buckets:
        minimum = bucket.get("min")
        score = float(bucket["score"])
        if minimum is None:
            return score
        if value >= float(minimum):
            return score
    return float(buckets[-1]["score"])
