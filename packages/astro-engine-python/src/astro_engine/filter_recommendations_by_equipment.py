"""Equipment filtering over an already conditions-ranked recommendation list."""
from __future__ import annotations

from typing import Any, Mapping, NamedTuple, Sequence

from astro_engine.contracts import load_canonical_data
from astro_engine.equipment import (
    _parse_capabilities,
    _parse_requirement,
    _ranked_candidates,
)
from astro_engine.errors import SampleCapError, ValidationError

CAPABILITY_ID = "targets.filter_recommendations_by_equipment"
MAX_CANDIDATE_COUNT = 1_440
MAX_CAPABILITY_COUNT = 1_440

THRESHOLDS = ("any", "challengingOrBetter", "goodOrBetter", "excellentOnly")
REQUIREMENT_KEYS = {
    "naked_eye_suitability",
    "binocular_suitability",
    "preferred_binocular_magnification",
    "practical_binocular_aperture_mm",
    "preferred_binocular_aperture_mm",
    "practical_visual_aperture_mm",
    "preferred_visual_aperture_mm",
    "practical_smart_eaa_aperture_mm",
    "preferred_smart_eaa_aperture_mm",
    "framing",
    "magnification_benefit",
    "smart_eaa_suitability",
}


class Candidate(NamedTuple):
    key: str
    is_planet: bool
    requirement: dict


class Selection(NamedTuple):
    index: int
    key: str


def includes(minimum_fit: str, level: str) -> bool:
    if minimum_fit == "any":
        return True
    if minimum_fit == "challengingOrBetter":
        return level != "poor"
    if minimum_fit == "goodOrBetter":
        return level in ("excellent", "good")
    return level == "excellent"


def selected(
    candidates: Sequence[Candidate],
    capabilities: Sequence[tuple[str, str, float | None, float | None]],
    has_saved_inventory: bool,
    minimum_fit: str,
) -> list[Selection]:
    """Return original identities in original order; never sort or deduplicate."""
    if not has_saved_inventory or minimum_fit == "any":
        return [Selection(index, candidate.key) for index, candidate in enumerate(candidates)]

    preferences = load_canonical_data("calibration/equipment-matching.json")["preferences"]
    result = []
    for index, candidate in enumerate(candidates):
        ranked = _ranked_candidates(
            candidate.requirement,
            capabilities,
            candidate.is_planet,
            preferences,
        )
        if ranked and includes(minimum_fit, ranked[0].level):
            result.append(Selection(index, candidate.key))
    return result


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def _boolean(value: Any) -> bool:
    if not isinstance(value, bool):
        raise _invalid()
    return value


def _key(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise _invalid()
    return value


def _parse_candidate_rows(rows: list[Any]) -> list[Candidate]:
    candidates = []
    for raw in rows:
        if not isinstance(raw, Mapping) or set(raw) != {"key", "is_planet", "requirement"}:
            raise _invalid()
        requirement = raw["requirement"]
        if not isinstance(requirement, Mapping) or set(requirement) != REQUIREMENT_KEYS:
            raise _invalid()
        try:
            parsed_requirement = _parse_requirement(requirement)
        except ValidationError as exc:
            raise _invalid() from exc
        candidates.append(Candidate(
            _key(raw["key"]),
            _boolean(raw["is_planet"]),
            parsed_requirement,
        ))
    return candidates


def filter_recommendations_by_equipment(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping) or set(input) != {
        "candidates", "capabilities", "has_saved_inventory", "minimum_fit"
    }:
        raise _invalid()

    raw_candidates = input["candidates"]
    if not isinstance(raw_candidates, list):
        raise _invalid()
    if len(raw_candidates) > MAX_CANDIDATE_COUNT:
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 candidate-row cap ({MAX_CANDIDATE_COUNT} rows)"
        )
    raw_capabilities = input["capabilities"]
    if not isinstance(raw_capabilities, list):
        raise _invalid()
    if len(raw_capabilities) > MAX_CAPABILITY_COUNT:
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 capability-row cap ({MAX_CAPABILITY_COUNT} rows)"
        )
    if any(
        not isinstance(row, Mapping)
        or set(row) != {"key", "type", "aperture_mm", "magnification"}
        for row in raw_capabilities
    ):
        raise _invalid()

    has_saved_inventory = _boolean(input["has_saved_inventory"])
    minimum_fit = input["minimum_fit"]
    if minimum_fit not in THRESHOLDS:
        raise _invalid()

    # Parse and validate both arrays even when the typed operation bypasses
    # matching. Bypass is a business decision, not a relaxed JSON schema.
    try:
        capabilities = _parse_capabilities(raw_capabilities)
    except ValidationError as exc:
        raise _invalid() from exc
    candidates = _parse_candidate_rows(raw_candidates)
    rows = selected(candidates, capabilities, has_saved_inventory, minimum_fit)
    return {"selected": [{"index": row.index, "key": row.key} for row in rows]}
