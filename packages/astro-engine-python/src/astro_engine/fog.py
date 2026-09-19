"""fog.score — integer fog risk and ordered factor ids from one hourly forecast."""

from __future__ import annotations

from typing import Any, Mapping

from astro_engine.contracts import fog_calibration
from astro_engine.errors import ValidationError
from astro_engine.validate import (
    optional_finite_number,
    optional_int,
    require_finite_number,
    require_int,
    trunc_toward_zero,
)

CAPABILITY_ID = "fog.score"

FACTOR_HIGH_HUMIDITY = "high_humidity"
FACTOR_LOW_TEMP_DEW_DIFF = "low_temp_dew_diff"
FACTOR_LOW_VISIBILITY = "low_visibility"
FACTOR_HIGH_LOW_CLOUD = "high_low_cloud"
FACTOR_LOW_WIND = "low_wind"


def score_fog(
    inputs: Mapping[str, Any],
    *,
    calibration: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return `{score, factors}` from a forecast/injected object."""
    if not isinstance(inputs, Mapping):
        raise ValidationError("fog.score input must be an object")
    cal = dict(calibration) if calibration is not None else fog_calibration()
    score_min = int(cal["score_min"])
    score_max = int(cal["score_max"])
    humidity_cal = cal["humidity"]
    dew_cal = cal["dew_spread"]
    vis_cal = cal["visibility"]
    cloud_cal = cal["low_cloud"]
    wind_cal = cal["wind"]

    humidity = require_int(inputs.get("humidity"), "humidity")
    temperature = require_finite_number(inputs.get("temperature"), "temperature")
    wind_speed = require_finite_number(inputs.get("wind_speed"), "wind_speed")
    dew_point = optional_finite_number(inputs.get("dew_point"), "dew_point")
    visibility = optional_finite_number(inputs.get("visibility"), "visibility")
    low_cloud = optional_int(inputs.get("low_cloud_cover"), "low_cloud_cover")

    score = 0
    factors: list[str] = []

    min_humidity = int(humidity_cal["min_percent"])
    if humidity >= min_humidity:
        humidity_score = trunc_toward_zero(
            (float(humidity) - float(min_humidity))
            / float(humidity_cal["span_percent"])
            * float(humidity_cal["max_points"])
        )
        humidity_score = max(humidity_score, 0)
        score += humidity_score
        if humidity_score > 0:
            factors.append(FACTOR_HIGH_HUMIDITY)

    if dew_point is not None:
        spread = temperature - dew_point
        max_spread = float(dew_cal["max_celsius"])
        if spread < max_spread:
            spread_score = trunc_toward_zero(
                (max_spread - spread) / max_spread * float(dew_cal["max_points"])
            )
            spread_score = max(spread_score, 0)
            score += spread_score
            if spread_score > 0:
                factors.append(FACTOR_LOW_TEMP_DEW_DIFF)

    if visibility is not None:
        max_visibility = float(vis_cal["max_meters"])
        if visibility < max_visibility:
            visibility_score = trunc_toward_zero(
                (max_visibility - visibility)
                / max_visibility
                * float(vis_cal["max_points"])
            )
            visibility_score = max(visibility_score, 0)
            score += visibility_score
            if visibility_score > 0:
                factors.append(FACTOR_LOW_VISIBILITY)

    if low_cloud is not None:
        min_low = int(cloud_cal["min_percent"])
        if low_cloud >= min_low:
            cloud_score = trunc_toward_zero(
                (float(low_cloud) - float(min_low))
                / float(cloud_cal["span_percent"])
                * float(cloud_cal["max_points"])
            )
            cloud_score = max(cloud_score, 0)
            score += cloud_score
            if cloud_score > 0:
                factors.append(FACTOR_HIGH_LOW_CLOUD)

    max_wind = float(wind_cal["max_meters_per_second"])
    if wind_speed < max_wind:
        wind_score = trunc_toward_zero(
            (max_wind - wind_speed) / max_wind * float(wind_cal["max_points"])
        )
        wind_score = max(wind_score, 0)
        score += wind_score
        if wind_score > 0:
            factors.append(FACTOR_LOW_WIND)

    return {"score": min(score_max, max(score_min, score)), "factors": factors}
