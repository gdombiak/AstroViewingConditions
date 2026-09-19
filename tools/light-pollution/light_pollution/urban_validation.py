"""Dense urban fidelity validation for LPATLAS1 vs source GeoTIFF.

Validation-only: does not regenerate or modify the production artifact.
"""

from __future__ import annotations

import csv
import json
import math
import random
import time
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from .binary_format import (
    FINEST_CELLS,
    ORIGIN_LAT,
    ORIGIN_LON,
    PIXEL_SIZE,
    ROOT_CELLS,
    LightPollutionArtifact,
    lon_lat_to_cell,
)
from .nodata import is_nodata
from .paths import CONFIG, DEFAULT_SOURCE, OUTPUT
from .report import write_json
from .source import open_dataset, require_osgeo

DEFAULT_REGIONS_CONFIG = CONFIG / "urban_validation_regions.json"
DEFAULT_ARTIFACT = OUTPUT / "artifacts" / "light_pollution_global_v1.bin"
DEFAULT_OUTPUT_DIR = OUTPUT / "urban_validation"

# Gradient proxy: 3×3 neighborhood max−min of valid source cells (mag).
GRADIENT_BANDS_DEFAULT = (
    ("low", 0.0, 0.05),
    ("moderate", 0.05, 0.15),
    ("high", 0.15, 0.35),
    ("extreme", 0.35, None),
)

BRIGHTNESS_BANDS_DEFAULT = (
    ("lt_17", None, 17.0),
    ("17_18", 17.0, 18.0),
    ("18_19", 18.0, 19.0),
    ("19_20", 19.0, 20.0),
    ("ge_20", 20.0, None),
)


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested)
# ---------------------------------------------------------------------------


def piecewise_linear(x: float, anchors: Sequence[tuple[float, float]]) -> float:
    """Piecewise-linear interpolation with endpoint clamping (sorted by x)."""
    if not anchors:
        raise ValueError("anchors must not be empty")
    if not math.isfinite(x):
        raise ValueError("non-finite x")
    if x <= anchors[0][0]:
        return float(anchors[0][1])
    if x >= anchors[-1][0]:
        return float(anchors[-1][1])
    for i in range(len(anchors) - 1):
        x0, y0 = anchors[i]
        x1, y1 = anchors[i + 1]
        if x0 <= x <= x1:
            if x1 == x0:
                return float(y0)
            t = (x - x0) / (x1 - x0)
            return float(y0 + t * (y1 - y0))
    return float(anchors[-1][1])


def base_light_pollution_penalty(
    brightness: float,
    anchors: Sequence[tuple[float, float]] | None = None,
) -> float | None:
    if not math.isfinite(brightness):
        return None
    if anchors is None:
        anchors = (
            (17.5, 8.0),
            (18.5, 7.0),
            (19.5, 5.0),
            (20.5, 3.0),
            (21.3, 1.0),
            (21.75, 0.0),
        )
    return piecewise_linear(brightness, anchors)


def usability_weight(
    night_conditions_score: int,
    anchors: Sequence[tuple[float, float]] | None = None,
) -> float:
    if anchors is None:
        anchors = (
            (35.0, 0.0),
            (45.0, 0.25),
            (65.0, 0.75),
            (80.0, 1.0),
        )
    s = max(0, min(100, int(night_conditions_score)))
    return piecewise_linear(float(s), anchors)


def round_half_away_from_zero(x: float) -> int:
    """Nearest-integer rounding with ties away from zero.

    Matches Swift `Int(Double.rounded())` / `.toNearestOrAwayFromZero`, **not**
    Python's banker's `round()` (ties-to-even).

    Examples: 84.5 → 85, 83.5 → 84, -1.5 → -2.
    """
    if not math.isfinite(x):
        raise ValueError("non-finite value")
    if x >= 0.0:
        return int(math.floor(x + 0.5))
    return int(math.ceil(x - 0.5))


def observing_quality_score(
    night_conditions_score: int,
    brightness: float | None,
    *,
    penalty_anchors: Sequence[tuple[float, float]] | None = None,
    weight_anchors: Sequence[tuple[float, float]] | None = None,
) -> int:
    """Mirror ObservingQualityCalculator.assess score (rounded, clamped)."""
    night = max(0, min(100, int(night_conditions_score)))
    if brightness is None or not math.isfinite(brightness):
        return night
    base = base_light_pollution_penalty(brightness, penalty_anchors)
    if base is None:
        return night
    weight = usability_weight(night, weight_anchors)
    raw = float(night) - base * weight
    # Swift: clampScore(Int(raw.rounded())) with ties away from zero.
    return max(0, min(100, round_half_away_from_zero(raw)))


def brightness_band_id(src: float) -> str:
    if src < 17.0:
        return "lt_17"
    if src < 18.0:
        return "17_18"
    if src < 19.0:
        return "18_19"
    if src < 20.0:
        return "19_20"
    return "ge_20"


def gradient_band_id(local_range: float) -> str:
    if local_range < 0.05:
        return "low"
    if local_range < 0.15:
        return "moderate"
    if local_range < 0.35:
        return "high"
    return "extreme"


