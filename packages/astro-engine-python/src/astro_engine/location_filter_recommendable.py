"""Stable suitability-only filtering for Best Nearby candidates."""
from __future__ import annotations

from typing import Any, Mapping, Sequence

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.grid import CONTRACT_POINT_CAP

CAPABILITY_ID = "location.filter_recommendable"
MAX_CANDIDATE_COUNT = CONTRACT_POINT_CAP
SUITABILITY_VALUES = frozenset(
    {"suitable", "unknown", "unchecked", "unsuitable"}
)


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def recommendable_input_indices(suitability: Sequence[str]) -> list[int]:
    return [
        index
        for index, status in enumerate(suitability)
        if status in ("suitable", "unknown")
    ]


def filter_recommendable(input: Mapping[str, Any] | Any) -> dict[str, Any]:
    """Strict JSON transport for location.filter_recommendable."""
    if not isinstance(input, Mapping) or set(input) != {"suitability"}:
        raise _invalid()
    rows = input["suitability"]
    if not isinstance(rows, list):
        raise _invalid()
    if len(rows) > MAX_CANDIDATE_COUNT:
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 suitability-row cap "
            f"({MAX_CANDIDATE_COUNT} rows)"
        )
    if any(
        not isinstance(status, str) or status not in SUITABILITY_VALUES
        for status in rows
    ):
        raise _invalid()
    return {"recommendable_input_indices": recommendable_input_indices(rows)}
