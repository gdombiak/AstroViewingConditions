"""Oregon (and future region) crop caching."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from .disk import ensure_space, estimate_array_bytes, human_bytes
from .grid import GeoGrid, subgrid, window_for_extent
from .nodata import DEFAULT_NODATA
from .paths import CACHE
from .source import grid_from_source, open_dataset, require_osgeo


def load_region_config(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def crop_cache_paths(region_id: str, cache_dir: Path = CACHE) -> dict[str, Path]:
    d = cache_dir / region_id
    return {
        "dir": d,
        "npy": d / "source_crop.npy",
        "meta": d / "source_crop_meta.json",
        "tiff": d / "source_crop.tiff",
    }


def build_region_crop(
    source_path: Path,
    region: dict[str, Any],
    cache_dir: Path = CACHE,
    force: bool = False,
) -> dict[str, Any]:
    require_osgeo()
    from osgeo import gdal, osr

    gdal.UseExceptions()
    region_id = region["id"]
    paths = crop_cache_paths(region_id, cache_dir)

    if not force and paths["npy"].is_file() and paths["meta"].is_file():
        meta = json.loads(paths["meta"].read_text())
        print(f"Reusing cached crop: {paths['npy']}")
        return meta

    grid = grid_from_source(source_path)
    xoff, yoff, xsize, ysize = window_for_extent(
        grid,
        region["lon_min"],
        region["lon_max"],
        region["lat_min"],
        region["lat_max"],
    )
    if xsize <= 0 or ysize <= 0:
        raise RuntimeError("Region window is empty or outside source coverage")

    needed = estimate_array_bytes((ysize, xsize), 4) * 3  # npy + tiff + headroom
    ensure_space(cache_dir, needed)
    print(
        f"Cropping region {region_id}: window x={xoff} y={yoff} "
        f"{xsize}x{ysize} (~{human_bytes(estimate_array_bytes((ysize, xsize), 4))})"
    )

    ds = open_dataset(source_path)
    band = ds.GetRasterBand(1)
    arr = band.ReadAsArray(xoff, yoff, xsize, ysize).astype(np.float32)
    crop_grid = subgrid(grid, xoff, yoff, xsize, ysize)

    paths["dir"].mkdir(parents=True, exist_ok=True)
    np.save(paths["npy"], arr)

    # Also write GeoTIFF for GDAL interoperability / debugging
    driver = gdal.GetDriverByName("GTiff")
    out = driver.Create(str(paths["tiff"]), xsize, ysize, 1, gdal.GDT_Float32, options=["COMPRESS=DEFLATE"])
    out.SetGeoTransform(crop_grid.geotransform)
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(4326)
    out.SetProjection(srs.ExportToWkt())
    ob = out.GetRasterBand(1)
    ob.WriteArray(arr)
    ob.SetNoDataValue(crop_grid.nodata)
    ob.SetUnitType("magnitudes per square arcsec")
    out.FlushCache()
    out = None

    meta = {
        "region_id": region_id,
        "region": region,
        "source_path": str(Path(source_path).resolve()),
        "window": {"xoff": xoff, "yoff": yoff, "xsize": xsize, "ysize": ysize},
        "grid": crop_grid.to_dict(),
        "npy": str(paths["npy"]),
        "tiff": str(paths["tiff"]),
        "dtype": "float32",
        "n_cells": int(xsize * ysize),
        "size_bytes_npy": int(paths["npy"].stat().st_size),
    }
    paths["meta"].write_text(json.dumps(meta, indent=2) + "\n")
    print(f"Wrote {paths['npy']} and {paths['tiff']}")
    return meta


def load_crop(region_id: str, cache_dir: Path = CACHE) -> tuple[np.ndarray, GeoGrid, dict[str, Any]]:
    paths = crop_cache_paths(region_id, cache_dir)
    if not paths["npy"].is_file() or not paths["meta"].is_file():
        raise FileNotFoundError(f"Missing crop cache for {region_id}; run build-crop first")
    meta = json.loads(paths["meta"].read_text())
    arr = np.load(paths["npy"])
    grid = GeoGrid.from_dict(meta["grid"])
    return arr, grid, meta
