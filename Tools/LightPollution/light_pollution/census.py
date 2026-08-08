"""Streaming full-world tile census for quantized adaptive formats."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

from .adaptive_tiles import AdaptiveConfig, LEVELS, select_level_for_block
from .nodata import DEFAULT_NODATA
from .paths import OUTPUT
from .quantize import UInt8Params, UInt16Params
from .report import write_json
from .sizes import bytes_to_mib
from .source import open_dataset, require_osgeo


def census_adaptive_quantized(
    source: Path,
    budgets: list[float] | None = None,
    storages: list[str] | None = None,
    tile_cells: int = 60,
    pristine_default: float = 22.0,
    u8: UInt8Params | None = None,
    u16: UInt16Params | None = None,
    source_pixel_deg: float = 1.0 / 120.0,
    out_path: Path | None = None,
) -> dict[str, Any]:
    """Stream source; for each tile pick smallest level under each budget/storage.

    Does not write global candidate rasters.
    """
    require_osgeo()
    budgets = budgets or [0.05, 0.10, 0.20]
    storages = storages or ["uint8", "uint16"]
    u8 = u8 or UInt8Params()
    u16 = u16 or UInt16Params()

    ds = open_dataset(source)
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue()
    if nodata is None:
        nodata = DEFAULT_NODATA
    w, h = ds.RasterXSize, ds.RasterYSize

    # results[storage][budget] = counters
    results: dict[str, dict[str, Any]] = {}
    for st in storages:
        results[st] = {}
        for b in budgets:
            results[st][str(b)] = {
                "level_counts": {k: 0 for k in LEVELS},
                "payload_bytes": 0,
                "n_tiles": 0,
                "tile_max_ae_samples": [],  # subsampled for distribution
            }

    n_tiles_total = 0
    print(f"Adaptive quantized census {w}x{h} tile={tile_cells} budgets={budgets} storage={storages}")
    for r0 in range(0, h, tile_cells):
        rows = min(tile_cells, h - r0)
        strip = band.ReadAsArray(0, r0, w, rows)
        for c0 in range(0, w, tile_cells):
            cols = min(tile_cells, w - c0)
            block = strip[:, c0 : c0 + cols].astype(np.float32)
            n_tiles_total += 1
            for st in storages:
                for budget in budgets:
                    cfg = AdaptiveConfig(
                        tile_source_cells=tile_cells,
                        error_budget=budget,
                        pristine_default=pristine_default,
                        nodata=float(nodata),
                        source_pixel_deg=source_pixel_deg,
                        storage=st,  # type: ignore
                        u8=u8,
                        u16=u16,
                    )
                    level, nbytes, max_ae = select_level_for_block(block, cfg)
                    slot = results[st][str(budget)]
                    slot["level_counts"][level] = slot["level_counts"].get(level, 0) + 1
                    slot["payload_bytes"] += nbytes
                    slot["n_tiles"] += 1
                    # keep every 200th max_ae for distribution approx
                    if max_ae is not None and (n_tiles_total % 200 == 0):
                        slot["tile_max_ae_samples"].append(max_ae)
        if (r0 // tile_cells) % 20 == 0:
            print(f"  census row {r0}/{h} tiles={n_tiles_total}")

    # finalize size estimates
    for st in storages:
        for budget in budgets:
            slot = results[st][str(budget)]
            n = slot["n_tiles"]
            index_bytes = 64 + n * 16
            metadata_bytes = 512
            # edge-tile flag already reflected in variable tile shapes via nbytes
            total = slot["payload_bytes"] + index_bytes + metadata_bytes
            samples = slot.pop("tile_max_ae_samples")
            slot["index_bytes"] = index_bytes
            slot["metadata_bytes"] = metadata_bytes
            slot["total_bytes"] = total
            slot["total_mib"] = bytes_to_mib(total)
            slot["payload_mib"] = bytes_to_mib(slot["payload_bytes"])
            if samples:
                slot["sampled_tile_max_ae_p95"] = float(np.percentile(samples, 95))
                slot["sampled_tile_max_ae_max"] = float(np.max(samples))
            else:
                slot["sampled_tile_max_ae_p95"] = None
                slot["sampled_tile_max_ae_max"] = None
            slot["level_fractions"] = {
                k: (v / n if n else 0) for k, v in slot["level_counts"].items()
            }

    out = {
        "kind": "adaptive_quantized_world_census",
        "reliability": "census_derived",
        "source_width": w,
        "source_height": h,
        "tile_cells": tile_cells,
        "budgets": budgets,
        "storages": storages,
        "pristine_default": pristine_default,
        "n_tiles": n_tiles_total,
        "results": results,
        "u8": (u8 or UInt8Params()).to_dict(),
        "u16": (u16 or UInt16Params()).to_dict(),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "note": (
            "Per-tile smallest level under max-AE budget with quantized storage. "
            "No global candidate rasters written. Includes level tags, offsets, "
            "edge tiles (variable h/w), packed masks for mixed default/constant, metadata."
        ),
    }
    out_path = out_path or (OUTPUT / "world_adaptive_quant_census.json")
    write_json(out_path, out)
    print("Census written to", out_path)
    return out


def census_on_array(
    arr: np.ndarray,
    budgets: list[float],
    storage: str = "uint8",
    tile_cells: int = 8,
    pristine_default: float = 22.0,
    nodata: float = DEFAULT_NODATA,
    u8: UInt8Params | None = None,
    u16: UInt16Params | None = None,
    source_pixel_deg: float = 1.0 / 120.0,
) -> dict[str, Any]:
    """Census helper for synthetic tests (in-memory array)."""
    h, w = arr.shape
    out: dict[str, Any] = {}
    for budget in budgets:
        cfg = AdaptiveConfig(
            tile_source_cells=tile_cells,
            error_budget=budget,
            pristine_default=pristine_default,
            nodata=nodata,
            source_pixel_deg=source_pixel_deg,
            storage=storage,  # type: ignore
            u8=u8 or UInt8Params(),
            u16=u16 or UInt16Params(),
        )
        counts = {k: 0 for k in LEVELS}
        payload = 0
        n = 0
        for r0 in range(0, h, tile_cells):
            for c0 in range(0, w, tile_cells):
                block = arr[r0 : min(r0 + tile_cells, h), c0 : min(c0 + tile_cells, w)]
                level, nbytes, _ = select_level_for_block(block, cfg)
                counts[level] = counts.get(level, 0) + 1
                payload += nbytes
                n += 1
        out[str(budget)] = {
            "level_counts": counts,
            "payload_bytes": payload,
            "n_tiles": n,
            "total_bytes": payload + 64 + n * 16 + 512,
        }
    return out
