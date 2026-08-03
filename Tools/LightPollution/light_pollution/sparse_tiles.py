"""Fixed-resolution sparse tile encoding and reconstruction.

Tile modes:
  - all_nodata: every cell is NoData
  - default_pristine: all valid cells within tolerance of pristine_default
  - constant: valid cells within range tolerance of a constant
  - delta: int8 residuals (float storage path only)
  - full: dense payload (float32 or quantized codes)

Mixed valid/NoData tiles persist a packed bit mask (np.packbits) and decode it.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

import numpy as np

from .masks import mask_payload_bytes, pack_nodata_mask, packed_mask_nbytes, unpack_nodata_mask
from .nodata import DEFAULT_NODATA, is_nodata
from .quantize import (
    UInt8Params,
    UInt16Params,
    dequantize_uint8,
    dequantize_uint16,
    quantize_uint8,
    quantize_uint16,
)

MODE_HEADER = 1
Storage = Literal["float32", "uint8", "uint16"]


@dataclass
class SparseTileConfig:
    tile_h: int = 32
    tile_w: int = 32
    tolerance: float = 0.05
    pristine_default: float = 22.0
    nodata: float = DEFAULT_NODATA
    storage: Storage = "float32"
    u8: UInt8Params | None = None
    u16: UInt16Params | None = None


def _tile_slices(h: int, w: int, th: int, tw: int):
    for r0 in range(0, h, th):
        for c0 in range(0, w, tw):
            r1 = min(r0 + th, h)
            c1 = min(c0 + tw, w)
            yield r0, r1, c0, c1


def _bytes_per_value(storage: Storage) -> int:
    if storage == "float32":
        return 4
    if storage == "uint8":
        return 1
    if storage == "uint16":
        return 2
    raise ValueError(storage)


def _store_scalar(value: float, cfg: SparseTileConfig) -> tuple[Any, int]:
    """Return (stored_value, nbytes) for a scalar magnitude."""
    if cfg.storage == "float32":
        return float(value), 4
    arr = np.array([[value]], dtype=np.float32)
    if cfg.storage == "uint8":
        codes, _ = quantize_uint8(arr, cfg.u8 or UInt8Params(), cfg.nodata)
        return int(codes[0, 0]), 1
    codes, _ = quantize_uint16(arr, cfg.u16 or UInt16Params(), cfg.nodata)
    return int(codes[0, 0]), 2


def _load_scalar(stored: Any, cfg: SparseTileConfig) -> float:
    if cfg.storage == "float32":
        return float(stored)
    arr = np.array([[stored]])
    if cfg.storage == "uint8":
        return float(dequantize_uint8(arr.astype(np.uint8), cfg.u8 or UInt8Params(), cfg.nodata)[0, 0])
    return float(dequantize_uint16(arr.astype(np.uint16), cfg.u16 or UInt16Params(), cfg.nodata)[0, 0])


def _store_block(block: np.ndarray, cfg: SparseTileConfig) -> tuple[np.ndarray, int]:
    n = int(block.size)
    bpc = _bytes_per_value(cfg.storage)
    if cfg.storage == "float32":
        return block.astype(np.float32).copy(), n * bpc
    if cfg.storage == "uint8":
        codes, _ = quantize_uint8(block, cfg.u8 or UInt8Params(), cfg.nodata)
        return codes, n * bpc
    codes, _ = quantize_uint16(block, cfg.u16 or UInt16Params(), cfg.nodata)
    return codes, n * bpc


def _load_block(stored: np.ndarray, cfg: SparseTileConfig) -> np.ndarray:
    if cfg.storage == "float32":
        return stored.astype(np.float32)
    if cfg.storage == "uint8":
        return dequantize_uint8(stored, cfg.u8 or UInt8Params(), cfg.nodata)
    return dequantize_uint16(stored, cfg.u16 or UInt16Params(), cfg.nodata)


def encode_sparse(
    arr: np.ndarray,
    cfg: SparseTileConfig,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    a = np.asarray(arr, dtype=np.float32)
    h, w = a.shape
    tiles: list[dict[str, Any]] = []
    counts = {k: 0 for k in ("all_nodata", "default_pristine", "constant", "delta", "full")}
    payload_bytes = 0
    n_tiles = 0
    accounted_mask_bytes = 0

    for r0, r1, c0, c1 in _tile_slices(h, w, cfg.tile_h, cfg.tile_w):
        n_tiles += 1
        block = a[r0:r1, c0:c1]
        th, tw = block.shape
        n_cells = th * tw
        inv = is_nodata(block, cfg.nodata)
        n_valid = int(np.sum(~inv))
        mixed = bool(np.any(inv) and n_valid > 0)

        if n_valid == 0:
            tile = {"mode": "all_nodata", "r0": r0, "c0": c0, "h": th, "w": tw}
            payload_bytes += MODE_HEADER
            counts["all_nodata"] += 1
            tiles.append(tile)
            continue

        vals = block[~inv]
        vmin = float(vals.min())
        vmax = float(vals.max())
        # Midpoint minimizes max AE for constant approximation
        vmid = 0.5 * (vmin + vmax)

        if np.all(np.abs(vals - cfg.pristine_default) <= cfg.tolerance):
            stored, sn = _store_scalar(cfg.pristine_default, cfg)
            tile: dict[str, Any] = {
                "mode": "default_pristine",
                "r0": r0,
                "c0": c0,
                "h": th,
                "w": tw,
                "stored_value": stored,
            }
            nbytes = MODE_HEADER + sn
            if mixed:
                packed = pack_nodata_mask(inv)
                tile["nodata_mask_packed"] = packed
                mb = len(packed)
                assert mb == packed_mask_nbytes(n_cells)
                nbytes += mb
                accounted_mask_bytes += mb
            payload_bytes += nbytes
            counts["default_pristine"] += 1
            tiles.append(tile)
            continue

        if (vmax - vmin) <= cfg.tolerance:
            stored, sn = _store_scalar(vmid, cfg)
            tile = {
                "mode": "constant",
                "r0": r0,
                "c0": c0,
                "h": th,
                "w": tw,
                "stored_value": stored,
            }
            nbytes = MODE_HEADER + sn
            if mixed:
                packed = pack_nodata_mask(inv)
                tile["nodata_mask_packed"] = packed
                mb = len(packed)
                assert mb == packed_mask_nbytes(n_cells)
                nbytes += mb
                accounted_mask_bytes += mb
            payload_bytes += nbytes
            counts["constant"] += 1
            tiles.append(tile)
            continue

        # delta only for float32 storage (optional path)
        if cfg.storage == "float32":
            base = float(np.round(vmid, 2))
            residuals = vals - base
            q = np.rint(residuals / 0.01)
            if (
                np.all(q >= -128)
                and np.all(q <= 127)
                and float(np.max(np.abs(residuals))) <= max(cfg.tolerance, 0.5)
            ):
                recon_valid = base + np.clip(q, -128, 127) * 0.01
                if float(np.max(np.abs(recon_valid - vals))) <= cfg.tolerance:
                    full_res = np.zeros(block.shape, dtype=np.int8)
                    full_res[~inv] = q.astype(np.int8)
                    tile = {
                        "mode": "delta",
                        "r0": r0,
                        "c0": c0,
                        "h": th,
                        "w": tw,
                        "base": base,
                        "residuals": full_res,
                    }
                    nbytes = MODE_HEADER + 4 + n_cells  # base float + int8 residuals
                    if mixed:
                        packed = pack_nodata_mask(inv)
                        tile["nodata_mask_packed"] = packed
                        mb = len(packed)
                        nbytes += mb
                        accounted_mask_bytes += mb
                    payload_bytes += nbytes
                    counts["delta"] += 1
                    tiles.append(tile)
                    continue

        stored_block, bn = _store_block(block, cfg)
        tile = {
            "mode": "full",
            "r0": r0,
            "c0": c0,
            "h": th,
            "w": tw,
            "data": stored_block,
        }
        # full includes NoData via quant nodata codes or float nodata — no separate mask
        payload_bytes += MODE_HEADER + bn
        counts["full"] += 1
        tiles.append(tile)

    index_bytes = 32 + n_tiles * 12
    metadata_bytes = 256
    stats = {
        "n_tiles": n_tiles,
        "tile_h": cfg.tile_h,
        "tile_w": cfg.tile_w,
        "tolerance": cfg.tolerance,
        "pristine_default": cfg.pristine_default,
        "storage": cfg.storage,
        "mask_encoding": "np.packbits",
        "mode_counts": counts,
        "payload_bytes": payload_bytes,
        "index_bytes": index_bytes,
        "metadata_bytes": metadata_bytes,
        "mask_bytes_accounted": accounted_mask_bytes,
        "total_estimated_bytes": payload_bytes + index_bytes + metadata_bytes,
        "shape": [h, w],
        "bytes_per_value": _bytes_per_value(cfg.storage),
    }
    return tiles, stats


def decode_sparse(
    tiles: list[dict[str, Any]],
    shape: tuple[int, int],
    cfg: SparseTileConfig,
) -> np.ndarray:
    h, w = shape
    out = np.full((h, w), cfg.nodata, dtype=np.float32)
    for t in tiles:
        r0, c0 = t["r0"], t["c0"]
        th, tw = t["h"], t["w"]
        mode = t["mode"]
        if mode == "all_nodata":
            out[r0 : r0 + th, c0 : c0 + tw] = cfg.nodata
            continue

        if mode in ("default_pristine", "constant"):
            val = _load_scalar(t["stored_value"], cfg)
            block = np.full((th, tw), val, dtype=np.float32)
            if "nodata_mask_packed" in t:
                inv = unpack_nodata_mask(t["nodata_mask_packed"], (th, tw))
                block[inv] = cfg.nodata
            out[r0 : r0 + th, c0 : c0 + tw] = block
            continue

        if mode == "delta":
            block = np.full((th, tw), cfg.nodata, dtype=np.float32)
            res = t["residuals"].astype(np.float64) * 0.01 + t["base"]
            if "nodata_mask_packed" in t:
                inv = unpack_nodata_mask(t["nodata_mask_packed"], (th, tw))
            else:
                inv = np.zeros((th, tw), dtype=bool)
            block[~inv] = res[~inv].astype(np.float32)
            # residual zeros on nodata positions are ignored via mask
            out[r0 : r0 + th, c0 : c0 + tw] = block
            continue

        if mode == "full":
            out[r0 : r0 + th, c0 : c0 + tw] = _load_block(t["data"], cfg)
            continue

        raise ValueError(mode)
    return out