def cell_center_lon_lat(col: int, row: int) -> tuple[float, float]:
    lon = ORIGIN_LON + (col + 0.5) * PIXEL_SIZE
    lat = ORIGIN_LAT - (row + 0.5) * PIXEL_SIZE
    return lon, lat


def region_grid_cells(
    west: float,
    east: float,
    south: float,
    north: float,
    *,
    step_cells: int = 1,
) -> list[tuple[int, int, float, float]]:
    """Deterministic source-aligned cell centers inside a lon/lat box.

    Returns list of (col, row, lon_center, lat_center) ordered row-major.
    """
    if step_cells < 1:
        raise ValueError("step_cells must be >= 1")
    if east <= west or north <= south:
        raise ValueError("invalid bounding box")

    sw = lon_lat_to_cell(west, south)
    ne = lon_lat_to_cell(east, north)
    se = lon_lat_to_cell(east, south)
    nw = lon_lat_to_cell(west, north)
    if None in (sw, ne, se, nw):
        raise ValueError("region partially outside source domain")

    cols = [sw[0], ne[0], se[0], nw[0]]
    rows = [sw[1], ne[1], se[1], nw[1]]
    c0, c1 = min(cols), max(cols)
    r0, r1 = min(rows), max(rows)

    out: list[tuple[int, int, float, float]] = []
    for row in range(r0, r1 + 1, step_cells):
        for col in range(c0, c1 + 1, step_cells):
            lon, lat = cell_center_lon_lat(col, row)
            # Keep only centers strictly inside the configured box
            if west <= lon <= east and south <= lat <= north:
                out.append((col, row, lon, lat))
    return out


def local_range_3x3(
    window: np.ndarray,
    valid: np.ndarray,
    local_r: int,
    local_c: int,
) -> float | None:
    """Max−min of valid cells in 3×3 neighborhood centered at (local_r, local_c)."""
    h, w = window.shape
    vals: list[float] = []
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            rr, cc = local_r + dr, local_c + dc
            if 0 <= rr < h and 0 <= cc < w and valid[rr, cc]:
                vals.append(float(window[rr, cc]))
    if len(vals) < 2:
        return None
    return max(vals) - min(vals)


def hierarchy_info(col: int, row: int) -> dict[str, Any]:
    root_i = col // ROOT_CELLS
    root_j = row // ROOT_CELLS
    local_c = col - root_i * ROOT_CELLS
    local_r = row - root_j * ROOT_CELLS
    # Distance to root edge in cells (0 = on edge)
    edge_dist = min(local_c, local_r, ROOT_CELLS - 1 - local_c, ROOT_CELLS - 1 - local_r)
    near_root_boundary = edge_dist <= 2
    # Within a 3-cell finest block alignment (proxy for finest-cap grid)
    finest_local_c = local_c % FINEST_CELLS
    finest_local_r = local_r % FINEST_CELLS
    return {
        "root_i": root_i,
        "root_j": root_j,
        "local_c": local_c,
        "local_r": local_r,
        "edge_dist_cells": edge_dist,
        "near_root_boundary": near_root_boundary,
        "finest_phase_c": finest_local_c,
        "finest_phase_r": finest_local_r,
    }


def error_stats(abs_errs: np.ndarray) -> dict[str, Any]:
    a = np.asarray(abs_errs, dtype=np.float64)
    if a.size == 0:
        return {
            "n": 0,
            "mae": None,
            "median": None,
            "p75": None,
            "p90": None,
            "p95": None,
            "p99": None,
            "max": None,
            "pct_gt_0_05": None,
            "pct_gt_0_10": None,
            "pct_gt_0_15": None,
            "pct_gt_0_20": None,
            "pct_gt_0_30": None,
        }
    return {
        "n": int(a.size),
        "mae": float(np.mean(a)),
        "median": float(np.median(a)),
        "p75": float(np.percentile(a, 75)),
        "p90": float(np.percentile(a, 90)),
        "p95": float(np.percentile(a, 95)),
        "p99": float(np.percentile(a, 99)),
        "max": float(np.max(a)),
        "pct_gt_0_05": float(100.0 * np.mean(a > 0.05)),
        "pct_gt_0_10": float(100.0 * np.mean(a > 0.10)),
        "pct_gt_0_15": float(100.0 * np.mean(a > 0.15)),
        "pct_gt_0_20": float(100.0 * np.mean(a > 0.20)),
        "pct_gt_0_30": float(100.0 * np.mean(a > 0.30)),
    }


def compact_region_stats(abs_errs: np.ndarray) -> dict[str, Any]:
    full = error_stats(abs_errs)
    return {
        "n": full["n"],
        "mae": full["mae"],
        "p95": full["p95"],
        "p99": full["p99"],
        "max": full["max"],
        "pct_gt_0_10": full["pct_gt_0_10"],
        "pct_gt_0_20": full["pct_gt_0_20"],
    }


