"""location.grid — deterministic circular-clipped square lattice.

Reproduces GeographicGridGenerator.generateGrid: great-circle destination
with Earth radius 6_371_000 m and 1609.344 m/mile, no longitude wrap, no
latitude clamp. Center first, then (north_step, east_step) nested loops,
then eight boundary bearings at the requested radius. Duplicate coordinates
are skipped in insertion order.
"""

from __future__ import annotations

import math
from typing import Any, Mapping

from astro_engine.errors import GridCapError, ValidationError
from astro_engine.validate import require_finite_number

CAPABILITY_ID = "location.grid"

_METERS_PER_MILE = 1609.344
_EARTH_RADIUS_METERS = 6_371_000.0
_RADIUS_EPS = 0.000_001
_BOUNDARY_BEARINGS = (0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0)

# 1.0 contract cap: result size of max iOS Best Nearby geometry (50 mi / 3 mi).
CONTRACT_POINT_CAP = 885
# maxSteps >= 22 implies an inscribed axis-aligned square of 31×31 = 961
# lattice+center points inside the circle, already over the cap. Exact
# counting is therefore only required for maxSteps <= 21 (≤ 43×43 hypot).
_MAX_STEPS_EXACT = 21


def generate_grid(
    *,
    latitude: float,
    longitude: float,
    radius_miles: float,
    spacing_miles: float,
) -> list[dict[str, Any]]:
    """Return contract grid points. Empty when radius or spacing is not > 0.

    Does not apply the capability-level grid_cap. Matches Swift generateGrid.
    """
    if not (radius_miles > 0 and spacing_miles > 0):
        return []

    points: list[dict[str, Any]] = []
    seen: set[tuple[float, float]] = set()

    def append(
        distance_miles: float,
        bearing_deg: float,
        *,
        north_step: int | None,
        east_step: int | None,
        is_center: bool = False,
    ) -> None:
        if distance_miles > radius_miles + _RADIUS_EPS:
            return
        if distance_miles == 0:
            coordinate = (latitude, longitude)
        else:
            coordinate = _destination(latitude, longitude, distance_miles, bearing_deg)
        if coordinate in seen:
            return
        seen.add(coordinate)
        points.append(
            {
                "north_step": north_step,
                "east_step": east_step,
                "is_center": is_center or distance_miles == 0,
                "bearing_deg": bearing_deg,
                "distance_miles": distance_miles,
                "latitude": coordinate[0],
                "longitude": coordinate[1],
            }
        )

    points.append(
        {
            "north_step": 0,
            "east_step": 0,
            "is_center": True,
            "bearing_deg": 0.0,
            "distance_miles": 0.0,
            "latitude": latitude,
            "longitude": longitude,
        }
    )
    seen.add((latitude, longitude))

    max_steps = int(math.floor(radius_miles / spacing_miles))
    if max_steps > 0:
        for north_step in range(-max_steps, max_steps + 1):
            for east_step in range(-max_steps, max_steps + 1):
                if north_step == 0 and east_step == 0:
                    continue
                north_miles = float(north_step) * spacing_miles
                east_miles = float(east_step) * spacing_miles
                distance = math.hypot(north_miles, east_miles)
                if distance > radius_miles + _RADIUS_EPS:
                    continue
                bearing = _normalized_bearing(
                    math.atan2(east_miles, north_miles) * 180.0 / math.pi
                )
                append(
                    distance,
                    bearing,
                    north_step=north_step,
                    east_step=east_step,
                )

    for bearing in _BOUNDARY_BEARINGS:
        append(
            radius_miles,
            bearing,
            north_step=None,
            east_step=None,
        )

    return points


def estimated_point_count(*, radius_miles: float, spacing_miles: float) -> int:
    """Match Swift estimatedPointCount: generate at (0, 0) and count.

    Host UI helper. Capability preflight must not call this.
    """
    return len(
        generate_grid(
            latitude=0.0,
            longitude=0.0,
            radius_miles=radius_miles,
            spacing_miles=spacing_miles,
        )
    )


def contract_point_cap() -> int:
    return CONTRACT_POINT_CAP


