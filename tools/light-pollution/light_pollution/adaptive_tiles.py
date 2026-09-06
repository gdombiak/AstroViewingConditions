"""Adaptive multi-resolution tiles on a fixed source-aligned tiling scheme.

Each tile selects the smallest representation satisfying a **maximum absolute
error** budget on valid cells (required). P95/P99 are diagnostic only.

Constant approximation uses the min/max **midpoint** to minimize max error.
This is distinct from linear-brightness spatial aggregation used for multi-cell
resolution levels.

Storage may be float32 (baseline), uint8, or uint16 (production-relevant).
Quantization is applied to stored values and included in reconstruction error.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

import numpy as np

from .brightness import block_reduce_vectorized_linear
from .masks import pack_nodata_mask, packed_mask_nbytes
from .nodata import DEFAULT_NODATA, is_nodata
from .quantize import (
    UInt8Params,
    UInt16Params,
    dequantize_uint8,
    dequantize_uint16,
    quantize_uint8,
    quantize_uint16,
)
from .reconstruct import reconstruct_uniform_integer_factor

LEVELS = (
    "all_nodata",
    "default_pristine",
    "constant",
    "res_0.1",
    "res_0.05",
    "res_0.025",
    "full_native",
)

Storage = Literal["float32", "uint8", "uint16"]


@dataclass
class AdaptiveConfig:
    tile_source_cells: int = 60
    error_budget: float = 0.05
    pristine_default: float = 22.0
    nodata: float = DEFAULT_NODATA
    source_pixel_deg: float = 1.0 / 120.0
    storage: Storage = "float32"
    u8: UInt8Params | None = None
    u16: UInt16Params | None = None


def _max_ae(original: np.ndarray, candidate: np.ndarray, nodata: float) -> float | None:
    o_nd = is_nodata(original, nodata)
    c_nd = is_nodata(candidate, nodata)
    both = ~o_nd & ~c_nd
    if not np.any(both):
        # nodata pattern must match for zero error
        if np.array_equal(o_nd, c_nd):
            return 0.0
        return None
    # also penalize nodata disagreement as infinite failure
    if not np.array_equal(o_nd, c_nd):
        return float("inf")
    return float(np.max(np.abs(candidate[both] - original[both])))


def _p_ae(original: np.ndarray, candidate: np.ndarray, nodata: float, q: float) -> float | None:
    o_nd = is_nodata(original, nodata)
    c_nd = is_nodata(candidate, nodata)
    both = ~o_nd & ~c_nd
    if not np.any(both):
        return 0.0
    return float(np.percentile(np.abs(candidate[both] - original[both]), q))


def constant_midpoint(block: np.ndarray, nodata: float) -> tuple[np.ndarray, float]:
    """Min/max midpoint constant — minimizes max absolute error among constants."""
    inv = is_nodata(block, nodata)
    out = np.full(block.shape, nodata, dtype=np.float32)
    if not np.any(~inv):
        return out, float(nodata)
    vals = block[~inv]
    mid = float(0.5 * (float(vals.min()) + float(vals.max())))
    out[~inv] = mid
    return out, mid


def try_default(block: np.ndarray, default: float, nodata: float) -> np.ndarray:
    inv = is_nodata(block, nodata)
    out = np.full(block.shape, nodata, dtype=np.float32)
    out[~inv] = default
    return out


def reduce_and_up(block: np.ndarray, factor: int, nodata: float) -> np.ndarray:
    h, w = block.shape
    ph = (factor - h % factor) % factor
    pw = (factor - w % factor) % factor
    if ph or pw:
        padded = np.full((h + ph, w + pw), nodata, dtype=np.float32)
        padded[:h, :w] = block
    else:
        padded = block.astype(np.float32, copy=False)
    coarse = block_reduce_vectorized_linear(padded, factor, factor, nodata)
    recon = reconstruct_uniform_integer_factor(coarse, factor, padded.shape, nodata)
    return recon[:h, :w], coarse


def _bytes_per_cell(storage: Storage) -> int:
    return {"float32": 4, "uint8": 1, "uint16": 2}[storage]


def quantize_array(arr: np.ndarray, cfg: AdaptiveConfig) -> np.ndarray:
    if cfg.storage == "float32":
        return arr.astype(np.float32)
    if cfg.storage == "uint8":
        codes, _ = quantize_uint8(arr, cfg.u8 or UInt8Params(), cfg.nodata)
        return dequantize_uint8(codes, cfg.u8 or UInt8Params(), cfg.nodata)
    codes, _ = quantize_uint16(arr, cfg.u16 or UInt16Params(), cfg.nodata)
    return dequantize_uint16(codes, cfg.u16 or UInt16Params(), cfg.nodata)


def quantize_scalar_roundtrip(value: float, cfg: AdaptiveConfig) -> float:
    return float(quantize_array(np.array([[value]], dtype=np.float32), cfg)[0, 0])


def payload_for_level(
    level: str,
    th: int,
    tw: int,
    factor: int | None,
    mixed_nodata: bool,
    storage: Storage,
) -> int:
    """Wire-size estimate for a tile level."""
    bpc = _bytes_per_cell(storage)
    header = 1  # level tag
    mask_b = packed_mask_nbytes(th * tw) if mixed_nodata and level in (
        "default_pristine",
        "constant",
    ) else 0
    if level == "all_nodata":
        return header
    if level in ("default_pristine", "constant"):
        return header + bpc + mask_b  # scalar + optional mask
    if level.startswith("res_") or level == "full_native":
        if level == "full_native":
            cells = th * tw
        else:
            assert factor is not None
            # floor policy on padded? stored coarse uses ceil of tile after pad to factor
            ch = int(np.ceil(th / factor))
            cw = int(np.ceil(tw / factor))
            cells = ch * cw
        return header + cells * bpc
    raise ValueError(level)


def encode_adaptive(
    arr: np.ndarray,
    cfg: AdaptiveConfig,
) -> tuple[list[dict[str, Any]], np.ndarray, dict[str, Any]]:
    a = np.asarray(arr, dtype=np.float32)
    h, w = a.shape
    ts = cfg.tile_source_cells
    recon_full = np.full_like(a, cfg.nodata)
    tiles: list[dict[str, Any]] = []
    level_counts: dict[str, int] = {k: 0 for k in LEVELS}
    payload_bytes = 0
    tile_errors: list[dict[str, Any]] = []

    factor_0_1 = max(1, int(round(0.1 / cfg.source_pixel_deg)))
    factor_0_05 = max(1, int(round(0.05 / cfg.source_pixel_deg)))
    factor_0_025 = max(1, int(round(0.025 / cfg.source_pixel_deg)))
    factors = {"res_0.1": factor_0_1, "res_0.05": factor_0_05, "res_0.025": factor_0_025}

    n_tiles = 0
    for r0 in range(0, h, ts):
        for c0 in range(0, w, ts):
            r1 = min(r0 + ts, h)
            c1 = min(c0 + ts, w)
            block = a[r0:r1, c0:c1]
            th, tw = block.shape
            n_tiles += 1
            inv = is_nodata(block, cfg.nodata)
            n_valid = int(np.sum(~inv))
            mixed = bool(np.any(inv) and n_valid > 0)

            chosen = None
            recon = None
            extra: dict[str, Any] = {}
            nbytes = 0

            if n_valid == 0:
                chosen = "all_nodata"
                recon = np.full_like(block, cfg.nodata)
                nbytes = payload_for_level("all_nodata", th, tw, None, False, cfg.storage)
            else:
                candidates: list[tuple[str, np.ndarray, int, dict]] = []

                d_raw = try_default(block, cfg.pristine_default, cfg.nodata)
                d_q = quantize_array(d_raw, cfg)
                # preserve nodata exactly after quantize
                d_q = np.where(inv, cfg.nodata, d_q)
                candidates.append((
                    "default_pristine",
                    d_q,
                    payload_for_level("default_pristine", th, tw, None, mixed, cfg.storage),
                    {},
                ))

                c_raw, cval = constant_midpoint(block, cfg.nodata)
                c_q = quantize_array(c_raw, cfg)
                c_q = np.where(inv, cfg.nodata, c_q)
                candidates.append((
                    "constant",
                    c_q,
                    payload_for_level("constant", th, tw, None, mixed, cfg.storage),
                    {"value": cval, "value_quantized": float(c_q[~inv][0]) if n_valid else None},
                ))

                for name, fac in factors.items():
                    r_up, coarse = reduce_and_up(block, fac, cfg.nodata)
                    # quantize stored coarse then upsample for fair recon
                    coarse_q = quantize_array(coarse, cfg)
                    r_q = reconstruct_uniform_integer_factor(
                        coarse_q, fac, (
                            coarse.shape[0] * fac,
                            coarse.shape[1] * fac,
                        ), cfg.nodata,
                    )[:th, :tw]
                    # If pad was used, reduce_and_up already truncated; match shapes
                    if r_q.shape != block.shape:
                        tmp = np.full(block.shape, cfg.nodata, dtype=np.float32)
                        tmp[: r_q.shape[0], : r_q.shape[1]] = r_q
                        r_q = tmp
                    candidates.append((
                        name,
                        r_q,
                        payload_for_level(name, th, tw, fac, False, cfg.storage),
                        {"factor": fac},
                    ))

                native_q = quantize_array(block, cfg)
                candidates.append((
                    "full_native",
                    native_q,
                    payload_for_level("full_native", th, tw, None, False, cfg.storage),
                    {},
                ))

                for name, r, nb, meta in candidates:
                    mae = _max_ae(block, r, cfg.nodata)
                    if mae is not None and mae <= cfg.error_budget:
                        chosen = name
                        recon = r
                        nbytes = nb
                        extra = meta
                        break
                if chosen is None:
                    chosen = "full_native"
                    recon = quantize_array(block, cfg)
                    nbytes = payload_for_level("full_native", th, tw, None, False, cfg.storage)

            assert recon is not None and chosen is not None
            recon_full[r0:r1, c0:c1] = recon
            level_counts[chosen] = level_counts.get(chosen, 0) + 1
            payload_bytes += nbytes
            max_ae = _max_ae(block, recon, cfg.nodata)
            if max_ae == float("inf"):
                max_ae = 999.0
            tile_errors.append({
                "r0": r0,
                "c0": c0,
                "h": th,
                "w": tw,
                "level": chosen,
                "max_ae": max_ae,
                "p95_ae": _p_ae(block, recon, cfg.nodata, 95),
                "p99_ae": _p_ae(block, recon, cfg.nodata, 99),
                "n_valid": n_valid,
                "payload_bytes": nbytes,
            })
            tiles.append({"r0": r0, "c0": c0, "h": th, "w": tw, "level": chosen, **extra})

    index_bytes = 64 + n_tiles * 16
    metadata_bytes = 512
    max_aes = [t["max_ae"] for t in tile_errors if t["max_ae"] is not None]
    stats = {
        "n_tiles": n_tiles,
        "tile_source_cells": ts,
        "error_budget_max_ae": cfg.error_budget,
        "acceptance_constraint": "max_absolute_error",
        "constant_method": "minmax_midpoint",
        "constant_note": (
            "Midpoint minimizes max AE for constant tiles; linear-brightness mean "
            "is used only for multi-cell spatial aggregation levels."
        ),
        "storage": cfg.storage,
        "pristine_default": cfg.pristine_default,
        "level_counts": level_counts,
        "payload_bytes": payload_bytes,
        "index_bytes": index_bytes,
        "metadata_bytes": metadata_bytes,
        "total_estimated_bytes": payload_bytes + index_bytes + metadata_bytes,
        "tile_errors": tile_errors,
        "per_tile_max_ae_p50": float(np.percentile(max_aes, 50)) if max_aes else None,
        "per_tile_max_ae_p95": float(np.percentile(max_aes, 95)) if max_aes else None,
        "per_tile_max_ae_p99": float(np.percentile(max_aes, 99)) if max_aes else None,
        "per_tile_max_ae_max": max(max_aes) if max_aes else None,
        "factors": {"0.1": factor_0_1, "0.05": factor_0_05, "0.025": factor_0_025},
    }
    return tiles, recon_full, stats


def select_level_for_block(
    block: np.ndarray,
    cfg: AdaptiveConfig,
) -> tuple[str, int, float | None]:
    """Return (level, payload_bytes, max_ae) for census without full encode list."""
    inv = is_nodata(block, cfg.nodata)
    n_valid = int(np.sum(~inv))
    th, tw = block.shape
    mixed = bool(np.any(inv) and n_valid > 0)
    if n_valid == 0:
        return "all_nodata", payload_for_level("all_nodata", th, tw, None, False, cfg.storage), 0.0

    factor_0_1 = max(1, int(round(0.1 / cfg.source_pixel_deg)))
    factor_0_05 = max(1, int(round(0.05 / cfg.source_pixel_deg)))
    factor_0_025 = max(1, int(round(0.025 / cfg.source_pixel_deg)))
    factors = [("res_0.1", factor_0_1), ("res_0.05", factor_0_05), ("res_0.025", factor_0_025)]

    options: list[tuple[str, np.ndarray, int]] = []
    d_q = np.where(inv, cfg.nodata, quantize_array(try_default(block, cfg.pristine_default, cfg.nodata), cfg))
    options.append(("default_pristine", d_q, payload_for_level("default_pristine", th, tw, None, mixed, cfg.storage)))
    c_raw, _ = constant_midpoint(block, cfg.nodata)
    c_q = np.where(inv, cfg.nodata, quantize_array(c_raw, cfg))
    options.append(("constant", c_q, payload_for_level("constant", th, tw, None, mixed, cfg.storage)))
    for name, fac in factors:
        r_up, coarse = reduce_and_up(block, fac, cfg.nodata)
        coarse_q = quantize_array(coarse, cfg)
        r_q = reconstruct_uniform_integer_factor(
            coarse_q, fac, (coarse.shape[0] * fac, coarse.shape[1] * fac), cfg.nodata
        )[:th, :tw]
        if r_q.shape != block.shape:
            tmp = np.full(block.shape, cfg.nodata, dtype=np.float32)
            tmp[: r_q.shape[0], : r_q.shape[1]] = r_q
            r_q = tmp
        options.append((name, r_q, payload_for_level(name, th, tw, fac, False, cfg.storage)))
    native_q = quantize_array(block, cfg)
    options.append(("full_native", native_q, payload_for_level("full_native", th, tw, None, False, cfg.storage)))

    for name, r, nb in options:
        mae = _max_ae(block, r, cfg.nodata)
        if mae is not None and mae <= cfg.error_budget:
            return name, nb, mae if mae != float("inf") else None
    return "full_native", payload_for_level("full_native", th, tw, None, False, cfg.storage), _max_ae(block, native_q, cfg.nodata)