def band_stats(abs_errs: np.ndarray) -> dict[str, Any]:
    full = error_stats(abs_errs)
    return {
        "n": full["n"],
        "mae": full["mae"],
        "p95": full["p95"],
        "p99": full["p99"],
        "max": full["max"],
        "pct_gt_0_10": full["pct_gt_0_10"],
        "pct_gt_0_20": full["pct_gt_0_20"],
    }


@dataclass(frozen=True)
class SamplePoint:
    region_id: str
    col: int
    row: int
    lon: float
    lat: float
    source: float
    artifact: float
    abs_error: float
    signed_error: float
    local_range: float | None
    gradient_band: str | None
    brightness_band: str
    hierarchy: dict[str, Any]


def assign_pair_delta_bin(delta: float) -> str:
    d = abs(delta)
    if d < 0.05:
        return "lt_0_05"
    if d < 0.10:
        return "0_05_0_10"
    if d < 0.25:
        return "0_10_0_25"
    return "gt_0_25"


def pair_ordering_outcome(
    src_a: float,
    src_b: float,
    art_a: float,
    art_b: float,
    night_a: int,
    night_b: int,
) -> str:
    """Compare darker-site preference via observing-quality scores.

    Returns: preserve | tie | reverse
    (relative to source-preferred darker site under equal or given night scores).
    """
    # Higher mag = darker = better (lower penalty)
    # Source preference: higher mag is better
    if src_a == src_b and night_a == night_b:
        # No preference from source brightness
        score_src_a = observing_quality_score(night_a, src_a)
        score_src_b = observing_quality_score(night_b, src_b)
        score_art_a = observing_quality_score(night_a, art_a)
        score_art_b = observing_quality_score(night_b, art_b)
        if score_src_a == score_src_b:
            if score_art_a == score_art_b:
                return "tie"
            # source tied; artifact broke tie — count as reverse of "no preference" → reverse
            return "reverse" if score_art_a != score_art_b else "tie"

    score_src_a = observing_quality_score(night_a, src_a)
    score_src_b = observing_quality_score(night_b, src_b)
    score_art_a = observing_quality_score(night_a, art_a)
    score_art_b = observing_quality_score(night_b, art_b)

    # Preferred site under source: higher score wins; if scores equal, higher mag wins
    if score_src_a > score_src_b:
        src_pref = "a"
    elif score_src_b > score_src_a:
        src_pref = "b"
    else:
        if src_a > src_b:
            src_pref = "a"
        elif src_b > src_a:
            src_pref = "b"
        else:
            src_pref = "tie"

    if score_art_a > score_art_b:
        art_pref = "a"
    elif score_art_b > score_art_a:
        art_pref = "b"
    else:
        art_pref = "tie"

    if src_pref == "tie":
        return "tie" if art_pref == "tie" else "reverse"
    if art_pref == "tie":
        return "tie"
    if art_pref == src_pref:
        return "preserve"
    return "reverse"


