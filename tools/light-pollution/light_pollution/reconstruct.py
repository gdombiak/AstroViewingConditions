"""Reconstruct coarse/tiled candidates onto the source-aligned comparison grid."""

from __future__ import annotations

import numpy as np

from .grid import GeoGrid, nearest_upsample
from .nodata import DEFAULT_NODATA


def reconstruct_uniform_to_source(
    coarse: np.ndarray,
    coarse_grid: GeoGrid,
    source_grid: GeoGrid,
) -> np.ndarray:
    """Nearest-neighbor reconstruct coarse grid onto source footprint.

    Uses source cell centers sampled from the coarse grid (no bilinear).
    """
    out = np.full((source_grid.height, source_grid.width), source_grid.nodata, dtype=np.float32)
    # Vectorized: map each source cell center to coarse cell
    rows = np.arange(source_grid.height)
    cols = np.arange(source_grid.width)
    # source cell centers
    lons = source_grid.origin_lon + (cols + 0.5) * source_grid.pixel_width
    lats = source_grid.origin_lat + (rows + 0.5) * source_grid.pixel_height
    # coarse indices
    cc = np.floor((lons - coarse_grid.origin_lon) / coarse_grid.pixel_width).astype(np.int64)
    # for each row lat
    for r, lat in enumerate(lats):
        cr = int(np.floor((coarse_grid.origin_lat - lat) / abs(coarse_grid.pixel_height)))
        if cr < 0 or cr >= coarse_grid.height:
            continue
        valid_c = (cc >= 0) & (cc < coarse_grid.width)
        if not np.any(valid_c):
            continue
        out[r, valid_c] = coarse[cr, cc[valid_c]]
    return out


def reconstruct_uniform_integer_factor(
    coarse: np.ndarray,
    factor: int,
    source_shape: tuple[int, int],
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    """Fast path when coarse was produced by integer block reduction of source."""
    out_h, out_w = source_shape
    up = nearest_upsample(coarse, factor, factor, out_h, out_w)
    # If source larger than factor*coarse due to leftover edges, pad with nodata
    if up.shape[0] < out_h or up.shape[1] < out_w:
        full = np.full((out_h, out_w), nodata, dtype=np.float32)
        full[: up.shape[0], : up.shape[1]] = up
        return full
    return up.astype(np.float32, copy=False)
