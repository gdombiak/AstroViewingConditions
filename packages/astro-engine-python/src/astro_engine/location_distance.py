"""location.distance — great-circle distance for arbitrary coordinates."""

from __future__ import annotations

import math
from typing import Any, Mapping

from astro_engine.errors import ValidationError
from astro_engine.grid import EARTH_RADIUS_METERS, METERS_PER_MILE
from astro_engine.validate import require_finite_number

CAPABILITY_ID = "location.distance"


def distance_miles(from_latitude: float, from_longitude: float,
                   to_latitude: float, to_longitude: float) -> float:
    """Shortest spherical arc, using the same Earth radius as location.grid."""
    lat1, lat2 = math.radians(from_latitude), math.radians(to_latitude)
    dlat = lat2 - lat1
    dlon = math.radians(to_longitude - from_longitude)
    haversine = (math.sin(dlat / 2.0) ** 2
                 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2.0) ** 2)
    haversine = min(1.0, max(0.0, haversine))
    angle = 2.0 * math.atan2(math.sqrt(haversine), math.sqrt(1.0 - haversine))
    return angle * EARTH_RADIUS_METERS / METERS_PER_MILE


def _coordinate(value: Any) -> tuple[float, float]:
    if not isinstance(value, Mapping) or set(value) != {"latitude", "longitude"}:
        raise ValidationError("invalid location.distance input")
    try:
        latitude = require_finite_number(value["latitude"], "latitude")
        longitude = require_finite_number(value["longitude"], "longitude")
    except ValidationError as exc:
        raise ValidationError("invalid location.distance input") from exc
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise ValidationError("invalid location.distance input")
    return latitude, longitude


def location_distance(input: Mapping[str, Any] | Any) -> dict[str, float]:
    if not isinstance(input, Mapping) or set(input) != {"from", "to"}:
        raise ValidationError("invalid location.distance input")
    start = _coordinate(input["from"])
    end = _coordinate(input["to"])
    return {"distance_miles": distance_miles(*start, *end)}
