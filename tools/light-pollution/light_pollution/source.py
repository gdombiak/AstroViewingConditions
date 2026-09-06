"""Source GeoTIFF inspection, validation, and streaming scans."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

from .grid import GeoGrid
from .nodata import DEFAULT_NODATA, valid_mask


EXPECTED = {
    "width": 43200,
    "height": 16801,
    "dtype": "Float32",
    "pixel_size": 1.0 / 120.0,
    "origin_lon": -180.0,
    "origin_lat": 75.0,
    "nodata_approx": 9.96921e36,
}


def require_osgeo():
    try:
        from osgeo import gdal  # noqa: F401
        return True
    except ImportError as e:
        raise RuntimeError(
            "Cannot import osgeo (GDAL Python bindings).\n"
            "Use Homebrew Python: /opt/homebrew/bin/python3\n"
            "Verify: python3 -c \"from osgeo import gdal; print(gdal.__version__)\"\n"
            "If needed, set PYTHONPATH to Homebrew GDAL site-packages.\n"
            f"Original error: {e}"
        ) from e


def gdal_version() -> str:
    require_osgeo()
    from osgeo import gdal
    return gdal.VersionInfo("RELEASE_NAME")


def file_sha256(path: Path, chunk: int = 8 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def open_dataset(path: Path):
    require_osgeo()
    from osgeo import gdal
    gdal.UseExceptions()
    ds = gdal.Open(str(path))
    if ds is None:
        raise RuntimeError(f"Failed to open GeoTIFF: {path}")
    return ds


def inspect_source(path: Path, compute_sha256: bool = True) -> dict[str, Any]:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"Source GeoTIFF not found: {path}")

    ds = open_dataset(path)
    band = ds.GetRasterBand(1)
    gt = ds.GetGeoTransform()
    from osgeo import gdal
    dtype = gdal.GetDataTypeName(band.DataType)
    nodata = band.GetNoDataValue()
    proj = ds.GetProjection()
    size_bytes = path.stat().st_size

    meta = {
        "path": str(path.resolve()),
        "name": path.name,
        "size_bytes": size_bytes,
        "gdal_version": gdal_version(),
        "inspected_at": datetime.now(timezone.utc).isoformat(),
        "width": ds.RasterXSize,
        "height": ds.RasterYSize,
        "band_count": ds.RasterCount,
        "dtype": dtype,
        "nodata": nodata,
        "geotransform": list(gt),
        "projection_wkt_head": (proj or "")[:200],
        "block_size": list(band.GetBlockSize()),
        "metadata": dict(ds.GetMetadata()),
        "band_metadata": dict(band.GetMetadata()),
        "unit_type": band.GetUnitType(),
    }
    if compute_sha256:
        print("Computing SHA-256 of source (may take a minute)...")
        meta["sha256"] = file_sha256(path)
    else:
        meta["sha256"] = None

    # Coverage checks
    meta["validation"] = validate_source_meta(meta)
    return meta


def validate_source_meta(meta: dict[str, Any]) -> dict[str, Any]:
    issues = []
    warnings = []
    if meta["width"] != EXPECTED["width"] or meta["height"] != EXPECTED["height"]:
        issues.append(
            f"Unexpected size {meta['width']}x{meta['height']}; "
            f"expected {EXPECTED['width']}x{EXPECTED['height']}"
        )
    if meta["dtype"] != EXPECTED["dtype"]:
        issues.append(f"Unexpected dtype {meta['dtype']}; expected {EXPECTED['dtype']}")
    gt = meta["geotransform"]
    if abs(gt[0] - EXPECTED["origin_lon"]) > 1e-9 or abs(gt[3] - EXPECTED["origin_lat"]) > 1e-9:
        issues.append(f"Unexpected origin {gt[0]}, {gt[3]}")
    if abs(abs(gt[1]) - EXPECTED["pixel_size"]) > 1e-9 or abs(abs(gt[5]) - EXPECTED["pixel_size"]) > 1e-9:
        issues.append(f"Unexpected pixel size {gt[1]}, {gt[5]}")
    if gt[5] >= 0:
        issues.append("Expected north-up raster (negative pixel height)")
    nd = meta["nodata"]
    if nd is None or abs(float(nd)) < 1e30:
        warnings.append(f"Unexpected NoData value: {nd}")
    if meta["band_count"] != 1:
        issues.append(f"Expected 1 band, got {meta['band_count']}")
    return {
        "ok": len(issues) == 0,
        "issues": issues,
        "warnings": warnings,
    }


def grid_from_source(path: Path) -> GeoGrid:
    ds = open_dataset(path)
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue()
    if nodata is None:
        nodata = DEFAULT_NODATA
    return GeoGrid.from_geotransform(
        ds.GetGeoTransform(),
        ds.RasterXSize,
        ds.RasterYSize,
        float(nodata),
    )


def streaming_global_minmax(
    path: Path,
    row_block: int = 64,
) -> dict[str, Any]:
    """Exact streaming min/max over valid cells (no full-array load)."""
    ds = open_dataset(path)
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue()
    if nodata is None:
        nodata = DEFAULT_NODATA
    w, h = ds.RasterXSize, ds.RasterYSize
    vmin = np.inf
    vmax = -np.inf
    n_valid = 0
    n_nodata = 0
    for y0 in range(0, h, row_block):
        rows = min(row_block, h - y0)
        arr = band.ReadAsArray(0, y0, w, rows)
        m = valid_mask(arr, float(nodata))
        n_valid += int(np.sum(m))
        n_nodata += int(np.sum(~m))
        if np.any(m):
            vmin = min(vmin, float(arr[m].min()))
            vmax = max(vmax, float(arr[m].max()))
        if (y0 // row_block) % 20 == 0:
            print(f"  min/max scan rows {y0}/{h}...")
    return {
        "min": None if n_valid == 0 else vmin,
        "max": None if n_valid == 0 else vmax,
        "n_valid": n_valid,
        "n_nodata": n_nodata,
        "width": w,
        "height": h,
    }


def save_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, default=str) + "\n")
