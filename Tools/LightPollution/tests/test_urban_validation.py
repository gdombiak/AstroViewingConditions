"""Unit tests for dense urban LPATLAS1 validation helpers."""

from __future__ import annotations

import math

import numpy as np
import pytest

from light_pollution.urban_validation import (
    assign_pair_delta_bin,
    base_light_pollution_penalty,
    brightness_band_id,
    cell_center_lon_lat,
    error_stats,
    gradient_band_id,
    hierarchy_info,
    local_range_3x3,
    observing_quality_score,
    pair_ordering_outcome,
    piecewise_linear,
    region_grid_cells,
    round_half_away_from_zero,
    select_pairs,
    usability_weight,
    SamplePoint,
)


def test_piecewise_linear_endpoints_and_mid():
    anchors = [(0.0, 0.0), (10.0, 10.0)]
    assert piecewise_linear(-5, anchors) == 0.0
    assert piecewise_linear(15, anchors) == 10.0
    assert abs(piecewise_linear(5, anchors) - 5.0) < 1e-12


def test_base_penalty_anchors():
    assert base_light_pollution_penalty(17.5) == pytest.approx(8.0)
    assert base_light_pollution_penalty(21.75) == pytest.approx(0.0)
    assert base_light_pollution_penalty(18.5) == pytest.approx(7.0)
    assert base_light_pollution_penalty(float("nan")) is None
    # Midpoint 18.0 between 17.5→8 and 18.5→7
    assert base_light_pollution_penalty(18.0) == pytest.approx(7.5)


def test_round_half_away_from_zero_matches_swift():
    # Positive half-up / away-from-zero (not Python banker's round)
    assert round_half_away_from_zero(84.5) == 85
    assert round_half_away_from_zero(83.5) == 84
    assert round_half_away_from_zero(84.4) == 84
    assert round_half_away_from_zero(84.6) == 85
    assert round_half_away_from_zero(83.4) == 83
    assert round_half_away_from_zero(83.6) == 84
    # Banker's round would send 0.5 → 0 and 1.5 → 2; we always go away from zero
    assert round_half_away_from_zero(0.5) == 1
    assert round_half_away_from_zero(1.5) == 2
    assert round_half_away_from_zero(2.5) == 3
    assert round_half_away_from_zero(-1.5) == -2
    with pytest.raises(ValueError):
        round_half_away_from_zero(float("nan"))


def test_usability_weight_and_score():
    assert usability_weight(35) == pytest.approx(0.0)
    assert usability_weight(80) == pytest.approx(1.0)
    # Bright urban + excellent night → full base penalty applied
    s = observing_quality_score(93, 17.5)
    # weight at 93 = 1.0, base=8 → round(93-8)=85
    assert s == 85
    # Missing brightness returns night score
    assert observing_quality_score(75, None) == 75
    # Score path clamps after Swift-style rounding (production order)
    assert max(0, min(100, round_half_away_from_zero(-0.5))) == 0
    assert max(0, min(100, round_half_away_from_zero(100.5))) == 100


def test_brightness_and_gradient_bands():
    assert brightness_band_id(16.5) == "lt_17"
    assert brightness_band_id(17.0) == "17_18"
    assert brightness_band_id(19.5) == "19_20"
    assert brightness_band_id(21.0) == "ge_20"
    assert gradient_band_id(0.01) == "low"
    assert gradient_band_id(0.10) == "moderate"
    assert gradient_band_id(0.20) == "high"
    assert gradient_band_id(0.50) == "extreme"


def test_region_grid_cells_deterministic_and_aligned():
    cells_a = region_grid_cells(-122.8, -122.6, 45.4, 45.5, step_cells=2)
    cells_b = region_grid_cells(-122.8, -122.6, 45.4, 45.5, step_cells=2)
    assert cells_a == cells_b
    assert len(cells_a) > 10
    # Cell centers map back to same col/row via lon_lat_to_cell semantics
    from light_pollution.binary_format import lon_lat_to_cell

    for col, row, lon, lat in cells_a[:5]:
        cell = lon_lat_to_cell(lon, lat)
        assert cell == (col, row)
        lon2, lat2 = cell_center_lon_lat(col, row)
        assert abs(lon2 - lon) < 1e-12
        assert abs(lat2 - lat) < 1e-12


def test_region_grid_rejects_bad_box():
    with pytest.raises(ValueError):
        region_grid_cells(0, -1, 0, 1)
    with pytest.raises(ValueError):
        region_grid_cells(0, 1, 0, 1, step_cells=0)


def test_local_range_3x3_and_nodata():
    window = np.array(
        [
            [20.0, 20.0, 20.0],
            [20.0, 18.0, 20.0],
            [20.0, 20.0, 20.0],
        ],
        dtype=np.float64,
    )
    valid = np.ones_like(window, dtype=bool)
    assert local_range_3x3(window, valid, 1, 1) == pytest.approx(2.0)
    valid[0, 0] = False
    # Still enough neighbors
    assert local_range_3x3(window, valid, 1, 1) == pytest.approx(2.0)
    # Only one valid → None
    v2 = np.zeros_like(window, dtype=bool)
    v2[1, 1] = True
    assert local_range_3x3(window, v2, 1, 1) is None


def test_hierarchy_info_root_boundary():
    # col=0 is on western edge of root 0
    h = hierarchy_info(0, 100)
    assert h["root_i"] == 0
    assert h["near_root_boundary"] is True
    # Interior of a root
    h2 = hierarchy_info(400, 400)
    assert h2["near_root_boundary"] is False


