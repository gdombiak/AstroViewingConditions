"""Magnitude <-> linear brightness conversions and aggregation.

Scientific convention for this harness:
  L = 10 ** (-0.4 * m)
  m = -2.5 * log10(L)
Larger mag/arcsec² means darker sky (smaller linear brightness).
Preferred spatial aggregation averages linear brightness, not magnitudes.
"""

from __future__ import annotations

import numpy as np

from .nodata import DEFAULT_NODATA, is_nodata, valid_mask


def mag_to_linear(mag: np.ndarray | float) -> np.ndarray | float:
    """Convert mag/arcsec² to relative linear brightness."""
    return np.power(10.0, -0.4 * np.asarray(mag, dtype=np.float64))


def linear_to_mag(linear: np.ndarray | float) -> np.ndarray | float:
    """Convert relative linear brightness to mag/arcsec²."""
    lin = np.asarray(linear, dtype=np.float64)
    # Avoid log of non-positive; callers should exclude invalid
    with np.errstate(divide="ignore", invalid="ignore"):
        return -2.5 * np.log10(lin)


def aggregate_linear_mean(
    values: np.ndarray,
    nodata: float = DEFAULT_NODATA,
) -> float:
    """Preferred: mean of linear brightness of valid cells, back to mag.

    Returns nodata if no valid cells.
    """
    v = np.asarray(values, dtype=np.float64).ravel()
    m = valid_mask(v, nodata)
    if not np.any(m):
        return float(nodata)
    lin = mag_to_linear(v[m])
    mean_lin = float(np.mean(lin))
    if mean_lin <= 0:
        return float(nodata)
    return float(linear_to_mag(mean_lin))


def aggregate_magnitude_mean(
    values: np.ndarray,
    nodata: float = DEFAULT_NODATA,
) -> float:
    """Baseline only: direct mean of magnitude values of valid cells."""
    v = np.asarray(values, dtype=np.float64).ravel()
    m = valid_mask(v, nodata)
    if not np.any(m):
        return float(nodata)
    return float(np.mean(v[m]))


def block_reduce(
    arr: np.ndarray,
    factor_y: int,
    factor_x: int,
    method: str,
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    """Reduce a 2D array by integer factors using the named method.

    method: 'nearest' | 'mag_avg' | 'linear_avg'
    Output shape is floor(h/fy) x floor(w/fx); leftover edge rows/cols dropped.
    """
    if method not in {"nearest", "mag_avg", "linear_avg"}:
        raise ValueError(f"Unknown method: {method}")
    a = np.asarray(arr)
    h, w = a.shape
    out_h = h // factor_y
    out_w = w // factor_x
    if out_h == 0 or out_w == 0:
        raise ValueError("Reduction factors larger than array dimensions")
    cropped = a[: out_h * factor_y, : out_w * factor_x]
    out = np.full((out_h, out_w), nodata, dtype=np.float32)

    if method == "nearest":
        # Cell-center sample within each block
        cy = factor_y // 2
        cx = factor_x // 2
        out[:, :] = cropped[cy::factor_y, cx::factor_x][:out_h, :out_w]
        return out

    # Reshape into blocks
    blocks = cropped.reshape(out_h, factor_y, out_w, factor_x)
    for iy in range(out_h):
        for ix in range(out_w):
            block = blocks[iy, :, ix, :].ravel()
            if method == "linear_avg":
                out[iy, ix] = np.float32(aggregate_linear_mean(block, nodata))
            else:
                out[iy, ix] = np.float32(aggregate_magnitude_mean(block, nodata))
    return out


def block_reduce_vectorized_linear(
    arr: np.ndarray,
    factor_y: int,
    factor_x: int,
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    """Faster linear-mean reduction using vectorized ops where possible."""
    a = np.asarray(arr, dtype=np.float64)
    h, w = a.shape
    out_h = h // factor_y
    out_w = w // factor_x
    cropped = a[: out_h * factor_y, : out_w * factor_x]
    valid = valid_mask(cropped, nodata)
    lin = np.zeros_like(cropped)
    lin[valid] = mag_to_linear(cropped[valid])
    # Zero invalid so sum only counts valid; count separately
    blocks_lin = lin.reshape(out_h, factor_y, out_w, factor_x)
    blocks_valid = valid.reshape(out_h, factor_y, out_w, factor_x)
    sum_lin = blocks_lin.sum(axis=(1, 3))
    count = blocks_valid.sum(axis=(1, 3)).astype(np.float64)
    out = np.full((out_h, out_w), nodata, dtype=np.float32)
    ok = count > 0
    mean_lin = np.zeros_like(sum_lin)
    mean_lin[ok] = sum_lin[ok] / count[ok]
    with np.errstate(divide="ignore", invalid="ignore"):
        mag = linear_to_mag(mean_lin)
    out[ok] = mag[ok].astype(np.float32)
    return out


def block_reduce_vectorized_mag(
    arr: np.ndarray,
    factor_y: int,
    factor_x: int,
    nodata: float = DEFAULT_NODATA,
) -> np.ndarray:
    """Vectorized direct magnitude mean (baseline)."""
    a = np.asarray(arr, dtype=np.float64)
    h, w = a.shape
    out_h = h // factor_y
    out_w = w // factor_x
    cropped = a[: out_h * factor_y, : out_w * factor_x]
    valid = valid_mask(cropped, nodata)
    masked = np.where(valid, cropped, 0.0)
    blocks = masked.reshape(out_h, factor_y, out_w, factor_x)
    blocks_valid = valid.reshape(out_h, factor_y, out_w, factor_x)
    sum_m = blocks.sum(axis=(1, 3))
    count = blocks_valid.sum(axis=(1, 3)).astype(np.float64)
    out = np.full((out_h, out_w), nodata, dtype=np.float32)
    ok = count > 0
    out[ok] = (sum_m[ok] / count[ok]).astype(np.float32)
    return out
