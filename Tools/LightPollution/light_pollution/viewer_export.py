"""Export PNG + float32 + meta for the local browser viewer."""

from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Any

import numpy as np

from .nodata import is_nodata


def _value_to_rgb(mag: np.ndarray, vmin: float, vmax: float, nodata_mask: np.ndarray) -> np.ndarray:
    """Simple dark-sky colormap: bright sky = yellow/white, dark = deep blue/black."""
    t = np.clip((mag - vmin) / max(vmax - vmin, 1e-6), 0, 1)
    # invert so darker sky (high mag) -> dark pixels
    t = 1.0 - t
    r = np.clip(255 * np.minimum(1.5 * t, 1.0), 0, 255).astype(np.uint8)
    g = np.clip(255 * np.minimum(1.2 * t, 1.0) * (0.6 + 0.4 * t), 0, 255).astype(np.uint8)
    b = np.clip(255 * (0.2 + 0.8 * (1.0 - t)), 0, 255).astype(np.uint8)
    # Actually use a clearer ramp: low mag (bright pollution) = yellow, high mag = navy
    t = np.clip((mag - vmin) / max(vmax - vmin, 1e-6), 0, 1)
    # t=0 bright polluted, t=1 dark
    r = (255 * (1 - t) + 10 * t).astype(np.uint8)
    g = (220 * (1 - t) + 20 * t).astype(np.uint8)
    b = (50 * (1 - t) + 80 * t).astype(np.uint8)
    rgb = np.stack([r, g, b], axis=-1)
    rgb[nodata_mask] = [40, 40, 40]
    return rgb


def _error_to_rgb(err: np.ndarray, emax: float, nodata_mask: np.ndarray, signed: bool) -> np.ndarray:
    rgb = np.zeros(err.shape + (3,), dtype=np.uint8)
    if signed:
        t = np.clip(err / emax, -1, 1)
        # blue = candidate darker (positive err if larger mag), red = brighter
        pos = t > 0
        neg = t < 0
        rgb[pos, 2] = (255 * t[pos]).astype(np.uint8)
        rgb[neg, 0] = (255 * (-t[neg])).astype(np.uint8)
        mid = ~pos & ~neg
        rgb[mid] = [200, 200, 200]
    else:
        t = np.clip(np.abs(err) / emax, 0, 1)
        rgb[..., 0] = (255 * t).astype(np.uint8)
        rgb[..., 1] = (255 * (1 - t)).astype(np.uint8)
        rgb[..., 2] = 40
    rgb[nodata_mask] = [40, 40, 40]
    return rgb


def write_png_rgb(path: Path, rgb: np.ndarray) -> None:
    """Write RGB PNG without external deps (minimal PNG encoder)."""
    import zlib

    h, w, _ = rgb.shape
    raw = b""
    for row in range(h):
        raw += b"\x00" + rgb[row].tobytes()
    compressor = zlib.compress(raw, 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressor) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def export_raster_for_viewer(
    out_dir: Path,
    name: str,
    arr: np.ndarray,
    grid_dict: dict[str, Any],
    vmin: float,
    vmax: float,
    nodata: float,
) -> dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    a = np.asarray(arr, dtype=np.float32)
    nd = is_nodata(a, nodata)
    rgb = _value_to_rgb(a, vmin, vmax, nd)
    png_path = out_dir / f"{name}.png"
    f32_path = out_dir / f"{name}.f32"
    meta_path = out_dir / f"{name}.meta.json"
    write_png_rgb(png_path, rgb)
    # row-major float32
    f32_path.write_bytes(a.astype("<f4").tobytes())
    meta = {
        "name": name,
        "shape": list(a.shape),
        "grid": grid_dict,
        "vmin": vmin,
        "vmax": vmax,
        "nodata": nodata,
        "png": png_path.name,
        "f32": f32_path.name,
        "dtype": "float32_le",
    }
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    return meta


def export_error_png(
    out_dir: Path,
    name: str,
    original: np.ndarray,
    candidate: np.ndarray,
    nodata: float,
    emax: float = 0.3,
    signed: bool = True,
) -> str:
    o = np.asarray(original, dtype=np.float32)
    c = np.asarray(candidate, dtype=np.float32)
    nd = is_nodata(o, nodata) | is_nodata(c, nodata)
    err = np.zeros_like(o)
    both = ~nd
    err[both] = c[both] - o[both]
    rgb = _error_to_rgb(err, emax, nd, signed=signed)
    fname = f"{name}.png"
    write_png_rgb(out_dir / fname, rgb)
    return fname
