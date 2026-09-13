"""Production cloud-advisory eligibility, without English presentation copy."""

from __future__ import annotations

import math
from typing import Any, Mapping

from astro_engine.contracts import night_quality_calibration
from astro_engine.errors import ValidationError

CAPABILITY_ID = "night_conditions.select_cloud_advisory"
_TIMINGS = frozenset({"none", "early_heavy", "late_heavy", "intermittent_heavy"})
_RATINGS = frozenset({"excellent", "good", "fair", "poor"})


def select_cloud_advisory(input: Mapping[str, Any]) -> dict[str, str | None]:
    if not isinstance(input, Mapping) or set(input) != {
        "cloud_timing", "rating", "average_cloud_cover"
    }:
        raise ValidationError(f"invalid {CAPABILITY_ID} input")
    timing = input["cloud_timing"]
    rating = input["rating"]
    average = input["average_cloud_cover"]
    if (
        not isinstance(timing, str) or timing not in _TIMINGS
        or not isinstance(rating, str) or rating not in _RATINGS
        or isinstance(average, bool) or not isinstance(average, (int, float))
    ):
        raise ValidationError(f"invalid {CAPABILITY_ID} input")
    try:
        cloud = float(average)
    except OverflowError as exc:
        raise ValidationError(f"invalid {CAPABILITY_ID} input") from exc
    if not math.isfinite(cloud) or not 0 <= cloud <= 100:
        raise ValidationError(f"invalid {CAPABILITY_ID} input")
    heavy_floor = night_quality_calibration()["cloud_floor"]["cloud_cover_min"]
    advisory = None if cloud >= heavy_floor or rating == "poor" or timing == "none" else timing
    return {"cloud_advisory": advisory}