def exceeds_contract_point_cap(radius_miles: float, spacing_miles: float) -> bool:
    """True when a positive geometry would produce more than 885 points.

    Bounded work: no destination math, no point allocation. Non-positive
    radius/spacing is not a cap (those yield an empty grid).
    """
    if not (radius_miles > 0 and spacing_miles > 0):
        return False
    ratio = radius_miles / spacing_miles
    if not math.isfinite(ratio) or ratio >= _MAX_STEPS_EXACT + 1:
        return True
    max_steps = int(math.floor(ratio))
    return _bounded_point_count(radius_miles, spacing_miles, max_steps) > CONTRACT_POINT_CAP


def _bounded_point_count(radius_miles: float, spacing_miles: float, max_steps: int) -> int:
    """Count generate_grid points using only hypot on the integer lattice."""
    count = 1
    occupied_boundary = 0
    if max_steps > 0:
        for north_step in range(-max_steps, max_steps + 1):
            for east_step in range(-max_steps, max_steps + 1):
                if north_step == 0 and east_step == 0:
                    continue
                distance = math.hypot(
                    float(north_step) * spacing_miles,
                    float(east_step) * spacing_miles,
                )
                if distance > radius_miles + _RADIUS_EPS:
                    continue
                count += 1
                if distance == radius_miles:
                    bit = _compass8_bit(north_step, east_step)
                    if bit is not None:
                        occupied_boundary |= 1 << bit
    for bit in range(8):
        if occupied_boundary & (1 << bit) == 0:
            count += 1
    return count


def _compass8_bit(north_step: int, east_step: int) -> int | None:
    """Index of a 45° compass direction, or None if the step is not on one."""
    if north_step != 0 and east_step != 0 and abs(north_step) != abs(east_step):
        return None
    north = 0 if north_step == 0 else (1 if north_step > 0 else -1)
    east = 0 if east_step == 0 else (1 if east_step > 0 else -1)
    return {
        (1, 0): 0,
        (1, 1): 1,
        (0, 1): 2,
        (-1, 1): 3,
        (-1, 0): 4,
        (-1, -1): 5,
        (0, -1): 6,
        (1, -1): 7,
    }[(north, east)]


def location_grid(inputs: Mapping[str, Any] | Any) -> dict[str, Any]:
    """Capability wrapper. Applies the 1.0 grid_cap; generate_grid itself does not."""
    if not isinstance(inputs, Mapping):
        raise ValidationError("location.grid input must be an object")
    center = inputs.get("center")
    if not isinstance(center, Mapping):
        raise ValidationError("center must be an object")
    latitude = require_finite_number(center.get("latitude"), "center.latitude")
    longitude = require_finite_number(center.get("longitude"), "center.longitude")
    radius_miles = require_finite_number(inputs.get("radius_miles"), "radius_miles")
    spacing_miles = require_finite_number(inputs.get("spacing_miles"), "spacing_miles")

    if exceeds_contract_point_cap(radius_miles, spacing_miles):
        raise GridCapError(
            "grid exceeds the 1.0 cap (50 mi radius / 3 mi spacing)"
        )
    return {
        "points": generate_grid(
            latitude=latitude,
            longitude=longitude,
            radius_miles=radius_miles,
            spacing_miles=spacing_miles,
        )
    }


def _destination(
    latitude: float,
    longitude: float,
    distance_miles: float,
    bearing_deg: float,
) -> tuple[float, float]:
    distance_meters = distance_miles * _METERS_PER_MILE
    angular = distance_meters / _EARTH_RADIUS_METERS
    lat1 = math.radians(latitude)
    lon1 = math.radians(longitude)
    bearing = math.radians(bearing_deg)
    lat2 = math.asin(
        math.sin(lat1) * math.cos(angular)
        + math.cos(lat1) * math.sin(angular) * math.cos(bearing)
    )
    lon2 = lon1 + math.atan2(
        math.sin(bearing) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lon2)


def _normalized_bearing(degrees: float) -> float:
    """Swift `(truncatingRemainder(360) + 360).truncatingRemainder(360)`."""
    remainder = math.fmod(degrees, 360.0)
    return math.fmod(remainder + 360.0, 360.0)
