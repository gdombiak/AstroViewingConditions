"""NoData handling for zenith brightness rasters."""

from __future__ import annotations

import numpy as np

# GDAL/NetCDF conventional fill for this atlas family
DEFAULT_NODATA = 9.96921e36
# Values at or above this threshold are treated as NoData (covers float32 encoding)
NODATA_THRESHOLD = 1.0e30


def is_nodata(arr: np.ndarray, nodata: float | None = DEFAULT_NODATA) -> np.ndarray:
    """Boolean mask of NoData cells (True = invalid)."""
    a = np.asarray(arr)
    mask = ~np.isfinite(a)
    if nodata is not None and np.isfinite(nodata):
        # Exact match plus large-fill convention
        mask = mask | (a == nodata) | (np.abs(a) >= NODATA_THRESHOLD)
    else:
        mask = mask | (np.abs(a) >= NODATA_THRESHOLD)
    return mask


def valid_mask(arr: np.ndarray, nodata: float | None = DEFAULT_NODATA) -> np.ndarray:
    return ~is_nodata(arr, nodata)


def with_nodata(arr: np.ndarray, mask_invalid: np.ndarray, nodata: float = DEFAULT_NODATA) -> np.ndarray:
    out = np.array(arr, dtype=np.float32, copy=True)
    out[mask_invalid] = np.float32(nodata)
    return out
