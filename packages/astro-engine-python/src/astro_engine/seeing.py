"""seeing.penalty — optional 0–2 penalty from temperature delta and/or 200 hPa wind."""

from __future__ import annotations

from typing import Any, Mapping

from astro_engine.contracts import seeing_calibration
from astro_engine.errors import ValidationError
from astro_engine.tables import score_upper_bound
from astro_engine.validate import optional_finite_number, require_finite_number

CAPABILITY_ID = "seeing.penalty"


def seeing_penalty(
    inputs: Mapping[str, Any],
    *,
    calibration: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return `{penalty: number|null}`."""
    if not isinstance(inputs, Mapping):
        raise ValidationError("seeing.penalty input must be an object")
    cal = dict(calibration) if calibration is not None else seeing_calibration()
    current = require_finite_number(inputs.get("current_temperature"), "current_temperature")
    previous = optional_finite_number(inputs.get("previous_temperature"), "previous_temperature")
    wind = optional_finite_number(inputs.get("wind_speed_200hpa"), "wind_speed_200hpa")
    return {
        "penalty": seeing_penalty_value(
            current_temperature=current,
            previous_temperature=previous,
            wind_speed_200hpa=wind,
            calibration=cal,
        )
    }


def seeing_penalty_value(
    *,
    current_temperature: float,
    previous_temperature: float | None,
    wind_speed_200hpa: float | None,
    calibration: Mapping[str, Any],
) -> float | None:
    components: list[float] = []
    if previous_temperature is not None:
        components.append(
            score_upper_bound(
                abs(current_temperature - previous_temperature),
                calibration["temperature_delta_celsius"],
                name="seeing temperature_delta_celsius",
            )
        )
    if wind_speed_200hpa is not None:
        components.append(
            score_upper_bound(
                wind_speed_200hpa,
                calibration["upper_wind_200hpa"],
                name="seeing upper_wind_200hpa",
            )
        )
    if not components:
        return None
    mean = sum(components) / float(len(components))
    penalty_min = float(calibration["penalty_min"])
    penalty_max = float(calibration["penalty_max"])
    return min(max(mean, penalty_min), penalty_max)
