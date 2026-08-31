"""observing_quality.assess — loads anchors from contracts, not a local copy."""

from __future__ import annotations

import math
from typing import Any, Mapping

from astro_engine.contracts import observing_quality_calibration

CAPABILITY_ID = "observing_quality.assess"


class ObservingQualityError(ValueError):
    pass


def _as_night_score(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ObservingQualityError("night_conditions_score must be a JSON number")
    if isinstance(value, float):
        if not math.isfinite(value) or value != math.trunc(value):
            raise ObservingQualityError("night_conditions_score must be an integral number")
        return int(value)
    return int(value)


def _as_brightness(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ObservingQualityError(
            "modeled_zenith_sky_brightness must be a finite JSON number or null"
        )
    number = float(value)
    if not math.isfinite(number):
        raise ObservingQualityError(
            "modeled_zenith_sky_brightness must be a finite JSON number or null"
        )
    return number


def _piecewise_linear(x: float, anchors: list[tuple[float, float]]) -> float:
    if not anchors:
        raise ObservingQualityError("calibration anchors must not be empty")
    if x <= anchors[0][0]:
        return anchors[0][1]
    if x >= anchors[-1][0]:
        return anchors[-1][1]
    for index in range(len(anchors) - 1):
        x0, y0 = anchors[index]
        x1, y1 = anchors[index + 1]
        if x0 <= x <= x1:
            if x1 == x0:
                return y0
            t = (x - x0) / (x1 - x0)
            return y0 + t * (y1 - y0)
    return anchors[-1][1]


def _round_half_away_from_zero(value: float) -> int:
    # Swift Double.rounded() / .toNearestOrAwayFromZero, then Int.
    if value >= 0:
        return int(math.floor(value + 0.5))
    return int(-math.floor(-value + 0.5))


def assess_observing_quality(
    night_conditions_score: Any,
    modeled_zenith_sky_brightness: Any = None,
    *,
    calibration: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return the observing-quality DTO (the `result` object, not the envelope)."""
    cal = dict(calibration) if calibration is not None else observing_quality_calibration()
    score_min = int(cal["score_min"])
    score_max = int(cal["score_max"])
    plausible = cal["plausible_brightness"]
    brightness_min = float(plausible["min"])
    brightness_max = float(plausible["max"])
    base_anchors = [
        (float(item["brightness"]), float(item["penalty"]))
        for item in cal["base_penalty_anchors"]
    ]
    weight_anchors = [
        (float(item["score"]), float(item["weight"]))
        for item in cal["usability_weight_anchors"]
    ]

    clamped_night = min(score_max, max(score_min, _as_night_score(night_conditions_score)))
    brightness = _as_brightness(modeled_zenith_sky_brightness)

    unavailable = (
        brightness is None
        or not math.isfinite(brightness)
        or brightness < brightness_min
        or brightness > brightness_max
    )
    if unavailable:
        return {
            "score": clamped_night,
            "night_conditions_score": clamped_night,
            "light_pollution": None,
        }

    base = _piecewise_linear(brightness, base_anchors)
    weight = _piecewise_linear(float(clamped_night), weight_anchors)
    applied = base * weight
    score = min(score_max, max(score_min, _round_half_away_from_zero(clamped_night - applied)))
    return {
        "score": score,
        "night_conditions_score": clamped_night,
        "light_pollution": {
            "modeled_zenith_sky_brightness": brightness,
            "base_penalty": base,
            "applied_penalty": applied,
        },
    }
