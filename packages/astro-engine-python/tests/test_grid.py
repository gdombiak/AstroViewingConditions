from __future__ import annotations

import time
from pathlib import Path

import pytest

from astro_engine.errors import GridCapError, ValidationError
from astro_engine.grid import (
    CAPABILITY_ID,
    contract_point_cap,
    estimated_point_count,
    exceeds_contract_point_cap,
    generate_grid,
    location_grid,
)

from compare import compare_envelope
from python_eval import python_envelope
from support import iter_capability_fixtures

GRID_DIR = "fixtures/capabilities/location-grid"
FROZEN_FIXTURE_IDS = (
    "antimeridian-v1",
    "high-latitude-v1",
    "nyc-10-5-v1",
    "nyc-radius-lt-spacing-v1",
    "zero-radius-v1",
)


def test_named_grid_fixtures_are_contract_owned() -> None:
    fixtures = list(iter_capability_fixtures(GRID_DIR))
    assert [item["id"] for item in fixtures] == sorted(FROZEN_FIXTURE_IDS)
    for fixture in fixtures:
        path: Path = fixture["path"]
        assert "packages" not in path.parts
        assert path.parts[-3:] == ("capabilities", "location-grid", fixture["id"])


@pytest.mark.parametrize("fixture_id", FROZEN_FIXTURE_IDS)
def test_named_grid_fixtures(fixture_id: str) -> None:
    fixture = next(item for item in iter_capability_fixtures(GRID_DIR) if item["id"] == fixture_id)
    actual = python_envelope(CAPABILITY_ID, fixture["input"])
    compare_envelope(actual, fixture["expected"], policy_id="grid")


def test_center_is_first_and_order_is_lattice_then_boundary() -> None:
    points = generate_grid(
        latitude=40.7128,
        longitude=-74.0060,
        radius_miles=10,
        spacing_miles=5,
    )
    assert points[0]["is_center"] is True
    assert points[0]["north_step"] == 0
    assert points[0]["east_step"] == 0
    assert points[0]["distance_miles"] == 0
    lattice = [point for point in points[1:] if point["north_step"] is not None]
    boundary = [point for point in points[1:] if point["north_step"] is None]
    assert lattice
    assert all(point["north_step"] is not None and point["east_step"] is not None for point in lattice)
    assert [point["bearing_deg"] for point in boundary] == [45.0, 135.0, 225.0, 315.0]


def test_zero_and_negative_parameters_are_empty() -> None:
    empty = generate_grid(latitude=40.0, longitude=-74.0, radius_miles=0, spacing_miles=5)
    assert empty == []
    assert generate_grid(latitude=40.0, longitude=-74.0, radius_miles=-10, spacing_miles=5) == []
    assert generate_grid(latitude=40.0, longitude=-74.0, radius_miles=10, spacing_miles=0) == []
    assert generate_grid(latitude=40.0, longitude=-74.0, radius_miles=10, spacing_miles=-5) == []
    assert location_grid(
        {"center": {"latitude": 40.0, "longitude": -74.0}, "radius_miles": 0, "spacing_miles": 5}
    ) == {"points": []}


def test_antimeridian_longitude_is_not_wrapped() -> None:
    points = generate_grid(
        latitude=0.0,
        longitude=179.5,
        radius_miles=50,
        spacing_miles=50,
    )
    east = next(point for point in points if point["east_step"] == 1 and point["north_step"] == 0)
    assert east["longitude"] > 180.0
    assert all(-90.0 <= point["latitude"] <= 90.0 for point in points)


def test_bool_and_non_finite_inputs_are_rejected() -> None:
    center = {"latitude": 40.7128, "longitude": -74.0060}
    with pytest.raises(ValidationError, match="finite JSON number"):
        location_grid({"center": center, "radius_miles": True, "spacing_miles": 5})
    with pytest.raises(ValidationError, match="finite JSON number"):
        location_grid(
            {"center": {"latitude": "40.7", "longitude": -74.0}, "radius_miles": 5, "spacing_miles": 5}
        )
    with pytest.raises(ValidationError, match="center must be an object"):
        location_grid({"radius_miles": 5, "spacing_miles": 5})


def _center() -> dict[str, float]:
    return {"latitude": 0.0, "longitude": 0.0}


def test_grid_cap_accepts_fifty_by_three() -> None:
    assert contract_point_cap() == 885
    assert contract_point_cap() == estimated_point_count(radius_miles=50, spacing_miles=3)
    assert exceeds_contract_point_cap(50, 3) is False
    result = location_grid(
        {"center": _center(), "radius_miles": 50, "spacing_miles": 3}
    )
    assert len(result["points"]) == 885


def test_grid_cap_rejects_fifty_one_by_three() -> None:
    with pytest.raises(GridCapError) as exc:
        location_grid(
            {"center": _center(), "radius_miles": 51, "spacing_miles": 3}
        )
    assert exc.value.code == "grid_cap"
    # Library generate_grid itself is uncapped, matching Swift production.
    assert len(
        generate_grid(latitude=0.0, longitude=0.0, radius_miles=51, spacing_miles=3)
    ) > contract_point_cap()


def test_grid_cap_rejects_tiny_spacing_without_generating() -> None:
    started = time.perf_counter()
    with pytest.raises(GridCapError) as exc:
        location_grid(
            {"center": _center(), "radius_miles": 50, "spacing_miles": 1e-12}
        )
    elapsed = time.perf_counter() - started
    assert exc.value.code == "grid_cap"
    assert elapsed < 0.25
    assert exceeds_contract_point_cap(50.0, 1e-12) is True


def test_grid_cap_rejects_extreme_finite_ratio_without_overflow() -> None:
    started = time.perf_counter()
    with pytest.raises(GridCapError) as exc:
        location_grid(
            {
                "center": _center(),
                "radius_miles": 1e308,
                "spacing_miles": 1e-308,
            }
        )
    elapsed = time.perf_counter() - started
    assert exc.value.code == "grid_cap"
    assert elapsed < 0.25
    assert exceeds_contract_point_cap(1e308, 1e-308) is True


def test_grid_cap_is_a_point_count_not_a_radius_spacing_domain() -> None:
    # Same radius/spacing ratio as 50/3, larger absolute miles: 885 points, accepted.
    result = location_grid(
        {"center": _center(), "radius_miles": 100, "spacing_miles": 6}
    )
    assert len(result["points"]) == 885
    assert exceeds_contract_point_cap(100, 6) is False
    # radius > 50 with coarse spacing stays under the point cap.
    coarse = location_grid(
        {"center": _center(), "radius_miles": 200, "spacing_miles": 50}
    )
    assert 1 < len(coarse["points"]) <= 885
    assert exceeds_contract_point_cap(200, 50) is False