def test_error_stats_empty_and_known():
    empty = error_stats(np.array([]))
    assert empty["n"] == 0
    assert empty["mae"] is None
    a = np.array([0.0, 0.1, 0.2])
    s = error_stats(a)
    assert s["n"] == 3
    assert s["mae"] == pytest.approx(0.1)
    assert s["max"] == pytest.approx(0.2)


def test_pair_delta_bins():
    assert assign_pair_delta_bin(0.01) == "lt_0_05"
    assert assign_pair_delta_bin(0.07) == "0_05_0_10"
    assert assign_pair_delta_bin(0.15) == "0_10_0_25"
    assert assign_pair_delta_bin(0.5) == "gt_0_25"


def test_pair_ordering_preserve_and_reverse():
    # Source: A darker (higher mag). Artifact reverses.
    # Equal night → darker site scores higher.
    assert (
        pair_ordering_outcome(
            src_a=21.0, src_b=18.0, art_a=18.0, art_b=21.0, night_a=75, night_b=75
        )
        == "reverse"
    )
    assert (
        pair_ordering_outcome(
            src_a=21.0, src_b=18.0, art_a=21.0, art_b=18.0, night_a=75, night_b=75
        )
        == "preserve"
    )


def _sample(col: int, row: int, lon: float, lat: float, source: float) -> SamplePoint:
    return SamplePoint(
        region_id="t",
        col=col,
        row=row,
        lon=lon,
        lat=lat,
        source=source,
        artifact=source,
        abs_error=0.0,
        signed_error=0.0,
        local_range=0.05,
        gradient_band="low",
        brightness_band=brightness_band_id(source),
        hierarchy={},
    )


def _pair_ids(pairs):
    """Canonical unordered pair identities by (row, col)."""
    out = []
    for a, b in pairs:
        ka = (a.row, a.col)
        kb = (b.row, b.col)
        out.append(tuple(sorted((ka, kb))))
    return out


def test_select_pairs_seed_reproducible_and_changes():
    # 2D grid spanning multiple geo tiles with varied brightness
    samples = []
    for r in range(12):
        for c in range(12):
            samples.append(
                _sample(
                    col=c,
                    row=r,
                    lon=-122.0 + c * 0.02,
                    lat=45.0 + r * 0.02,
                    source=17.0 + 0.05 * c + 0.03 * r,
                )
            )
    p1 = select_pairs(samples, max_distance_deg=0.05, max_pairs=40, seed=70)
    p2 = select_pairs(samples, max_distance_deg=0.05, max_pairs=40, seed=70)
    p3 = select_pairs(samples, max_distance_deg=0.05, max_pairs=40, seed=71)
    assert len(p1) > 0
    assert _pair_ids(p1) == _pair_ids(p2)
    # Different seed must change selection when many candidates exist
    assert _pair_ids(p1) != _pair_ids(p3)


def test_select_pairs_geographic_coverage_and_constraints():
    samples = []
    for r in range(15):
        for c in range(15):
            samples.append(
                _sample(
                    col=c,
                    row=r,
                    lon=0.0 + c * 0.025,
                    lat=0.0 + r * 0.025,
                    source=18.0 + 0.1 * ((c + r) % 5),
                )
            )
    max_d = 0.05
    pairs = select_pairs(samples, max_distance_deg=max_d, max_pairs=60, seed=70)
    assert 0 < len(pairs) <= 60

    ids = _pair_ids(pairs)
    assert len(ids) == len(set(ids)), "duplicate unordered pairs"
    assert len(pairs) == len(set(ids))

    mids_lon = []
    mids_lat = []
    for a, b in pairs:
        d = math.hypot(a.lon - b.lon, a.lat - b.lat)
        assert d > 0.0
        assert d <= max_d + 1e-12
        mids_lon.append(0.5 * (a.lon + b.lon))
        mids_lat.append(0.5 * (a.lat + b.lat))

    # Cover multiple geographic portions of the synthetic region
    assert max(mids_lon) - min(mids_lon) > 0.1
    assert max(mids_lat) - min(mids_lat) > 0.1

    # Source-delta binning still classifies pairs
    bins = {assign_pair_delta_bin(a.source - b.source) for a, b in pairs}
    assert len(bins) >= 1


def test_select_pairs_respects_max_pairs():
    samples = [
        _sample(c, 0, -122.0 + c * 0.01, 45.5, 18.0 + c * 0.02) for c in range(30)
    ]
    pairs = select_pairs(samples, max_distance_deg=0.05, max_pairs=7, seed=70)
    assert len(pairs) <= 7


def test_config_loads_required_cities():
    from light_pollution.urban_validation import load_regions_config

    cfg = load_regions_config()
    ids = {r["id"] for r in cfg["regions"]}
    required = {
        "portland",
        "seattle",
        "sf_bay",
        "los_angeles",
        "new_york",
        "chicago",
        "dallas_fw",
        "miami",
        "phoenix",
        "mexico_city",
        "sao_paulo",
        "buenos_aires",
        "london",
        "paris",
        "madrid",
        "rome",
        "cairo",
        "johannesburg",
        "tokyo",
        "seoul",
        "beijing",
        "shanghai",
        "delhi",
        "mumbai",
        "singapore",
        "sydney",
    }
    assert required.issubset(ids)
    assert cfg["seed"] == 70
