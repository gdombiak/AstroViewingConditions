"""Coherent Best Nearby public-score composition over injected score facts."""
from __future__ import annotations

from typing import Any, Mapping, NamedTuple, Sequence

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.grid import CONTRACT_POINT_CAP
from astro_engine.validate import require_int

CAPABILITY_ID = "location.compose_scores"
MAX_CANDIDATE_COUNT = CONTRACT_POINT_CAP


class NoScorableLocationsError(ValidationError):
    """Valid composition input had no candidate with nighttime rows."""

    code = "no_scorable_locations"


class ObservingQualityInput(NamedTuple):
    score: int
    has_valid_light_pollution: bool


class Candidate(NamedTuple):
    is_center: bool
    night_conditions_score: int
    has_nighttime_rows: bool
    observing_quality: ObservingQualityInput


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def _boolean(value: Any) -> bool:
    if not isinstance(value, bool):
        raise _invalid()
    return value


def _score(value: Any) -> int:
    try:
        result = require_int(value, "score")
    except ValidationError as exc:
        raise _invalid() from exc
    if result < 0 or result > 100:
        raise _invalid()
    return result


def _parse_candidate(value: Any) -> Candidate:
    if not isinstance(value, Mapping) or set(value) != {
        "is_center", "night_conditions_score", "has_nighttime_rows", "observing_quality"
    }:
        raise _invalid()
    observing_quality = value["observing_quality"]
    if not isinstance(observing_quality, Mapping) or set(observing_quality) != {
        "score", "has_valid_light_pollution"
    }:
        raise _invalid()
    return Candidate(
        is_center=_boolean(value["is_center"]),
        night_conditions_score=_score(value["night_conditions_score"]),
        has_nighttime_rows=_boolean(value["has_nighttime_rows"]),
        observing_quality=ObservingQualityInput(
            score=_score(observing_quality["score"]),
            has_valid_light_pollution=_boolean(
                observing_quality["has_valid_light_pollution"]
            ),
        ),
    )


def compose(candidates: Sequence[Candidate]) -> dict[str, Any]:
    """Return survivors in caller order with one coherent score mode."""
    if sum(candidate.is_center for candidate in candidates) > 1:
        raise _invalid()
    if any(
        not 0 <= candidate.night_conditions_score <= 100
        or not 0 <= candidate.observing_quality.score <= 100
        for candidate in candidates
    ):
        raise _invalid()
    scorable = [
        (index, candidate)
        for index, candidate in enumerate(candidates)
        if candidate.has_nighttime_rows
    ]
    if not scorable:
        raise NoScorableLocationsError("no scorable locations")

    use_observing_quality = all(
        candidate.observing_quality.has_valid_light_pollution
        for _, candidate in scorable
    )
    mode = (
        "observing_quality" if use_observing_quality else "night_conditions_fallback"
    )

    def public_score(candidate: Candidate) -> int:
        return (
            candidate.observing_quality.score
            if use_observing_quality
            else candidate.night_conditions_score
        )

    center_score = next(
        (public_score(candidate) for _, candidate in scorable if candidate.is_center),
        None,
    )
    return {
        "scoring_mode": mode,
        "candidates": [
            {
                "input_index": index,
                "public_score": public_score(candidate),
                "improvement_over_center": (
                    None
                    if center_score is None
                    else public_score(candidate) - center_score
                ),
            }
            for index, candidate in scorable
        ],
    }


def compose_location_scores(input: Mapping[str, Any] | Any) -> dict[str, Any]:
    """Strict JSON transport for location.compose_scores."""
    if not isinstance(input, Mapping) or set(input) != {"candidates"}:
        raise _invalid()
    rows = input["candidates"]
    if not isinstance(rows, list):
        raise _invalid()
    if len(rows) > MAX_CANDIDATE_COUNT:
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 candidate-row cap "
            f"({MAX_CANDIDATE_COUNT} rows)"
        )
    return compose([_parse_candidate(row) for row in rows])
