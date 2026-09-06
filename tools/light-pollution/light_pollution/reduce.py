"""Spatial reduction candidates."""

from __future__ import annotations

from typing import Any

import numpy as np

from .brightness import (
    block_reduce_vectorized_linear,
    block_reduce_vectorized_mag,
)
from .grid import GeoGrid, reduction_factor_for_degrees
from .nodata import DEFAULT_NODATA


METHODS = ("nearest", "mag_avg", "linear_avg")
TARGET_DEGREES = (0.025, 0.05, 0.1)


def reduce_array(
    arr: np.ndarray,
    grid: GeoGrid,
    target_deg: float,
    method: str,
) -> tuple[np.ndarray, GeoGrid, dict[str, Any]]:
    src_px = abs(grid.pixel_width)
    factor = reduction_factor_for_degrees(src_px, target_deg)
    # For this atlas, 0.008333 * 3 = 0.025, *6 = 0.05, *12 = 0.1
    if method == "nearest":
        cy = factor // 2
        cx = factor // 2
        h, w = arr.shape
        out_h = h // factor
        out_w = w // factor
        coarse = arr[cy : out_h * factor : factor, cx : out_w * factor : factor].astype(np.float32)
    elif method == "linear_avg":
        coarse = block_reduce_vectorized_linear(arr, factor, factor, grid.nodata)
    elif method == "mag_avg":
        coarse = block_reduce_vectorized_mag(arr, factor, factor, grid.nodata)
    else:
        raise ValueError(method)

    out_h, out_w = coarse.shape
    out_grid = GeoGrid(
        origin_lon=grid.origin_lon,
        origin_lat=grid.origin_lat,
        pixel_width=grid.pixel_width * factor,
        pixel_height=grid.pixel_height * factor,
        width=out_w,
        height=out_h,
        nodata=grid.nodata,
    )
    info = {
        "method": method,
        "target_deg": target_deg,
        "factor": factor,
        "actual_pixel_deg": abs(out_grid.pixel_width),
        "shape": [out_h, out_w],
        "preferred_scientific": method == "linear_avg",
        "baseline_only": method == "mag_avg",
    }
    return coarse, out_grid, info