def select_pairs(
    samples: Sequence[SamplePoint],
    *,
    max_distance_deg: float = 0.05,
    max_pairs: int = 500,
    seed: int = 70,
) -> list[tuple[SamplePoint, SamplePoint]]:
    """Deterministic, spatially stratified nearby pairs within one region.

    Strategy (avoids full Cartesian product and first-row bias):

    1. Index samples into geographic tiles of size ``max_distance_deg``.
    2. Emit candidate pairs only against the same/adjacent tiles, keeping
       unordered pairs with Euclidean lon/lat distance in ``(0, max_distance]``.
    3. Stratify candidates by coarser midpoint geo-tile (2× max distance) and
       source-brightness delta bin.
    4. Seeded shuffle within each (geo, bin) stratum, then round-robin across
       geo tiles and delta bins until ``max_pairs`` is reached.

    Same inputs + seed always yield the same pair identities; a different seed
    reshuffles strata when enough candidates exist.
    """
    if len(samples) < 2 or max_pairs <= 0:
        return []
    if max_distance_deg <= 0:
        raise ValueError("max_distance_deg must be > 0")

    # Stable index order for deterministic pair keys.
    points = [
        s
        for _, s in sorted(
            enumerate(samples), key=lambda t: (t[1].row, t[1].col, t[0])
        )
    ]

    tile = max_distance_deg
    buckets: dict[tuple[int, int], list[int]] = defaultdict(list)
    for i, s in enumerate(points):
        ti = int(math.floor(s.lon / tile))
        tj = int(math.floor(s.lat / tile))
        buckets[(ti, tj)].append(i)

    # Candidate: (ia, ib, geo_stratum, delta_bin) with ia < ib
    candidates: list[tuple[int, int, tuple[int, int], str]] = []
    seen: set[tuple[int, int]] = set()
    geo_tile = 2.0 * max_distance_deg

    for (ti, tj), idxs in buckets.items():
        neighbor_idxs: list[int] = []
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                neighbor_idxs.extend(buckets.get((ti + di, tj + dj), ()))
        for ia in idxs:
            a = points[ia]
            for ib in neighbor_idxs:
                if ib <= ia:
                    continue
                key = (ia, ib)
                if key in seen:
                    continue
                b = points[ib]
                dlon = abs(a.lon - b.lon)
                dlat = abs(a.lat - b.lat)
                if dlon > max_distance_deg or dlat > max_distance_deg:
                    continue
                dist = math.hypot(dlon, dlat)
                if dist <= 0.0 or dist > max_distance_deg:
                    continue
                seen.add(key)
                mid_lon = 0.5 * (a.lon + b.lon)
                mid_lat = 0.5 * (a.lat + b.lat)
                geo_key = (
                    int(math.floor(mid_lon / geo_tile)),
                    int(math.floor(mid_lat / geo_tile)),
                )
                delta_bin = assign_pair_delta_bin(a.source - b.source)
                candidates.append((ia, ib, geo_key, delta_bin))

    if not candidates:
        return []

    rng = random.Random(seed)

    # Group by geo stratum, then by brightness-delta bin.
    by_geo: dict[tuple[int, int], dict[str, list[tuple[int, int]]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for ia, ib, geo_key, delta_bin in candidates:
        by_geo[geo_key][delta_bin].append((ia, ib))

    geo_keys = sorted(by_geo.keys())
    # Per geo: round-robin across delta bins after seeded shuffle of each bin.
    geo_streams: list[list[tuple[int, int]]] = []
    for gk in geo_keys:
        bins = by_geo[gk]
        bin_ids = sorted(bins.keys())
        queues: list[list[tuple[int, int]]] = []
        for bid in bin_ids:
            items = list(bins[bid])
            items.sort()  # stable before shuffle
            rng.shuffle(items)
            queues.append(items)
        merged: list[tuple[int, int]] = []
        while any(queues):
            for q in queues:
                if q:
                    merged.append(q.pop(0))
        geo_streams.append(merged)

    # Round-robin across geo tiles so the metro is covered, not one corner.
    selected_idx: list[tuple[int, int]] = []
    ptrs = [0] * len(geo_streams)
    while len(selected_idx) < max_pairs and any(
        ptrs[i] < len(geo_streams[i]) for i in range(len(geo_streams))
    ):
        for i in range(len(geo_streams)):
            if ptrs[i] < len(geo_streams[i]):
                selected_idx.append(geo_streams[i][ptrs[i]])
                ptrs[i] += 1
                if len(selected_idx) >= max_pairs:
                    break

    return [(points[ia], points[ib]) for ia, ib in selected_idx]


# ---------------------------------------------------------------------------
# Region evaluation
# ---------------------------------------------------------------------------


def load_regions_config(path: Path | None = None) -> dict[str, Any]:
    p = Path(path or DEFAULT_REGIONS_CONFIG)
    return json.loads(p.read_text())


def evaluate_region(
    region: dict[str, Any],
    *,
    source_path: Path,
    artifact: LightPollutionArtifact,
    nodata: float | None,
) -> tuple[list[SamplePoint], dict[str, Any]]:
    """Windowed source read + dense grid compare for one metro region."""
    from osgeo import gdal

    step = int(region.get("subsample_step_cells", 1))
    cells = region_grid_cells(
        region["west"],
        region["east"],
        region["south"],
        region["north"],
        step_cells=step,
    )
    requested = len(cells)
    if requested == 0:
        return [], {
            "region_id": region["id"],
            "name": region.get("name", region["id"]),
            "requested": 0,
            "valid": 0,
            "nodata_or_unavailable": 0,
            "stats": compact_region_stats(np.array([])),
        }

    cols = [c for c, _, _, _ in cells]
    rows = [r for _, r, _, _ in cells]
    c0, c1 = min(cols), max(cols)
    r0, r1 = min(rows), max(rows)
    # Pad by 1 for 3×3 gradient
    pad = 1
    win_c0 = max(0, c0 - pad)
    win_r0 = max(0, r0 - pad)
    win_c1 = min(43200 - 1, c1 + pad)
    win_r1 = min(16801 - 1, r1 + pad)
    xsize = win_c1 - win_c0 + 1
    ysize = win_r1 - win_r0 + 1

    ds = gdal.Open(str(source_path))
    if ds is None:
        raise RuntimeError(f"cannot open source {source_path}")
    band = ds.GetRasterBand(1)
    window = np.array(band.ReadAsArray(win_c0, win_r0, xsize, ysize), dtype=np.float64)
    valid = ~is_nodata(window, nodata)

    samples: list[SamplePoint] = []
    nodata_count = 0
    for col, row, lon, lat in cells:
        lr = row - win_r0
        lc = col - win_c0
        if lr < 0 or lc < 0 or lr >= ysize or lc >= xsize:
            nodata_count += 1
            continue
        if not valid[lr, lc]:
            nodata_count += 1
            continue
        src = float(window[lr, lc])
        art = artifact.lookup(lat, lon)
        if art is None:
            nodata_count += 1
            continue
        abs_e = abs(src - art)
        signed = art - src
        loc_range = local_range_3x3(window, valid, lr, lc)
        gband = gradient_band_id(loc_range) if loc_range is not None else None
        samples.append(
            SamplePoint(
                region_id=region["id"],
                col=col,
                row=row,
                lon=lon,
                lat=lat,
                source=src,
                artifact=art,
                abs_error=abs_e,
                signed_error=signed,
                local_range=loc_range,
                gradient_band=gband,
                brightness_band=brightness_band_id(src),
                hierarchy=hierarchy_info(col, row),
            )
        )

    errs = np.array([s.abs_error for s in samples], dtype=np.float64)
    meta = {
        "region_id": region["id"],
        "name": region.get("name", region["id"]),
        "continent": region.get("continent"),
        "bbox": {
            "west": region["west"],
            "east": region["east"],
            "south": region["south"],
            "north": region["north"],
        },
        "subsample_step_cells": step,
        "requested": requested,
        "valid": len(samples),
        "nodata_or_unavailable": nodata_count,
        "stats": compact_region_stats(errs),
    }
    return samples, meta


# ---------------------------------------------------------------------------
# Aggregate analyses
# ---------------------------------------------------------------------------


def scoring_impact_analysis(
    samples: Sequence[SamplePoint],
    *,
    night_scores: Sequence[int],
    penalty_anchors: Sequence[tuple[float, float]],
    weight_anchors: Sequence[tuple[float, float]],
) -> dict[str, Any]:
    pen_src = []
    pen_art = []
    pen_diff = []
    for s in samples:
        ps = base_light_pollution_penalty(s.source, penalty_anchors)
        pa = base_light_pollution_penalty(s.artifact, penalty_anchors)
        if ps is None or pa is None:
            continue
        pen_src.append(ps)
        pen_art.append(pa)
        pen_diff.append(abs(ps - pa))

    d = np.array(pen_diff, dtype=np.float64) if pen_diff else np.array([], dtype=np.float64)
    penalty_summary = {
        "n": int(d.size),
        "mean_abs_penalty_diff": float(np.mean(d)) if d.size else None,
        "p95_abs_penalty_diff": float(np.percentile(d, 95)) if d.size else None,
        "p99_abs_penalty_diff": float(np.percentile(d, 99)) if d.size else None,
        "max_abs_penalty_diff": float(np.max(d)) if d.size else None,
        "pct_gt_0_1": float(100.0 * np.mean(d > 0.1)) if d.size else None,
        "pct_gt_0_25": float(100.0 * np.mean(d > 0.25)) if d.size else None,
        "pct_gt_0_5": float(100.0 * np.mean(d > 0.5)) if d.size else None,
        "pct_gt_1_0": float(100.0 * np.mean(d > 1.0)) if d.size else None,
    }

    score_deltas: dict[str, Any] = {}
    for night in night_scores:
        deltas = []
        for s in samples:
            qs = observing_quality_score(
                night, s.source, penalty_anchors=penalty_anchors, weight_anchors=weight_anchors
            )
            qa = observing_quality_score(
                night, s.artifact, penalty_anchors=penalty_anchors, weight_anchors=weight_anchors
            )
            deltas.append(abs(qs - qa))
        arr = np.array(deltas, dtype=np.int64)
        score_deltas[str(night)] = {
            "n": int(arr.size),
            "pct_delta_0": float(100.0 * np.mean(arr == 0)),
            "pct_delta_1": float(100.0 * np.mean(arr == 1)),
            "pct_delta_2": float(100.0 * np.mean(arr == 2)),
            "pct_delta_gt_2": float(100.0 * np.mean(arr > 2)),
            "mean_abs_score_delta": float(np.mean(arr)),
            "max_abs_score_delta": int(np.max(arr)) if arr.size else None,
        }

    return {"base_penalty": penalty_summary, "rounded_score_by_night": score_deltas}


def best_nearby_sensitivity(
    samples_by_region: dict[str, list[SamplePoint]],
    *,
    max_distance_deg: float,
    max_pairs_per_region: int,
    seed: int,
    night_deltas: Sequence[int],
) -> dict[str, Any]:
    all_pairs: list[tuple[SamplePoint, SamplePoint]] = []
    for region_id, samples in samples_by_region.items():
        pairs = select_pairs(
            samples,
            max_distance_deg=max_distance_deg,
            max_pairs=max_pairs_per_region,
            seed=seed,
        )
        all_pairs.extend(pairs)

    def summarize(night_delta: int) -> dict[str, Any]:
        bins: dict[str, dict[str, int]] = {}
        for a, b in all_pairs:
            # Apply night delta to site B relative to base 75
            night_a = 75
            night_b = max(0, min(100, 75 + night_delta))
            bin_id = assign_pair_delta_bin(a.source - b.source)
            outcome = pair_ordering_outcome(
                a.source, b.source, a.artifact, b.artifact, night_a, night_b
            )
            bins.setdefault(bin_id, {"preserve": 0, "tie": 0, "reverse": 0, "n": 0})
            bins[bin_id][outcome] += 1
            bins[bin_id]["n"] += 1

        out: dict[str, Any] = {"n_pairs": len(all_pairs), "by_source_delta": {}}
        for bin_id, counts in bins.items():
            n = counts["n"]
            out["by_source_delta"][bin_id] = {
                "n": n,
                "pct_preserve": 100.0 * counts["preserve"] / n if n else None,
                "pct_tie": 100.0 * counts["tie"] / n if n else None,
                "pct_reverse": 100.0 * counts["reverse"] / n if n else None,
            }
        # Overall
        total = {"preserve": 0, "tie": 0, "reverse": 0}
        for counts in bins.values():
            for k in total:
                total[k] += counts[k]
        n = sum(total.values())
        out["overall"] = {
            "n": n,
            "pct_preserve": 100.0 * total["preserve"] / n if n else None,
            "pct_tie": 100.0 * total["tie"] / n if n else None,
            "pct_reverse": 100.0 * total["reverse"] / n if n else None,
        }
        return out

    return {
        "max_pair_distance_deg": max_distance_deg,
        "max_pairs_per_region": max_pairs_per_region,
        "n_pairs_total": len(all_pairs),
        "by_night_delta": {str(d): summarize(d) for d in night_deltas},
    }


def worst_samples(samples: Sequence[SamplePoint], n: int = 50) -> list[dict[str, Any]]:
    ordered = sorted(samples, key=lambda s: (-s.abs_error, s.region_id, s.row, s.col))
    out = []
    for s in ordered[:n]:
        out.append(
            {
                "region_id": s.region_id,
                "latitude": s.lat,
                "longitude": s.lon,
                "col": s.col,
                "row": s.row,
                "source": s.source,
                "artifact": s.artifact,
                "signed_error": s.signed_error,
                "abs_error": s.abs_error,
                "local_range_3x3": s.local_range,
                "gradient_band": s.gradient_band,
                "brightness_band": s.brightness_band,
                **{f"hier_{k}": v for k, v in s.hierarchy.items()},
            }
        )
    return out


def cluster_summary(worst: list[dict[str, Any]]) -> dict[str, Any]:
    """Describe whether worst points cluster by region / boundary / gradient."""
    if not worst:
        return {}
    by_region: dict[str, int] = {}
    near_boundary = 0
    by_grad: dict[str, int] = {}
    by_band: dict[str, int] = {}
    for w in worst:
        by_region[w["region_id"]] = by_region.get(w["region_id"], 0) + 1
        if w.get("hier_near_root_boundary"):
            near_boundary += 1
        gb = w.get("gradient_band") or "unknown"
        by_grad[gb] = by_grad.get(gb, 0) + 1
        bb = w.get("brightness_band") or "unknown"
        by_band[bb] = by_band.get(bb, 0) + 1
    # Spatial clustering: count unique regions among top 50
    return {
        "n": len(worst),
        "unique_regions": len(by_region),
        "by_region": dict(sorted(by_region.items(), key=lambda kv: -kv[1])),
        "pct_near_root_boundary": 100.0 * near_boundary / len(worst),
        "by_gradient_band": by_grad,
        "by_brightness_band": by_band,
        "note": (
            "Clustering is summary-only: high unique_regions with few per-region "
            "implies isolated worst points; low unique_regions implies metro hotspots."
        ),
    }


def render_markdown(report: dict[str, Any]) -> str:
    o = report["overall"]
    lines = [
        "# Dense urban LPATLAS1 validation",
        "",
        f"- Artifact: `{report.get('artifact_path')}`",
        f"- Source: `{report.get('source_path')}`",
        f"- Regions: {report['n_regions']}",
        f"- Requested samples: {o['requested']}",
        f"- Valid samples: {o['valid']}",
        f"- NoData/unavailable: {o['nodata_or_unavailable']}",
        "",
        "## Overall metrics",
        "",
        f"| Metric | Value |",
        f"|--------|-------|",
        f"| MAE | {o['mae']:.4f} |" if o["mae"] is not None else "| MAE | — |",
        f"| Median | {o['median']:.4f} |",
        f"| P75 | {o['p75']:.4f} |",
        f"| P90 | {o['p90']:.4f} |",
        f"| P95 | {o['p95']:.4f} |",
        f"| P99 | {o['p99']:.4f} |",
        f"| Max | {o['max']:.4f} |",
        f"| % > 0.05 | {o['pct_gt_0_05']:.2f} |",
        f"| % > 0.10 | {o['pct_gt_0_10']:.2f} |",
        f"| % > 0.15 | {o['pct_gt_0_15']:.2f} |",
        f"| % > 0.20 | {o['pct_gt_0_20']:.2f} |",
        f"| % > 0.30 | {o['pct_gt_0_30']:.2f} |",
        "",
        "## Per-region (worst P95 first)",
        "",
        "| Region | n | MAE | P95 | P99 | Max | % >0.10 | % >0.20 |",
        "|--------|---|-----|-----|-----|-----|---------|---------|",
    ]
    for r in report["regions_sorted_by_p95"]:
        s = r["stats"]
        if s["n"] == 0:
            continue
        lines.append(
            f"| {r['name']} | {s['n']} | {s['mae']:.4f} | {s['p95']:.4f} | "
            f"{s['p99']:.4f} | {s['max']:.4f} | {s['pct_gt_0_10']:.2f} | {s['pct_gt_0_20']:.2f} |"
        )

    lines += ["", "## By source brightness", ""]
    lines.append("| Band | n | MAE | P95 | P99 | Max | % >0.10 | % >0.20 |")
    lines.append("|------|---|-----|-----|-----|-----|---------|---------|")
    for bid, s in report["by_brightness"].items():
        if s["n"] == 0:
            lines.append(f"| {bid} | 0 | — | — | — | — | — | — |")
        else:
            lines.append(
                f"| {bid} | {s['n']} | {s['mae']:.4f} | {s['p95']:.4f} | {s['p99']:.4f} | "
                f"{s['max']:.4f} | {s['pct_gt_0_10']:.2f} | {s['pct_gt_0_20']:.2f} |"
            )

    lines += ["", "## By local gradient (3×3 range)", ""]
    lines.append("| Band | n | MAE | P95 | P99 | Max | % >0.10 | % >0.20 |")
    lines.append("|------|---|-----|-----|-----|-----|---------|---------|")
    for bid, s in report["by_gradient"].items():
        if s["n"] == 0:
            lines.append(f"| {bid} | 0 | — | — | — | — | — | — |")
        else:
            lines.append(
                f"| {bid} | {s['n']} | {s['mae']:.4f} | {s['p95']:.4f} | {s['p99']:.4f} | "
                f"{s['max']:.4f} | {s['pct_gt_0_10']:.2f} | {s['pct_gt_0_20']:.2f} |"
            )

    lines += ["", "## Scoring impact (base penalty)", ""]
    bp = report["scoring_impact"]["base_penalty"]
    lines.append(f"- Mean |Δpenalty|: {bp['mean_abs_penalty_diff']}")
    lines.append(f"- P95 |Δpenalty|: {bp['p95_abs_penalty_diff']}")
    lines.append(f"- P99 |Δpenalty|: {bp['p99_abs_penalty_diff']}")
    lines.append(f"- Max |Δpenalty|: {bp['max_abs_penalty_diff']}")
    lines.append(f"- % |Δpenalty| > 0.1: {bp['pct_gt_0_1']}")
    lines.append(f"- % |Δpenalty| > 0.25: {bp['pct_gt_0_25']}")
    lines.append(f"- % |Δpenalty| > 0.5: {bp['pct_gt_0_5']}")
    lines.append(f"- % |Δpenalty| > 1.0: {bp['pct_gt_1_0']}")

    lines += ["", "## Rounded observing-quality score deltas", ""]
    for night, sd in report["scoring_impact"]["rounded_score_by_night"].items():
        lines.append(
            f"- NCS={night}: Δ0={sd['pct_delta_0']:.1f}% Δ1={sd['pct_delta_1']:.1f}% "
            f"Δ2={sd['pct_delta_2']:.1f}% Δ>2={sd['pct_delta_gt_2']:.1f}% "
            f"(max {sd['max_abs_score_delta']})"
        )

    bn = report.get("best_nearby", {})
    lines += ["", "## Best Nearby ordering (equal night=75 unless noted)", ""]
    for nd, block in bn.get("by_night_delta", {}).items():
        ov = block["overall"]
        lines.append(
            f"- night_delta={nd}: pairs={ov['n']} preserve={ov['pct_preserve']:.1f}% "
            f"tie={ov['pct_tie']:.1f}% reverse={ov['pct_reverse']:.1f}%"
        )

    lines += ["", "## Worst-case clustering", ""]
    cs = report.get("worst_cluster", {})
    lines.append(f"- Unique regions in top {cs.get('n')}: {cs.get('unique_regions')}")
    lines.append(f"- % near root boundary: {cs.get('pct_near_root_boundary')}")
    lines.append(f"- By region: {cs.get('by_region')}")
    lines.append(f"- By gradient: {cs.get('by_gradient_band')}")
    lines.append("")
    lines.append(f"Elapsed: {report.get('elapsed_sec')} s")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main runner
# ---------------------------------------------------------------------------


def run_urban_validation(
    *,
    source: Path = DEFAULT_SOURCE,
    artifact_path: Path = DEFAULT_ARTIFACT,
    regions_config: Path = DEFAULT_REGIONS_CONFIG,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
) -> dict[str, Any]:
    require_osgeo()
    from osgeo import gdal

    t0 = time.time()
    source = Path(source)
    artifact_path = Path(artifact_path)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    cfg = load_regions_config(regions_config)
    print(f"Loading artifact {artifact_path}...", flush=True)
    artifact = LightPollutionArtifact.load(artifact_path)

    ds = open_dataset(source)
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue()

    scoring_cfg = cfg.get("scoring", {})
    pen_anchors = [tuple(x) for x in scoring_cfg.get("base_penalty_anchors", [])]
    w_anchors = [tuple(x) for x in scoring_cfg.get("usability_weight_anchors", [])]
    night_scores = scoring_cfg.get("night_condition_scores", [50, 65, 75, 85, 93])
    if not pen_anchors:
        pen_anchors = [(17.5, 8.0), (18.5, 7.0), (19.5, 5.0), (20.5, 3.0), (21.3, 1.0), (21.75, 0.0)]
    if not w_anchors:
        w_anchors = [(35.0, 0.0), (45.0, 0.25), (65.0, 0.75), (80.0, 1.0)]

    all_samples: list[SamplePoint] = []
    region_metas: list[dict[str, Any]] = []
    samples_by_region: dict[str, list[SamplePoint]] = {}

    for region in cfg["regions"]:
        print(f"  Evaluating {region['id']}...", flush=True)
        samples, meta = evaluate_region(
            region, source_path=source, artifact=artifact, nodata=nodata
        )
        all_samples.extend(samples)
        samples_by_region[region["id"]] = samples
        region_metas.append(meta)
        print(
            f"    requested={meta['requested']} valid={meta['valid']} "
            f"p95={meta['stats']['p95']}",
            flush=True,
        )

    abs_errs = np.array([s.abs_error for s in all_samples], dtype=np.float64)
    overall = error_stats(abs_errs)
    overall["requested"] = sum(m["requested"] for m in region_metas)
    overall["valid"] = len(all_samples)
    overall["nodata_or_unavailable"] = sum(m["nodata_or_unavailable"] for m in region_metas)

    # Brightness bands
    by_brightness: dict[str, dict[str, Any]] = {}
    for bid, _, _ in BRIGHTNESS_BANDS_DEFAULT:
        e = np.array(
            [s.abs_error for s in all_samples if s.brightness_band == bid], dtype=np.float64
        )
        by_brightness[bid] = band_stats(e)

    # Gradient bands
    by_gradient: dict[str, dict[str, Any]] = {}
    for bid, _, _ in GRADIENT_BANDS_DEFAULT:
        e = np.array(
            [s.abs_error for s in all_samples if s.gradient_band == bid], dtype=np.float64
        )
        by_gradient[bid] = band_stats(e)

    # Sort regions by P95 descending (worst first); missing p95 last
    def p95_key(m: dict[str, Any]) -> float:
        v = m["stats"].get("p95")
        return -v if v is not None else 0.0

    regions_sorted = sorted(region_metas, key=p95_key)

    worst = worst_samples(all_samples, n=int(cfg.get("worst_n", 50)))
    worst_cluster = cluster_summary(worst)

    scoring = scoring_impact_analysis(
        all_samples,
        night_scores=night_scores,
        penalty_anchors=pen_anchors,
        weight_anchors=w_anchors,
    )

    pairing = cfg.get("pairing", {})
    best_nearby = best_nearby_sensitivity(
        samples_by_region,
        max_distance_deg=float(pairing.get("max_pair_distance_deg", 0.05)),
        max_pairs_per_region=int(pairing.get("max_pairs_per_region", 500)),
        seed=int(cfg.get("seed", 70)),
        night_deltas=list(pairing.get("night_deltas", [0, 1, 2, -1, -2])),
    )

    # Bias probes
    near_bound_errs = [s.abs_error for s in all_samples if s.hierarchy["near_root_boundary"]]
    far_bound_errs = [s.abs_error for s in all_samples if not s.hierarchy["near_root_boundary"]]
    bias = {
        "near_root_boundary": band_stats(np.array(near_bound_errs, dtype=np.float64)),
        "interior_root": band_stats(np.array(far_bound_errs, dtype=np.float64)),
        "mean_signed_error": float(np.mean([s.signed_error for s in all_samples]))
        if all_samples
        else None,
    }

    elapsed = time.time() - t0
    report: dict[str, Any] = {
        "study": "dense_urban_lpatlas1",
        "seed": cfg.get("seed"),
        "regions_config": str(regions_config),
        "artifact_path": str(artifact_path),
        "artifact_bytes": artifact_path.stat().st_size if artifact_path.is_file() else None,
        "source_path": str(source),
        "n_regions": len(region_metas),
        "elapsed_sec": elapsed,
        "overall": overall,
        "regions": region_metas,
        "regions_sorted_by_p95": regions_sorted,
        "by_brightness": by_brightness,
        "by_gradient": by_gradient,
        "scoring_impact": scoring,
        "best_nearby": best_nearby,
        "worst_cluster": worst_cluster,
        "bias_probes": bias,
        "decision_criteria_snapshot": {
            "urban_p95": overall.get("p95"),
            "pct_gt_0_10": overall.get("pct_gt_0_10"),
            "pct_gt_0_20": overall.get("pct_gt_0_20"),
            "max": overall.get("max"),
        },
    }

    write_json(output_dir / "urban_validation_report.json", report)
    (output_dir / "urban_validation_summary.md").write_text(render_markdown(report), encoding="utf-8")

    # Worst-case CSV
    worst_path = output_dir / "worst_points.csv"
    if worst:
        with worst_path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(worst[0].keys()))
            w.writeheader()
            w.writerows(worst)
    write_json(output_dir / "worst_points.json", worst)

    print(f"Wrote {output_dir}", flush=True)
    print(
        f"Overall valid={overall['valid']} MAE={overall['mae']:.4f} "
        f"P95={overall['p95']:.4f} max={overall['max']:.4f} "
        f"% >0.10={overall['pct_gt_0_10']:.2f}",
        flush=True,
    )
    return report
