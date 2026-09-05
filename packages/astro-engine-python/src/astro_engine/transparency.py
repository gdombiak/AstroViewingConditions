"""transparency.penalty — 0–2 penalty from total/layered cloud and optional visibility."""

from __future__ import annotations

from typing import Any, Mapping

from astro_engine.contracts import transparency_calibration
from astro_engine.errors import ValidationError
from astro_engine.tables import score_lower_bound, score_upper_bound
from astro_engine.validate import optional_finite_number, optional_int, require_int

CAPABILITY_ID = "transparency.penalty"


def transparency_penalty(
    inputs: Mapping[str, Any],
    *,
    calibration: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Return `{penalty: number}`. Never null; missing layers fall back to total cloud."""
    if not isinstance(inputs, Mapping):
        raise ValidationError("transparency.penalty input must be an object")
    cal = dict(calibration) if calibration is not None else transparency_calibration()
    return {
        "penalty": transparency_penalty_value(
            total_cloud_cover=require_int(inputs.get("total_cloud_cover"), "total_cloud_cover"),
            low_cloud_cover=optional_int(inputs.get("low_cloud_cover"), "low_cloud_cover"),
            mid_cloud_cover=optional_int(inputs.get("mid_cloud_cover"), "mid_cloud_cover"),
            high_cloud_cover=optional_int(inputs.get("high_cloud_cover"), "high_cloud_cover"),
            visibility_meters=optional_finite_number(
                inputs.get("visibility_meters"), "visibility_meters"
            ),
            calibration=cal,
        )
    }


def transparency_penalty_value(
    *,
    total_cloud_cover: int,
    low_cloud_cover: int | None,
    mid_cloud_cover: int | None,
    high_cloud_cover: int | None,
    visibility_meters: float | None,
    calibration: Mapping[str, Any],
) -> float:
    total = float(min(max(total_cloud_cover, 0), 100))
    if (
        low_cloud_cover is not None
        and mid_cloud_cover is not None
        and high_cloud_cover is not None
    ):
        weights = calibration["layer_weights"]
        layered = (
            float(min(max(low_cloud_cover, 0), 100)) * float(weights["low"])
            + float(min(max(mid_cloud_cover, 0), 100)) * float(weights["mid"])
            + float(min(max(high_cloud_cover, 0), 100)) * float(weights["high"])
        )
        effective = max(total, layered)
    else:
        effective = total

    cloud = score_upper_bound(
        effective, calibration["cloud_cover"], name="transparency cloud_cover"
    )
    if visibility_meters is None:
        return cloud

    visibility = score_lower_bound(
        max(visibility_meters, 0.0),
        calibration["visibility_meters"],
        name="transparency visibility_meters",
    )
    combine = calibration["combine_weights"]
    combined = cloud * float(combine["cloud"]) + visibility * float(combine["visibility"])
    penalty_min = float(calibration["penalty_min"])
    penalty_max = float(calibration["penalty_max"])
    return min(max(max(cloud, combined), penalty_min), penalty_max)
