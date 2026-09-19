"""location.compare — production Best Nearby total order with injected suitability.

Consumes already-scored candidates. Does not geocode, fetch weather, sample
astronomy, or generate location grids. Suitability is an overlay array of {key, suitability} entries keyed by
caller-supplied candidate key; omitted overlay defaults every candidate to
unchecked. JSON object maps are rejected because Swift [String: Any]
collapses canonically equivalent keys. night_conditions_score is required and is not inferred from
public_score. Final tie-break is lexicographic UTF-8 bytes of key.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import cmp_to_key
from typing import Any, Mapping

from astro_engine.errors import ValidationError
from astro_engine.validate import require_finite_number, require_int

CAPABILITY_ID = "location.compare"

SUITABILITY_RANK = {
    "suitable": 0,
    "unknown": 1,
    "unchecked": 2,
    "unsuitable": 3,
}
_SUITABILITY_VALUES = frozenset(SUITABILITY_RANK)


@dataclass(frozen=True)
class LocationCompareCandidate:
    key: str
    public_score: int
    night_conditions_score: int
    avg_cloud_cover: float
    fog_score: int
    avg_wind_speed: float
    distance_miles: float
    latitude: float
    longitude: float
    suitability: str = "unchecked"


def is_higher_ranked(
    lhs: LocationCompareCandidate,
    rhs: LocationCompareCandidate,
    *,
    use_key: bool = True,
) -> bool:
    """True when lhs ranks above rhs.

    Production keys match BestSpotSearcher.isHigherRanked. `use_key` is the
    contract-only final tie-breaker: lexicographic UTF-8 bytes of `key`.
    """
    if lhs.public_score != rhs.public_score:
        return lhs.public_score > rhs.public_score
    if lhs.avg_cloud_cover != rhs.avg_cloud_cover:
        return lhs.avg_cloud_cover < rhs.avg_cloud_cover
    if lhs.fog_score != rhs.fog_score:
        return lhs.fog_score < rhs.fog_score
    if lhs.avg_wind_speed != rhs.avg_wind_speed:
        return lhs.avg_wind_speed < rhs.avg_wind_speed
    lhs_rank = SUITABILITY_RANK[lhs.suitability]
    rhs_rank = SUITABILITY_RANK[rhs.suitability]
    if lhs_rank != rhs_rank:
        return lhs_rank < rhs_rank
    if lhs.distance_miles != rhs.distance_miles:
        return lhs.distance_miles < rhs.distance_miles
    if lhs.latitude != rhs.latitude:
        return lhs.latitude < rhs.latitude
    if lhs.longitude != rhs.longitude:
        return lhs.longitude < rhs.longitude
    if use_key:
        return key_is_less(lhs.key, rhs.key)
    return False


def key_is_less(lhs: str, rhs: str) -> bool:
    """Lexicographic UTF-8 byte order. Not Unicode collation, not locale."""
    return lhs.encode("utf-8") < rhs.encode("utf-8")


def compare_locations(inputs: Mapping[str, Any] | Any) -> dict[str, Any]:
    """Capability wrapper. `inputs` is the injected object."""
    if not isinstance(inputs, Mapping):
        raise ValidationError("location.compare input must be an object")
    candidates = _decode_candidates(inputs)
    ranked = sorted(
        candidates,
        key=cmp_to_key(
            lambda left, right: (
                -1
                if is_higher_ranked(left, right)
                else 1 if is_higher_ranked(right, left) else 0
            )
        ),
    )
    return {
        "ranking": [item.key for item in ranked],
        "locations": [_encode(item) for item in ranked],
    }


def _decode_candidates(injected: Mapping[str, Any]) -> list[LocationCompareCandidate]:
    rows = injected.get("candidates")
    if not isinstance(rows, list):
        raise ValidationError("injected.candidates must be an array")
    overlay = _decode_overlay(injected.get("suitability"))
    candidates: list[LocationCompareCandidate] = []
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, Mapping):
            raise ValidationError("candidates must be objects")
        key = _decode_key(row.get("key"))
        if key in seen:
            raise ValidationError(f"duplicate candidate key: {key}")
        seen.add(key)
        public_score = require_int(row.get("public_score"), "public_score")
        night_score = require_int(row.get("night_conditions_score"), "night_conditions_score")
        candidate = LocationCompareCandidate(
            key=key,
            public_score=public_score,
            night_conditions_score=night_score,
            avg_cloud_cover=require_finite_number(row.get("avg_cloud_cover"), "avg_cloud_cover"),
            fog_score=require_int(row.get("fog_score"), "fog_score"),
            avg_wind_speed=require_finite_number(row.get("avg_wind_speed"), "avg_wind_speed"),
            distance_miles=require_finite_number(row.get("distance_miles"), "distance_miles"),
            latitude=require_finite_number(row.get("latitude"), "latitude"),
            longitude=require_finite_number(row.get("longitude"), "longitude"),
            suitability=overlay.get(key, "unchecked"),
        )
        candidates.append(candidate)
    for overlay_key in overlay:
        if overlay_key not in seen:
            raise ValidationError(f"unknown suitability key: {overlay_key}")
    return candidates


def _decode_overlay(value: Any) -> dict[str, str]:
    if value is None:
        return {}
    if not isinstance(value, list):
        raise ValidationError("suitability must be an array")
    overlay: dict[str, str] = {}
    for row in value:
        if not isinstance(row, Mapping):
            raise ValidationError("suitability entries must be objects")
        key = _decode_key(row.get("key"))
        raw = row.get("suitability")
        if not isinstance(raw, str) or raw not in _SUITABILITY_VALUES:
            raise ValidationError(
                "suitability value must be suitable, unknown, unchecked, or unsuitable"
            )
        if key in overlay:
            raise ValidationError(f"duplicate candidate key: {key}")
        overlay[key] = raw
    return overlay


def _decode_key(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise ValidationError("candidate key is required")
    return value


def _encode(candidate: LocationCompareCandidate) -> dict[str, Any]:
    return {
        "key": candidate.key,
        "public_score": candidate.public_score,
        "night_conditions_score": candidate.night_conditions_score,
        "avg_cloud_cover": candidate.avg_cloud_cover,
        "fog_score": candidate.fog_score,
        "avg_wind_speed": candidate.avg_wind_speed,
        "suitability": candidate.suitability,
        "distance_miles": candidate.distance_miles,
        "latitude": candidate.latitude,
        "longitude": candidate.longitude,
    }
