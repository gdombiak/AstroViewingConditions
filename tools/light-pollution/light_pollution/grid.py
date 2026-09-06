"""Grid alignment, geotransform, and coordinate-cell mapping."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np


@dataclass(frozen=True)
class GeoGrid:
    """North-up geographic grid (GeoTIFF-style geotransform)."""

    origin_lon: float  # upper-left corner X
    origin_lat: float  # upper-left corner Y
    pixel_width: float  # positive degrees
    pixel_height: float  # negative degrees (north-up)
    width: int
    height: int
    nodata: float

    @property
    def geotransform(self) -> tuple[float, float, float, float, float, float]:
        return (
            self.origin_lon,
            self.pixel_width,
            0.0,
            self.origin_lat,
            0.0,
            self.pixel_height,
        )

    @classmethod
    def from_geotransform(
        cls,
        gt: tuple[float, ...] | list[float],
        width: int,
        height: int,
        nodata: float,
    ) -> "GeoGrid":
        return cls(
            origin_lon=float(gt[0]),
            origin_lat=float(gt[3]),
            pixel_width=float(gt[1]),
            pixel_height=float(gt[5]),
            width=width,
            height=height,
            nodata=nodata,
        )

    def lon_to_col(self, lon: float) -> int:
        return int(np.floor((lon - self.origin_lon) / self.pixel_width))

    def lat_to_row(self, lat: float) -> int:
        return int(np.floor((self.origin_lat - lat) / abs(self.pixel_height)))

    def col_to_lon_left(self, col: int) -> float:
        return self.origin_lon + col * self.pixel_width

    def row_to_lat_top(self, row: int) -> float:
        return self.origin_lat + row * self.pixel_height

    def cell_center(self, row: int, col: int) -> tuple[float, float]:
        lon = self.origin_lon + (col + 0.5) * self.pixel_width
        lat = self.origin_lat + (row + 0.5) * self.pixel_height
        return lon, lat

    def contains_lon_lat(self, lon: float, lat: float) -> bool:
        c = self.lon_to_col(lon)
        r = self.lat_to_row(lat)
        return 0 <= c < self.width and 0 <= r < self.height

    def sample_nearest(self, arr: np.ndarray, lon: float, lat: float) -> float:
        if not self.contains_lon_lat(lon, lat):
            return float(self.nodata)
        r = self.lat_to_row(lat)
        c = self.lon_to_col(lon)
        return float(arr[r, c])

    def lon_max(self) -> float:
        return self.origin_lon + self.width * self.pixel_width

    def lat_min(self) -> float:
        return self.origin_lat + self.height * self.pixel_height

    def to_dict(self) -> dict[str, Any]:
        return {
            "origin_lon": self.origin_lon,
            "origin_lat": self.origin_lat,
            "pixel_width": self.pixel_width,
            "pixel_height": self.pixel_height,
            "width": self.width,
            "height": self.height,
            "nodata": self.nodata,
            "geotransform": list(self.geotransform),
            "lon_min": self.origin_lon,
            "lon_max": self.lon_max(),
            "lat_max": self.origin_lat,
            "lat_min": self.lat_min(),
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "GeoGrid":
        if "geotransform" in d:
            gt = d["geotransform"]
            return cls.from_geotransform(gt, int(d["width"]), int(d["height"]), float(d["nodata"]))
        return cls(
            origin_lon=float(d["origin_lon"]),
            origin_lat=float(d["origin_lat"]),
            pixel_width=float(d["pixel_width"]),
            pixel_height=float(d["pixel_height"]),
            width=int(d["width"]),
            height=int(d["height"]),
            nodata=float(d["nodata"]),
        )


def window_for_extent(
    grid: GeoGrid,
    lon_min: float,
    lon_max: float,
    lat_min: float,
    lat_max: float,
) -> tuple[int, int, int, int]:
    """Return (xoff, yoff, xsize, ysize) source-aligned window covering extent."""
    x0 = grid.lon_to_col(lon_min)
    x1 = grid.lon_to_col(lon_max)
    y0 = grid.lat_to_row(lat_max)
    y1 = grid.lat_to_row(lat_min)
    x0 = max(0, x0)
    y0 = max(0, y0)
    x1 = min(grid.width, max(x1, x0 + 1))
    y1 = min(grid.height, max(y1, y0 + 1))
    return x0, y0, x1 - x0, y1 - y0


def subgrid(grid: GeoGrid, xoff: int, yoff: int, xsize: int, ysize: int) -> GeoGrid:
    return GeoGrid(
        origin_lon=grid.col_to_lon_left(xoff),
        origin_lat=grid.row_to_lat_top(yoff),
        pixel_width=grid.pixel_width,
        pixel_height=grid.pixel_height,
        width=xsize,
        height=ysize,
        nodata=grid.nodata,
    )


def reduction_factor_for_degrees(source_pixel_deg: float, target_deg: float) -> int:
    """Integer cell factor closest to target resolution / source resolution."""
    ratio = target_deg / abs(source_pixel_deg)
    factor = int(round(ratio))
    if factor < 1:
        factor = 1
    return factor


def nearest_upsample(coarse: np.ndarray, factor_y: int, factor_x: int, out_h: int, out_w: int) -> np.ndarray:
    """Nearest-neighbor expand coarse grid toward source size (no smoothing)."""
    up = np.repeat(np.repeat(coarse, factor_y, axis=0), factor_x, axis=1)
    return up[:out_h, :out_w]
