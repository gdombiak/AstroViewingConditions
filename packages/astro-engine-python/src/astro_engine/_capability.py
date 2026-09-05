"""Internal library dispatch for tests/parity. Not a public CLI surface."""

from __future__ import annotations

from typing import Any, Mapping

from astro_engine.catalog import CAPABILITY_ID as CATALOG_ID, catalog_deep_sky
from astro_engine.contracts import load_fixture_ref
from astro_engine.errors import ValidationError
from astro_engine.fog import CAPABILITY_ID as FOG_ID, score_fog
from astro_engine.grid import CAPABILITY_ID as GRID_ID, location_grid
from astro_engine.iss import CAPABILITY_ID as ISS_ID, decode_iss
from astro_engine.night_conditions import (
    ANALYZE_CAPABILITY_ID,
    SCORE_CAPABILITY_ID,
    analyze_night_conditions,
    public_night_score,
)
from astro_engine.observing_quality import CAPABILITY_ID as OQ_ID, assess_observing_quality
from astro_engine.seeing import CAPABILITY_ID as SEEING_ID, seeing_penalty
from astro_engine.transparency import CAPABILITY_ID as TRANSPARENCY_ID, transparency_penalty
from astro_engine.weather import CAPABILITY_ID as WEATHER_ID, decode_weather

SCORING_CAPABILITY_IDS = (
    OQ_ID,
    ANALYZE_CAPABILITY_ID,
    SCORE_CAPABILITY_ID,
    FOG_ID,
    SEEING_ID,
    TRANSPARENCY_ID,
)

DECODE_CAPABILITY_IDS = (WEATHER_ID, ISS_ID)

DETERMINISTIC_CAPABILITY_IDS = (GRID_ID, CATALOG_ID)


def _injected(document: Mapping[str, Any]) -> Mapping[str, Any]:
    injected = document.get("injected")
    if not isinstance(injected, Mapping):
        raise ValidationError("input JSON must contain an 'injected' object")
    return _resolve_injected_ref(injected)


def _resolve_injected_ref(injected: Mapping[str, Any]) -> Mapping[str, Any]:
    if list(injected.keys()) != ["$ref"]:
        return injected
    ref = injected["$ref"]
    if not isinstance(ref, str):
        raise ValidationError("injected.$ref must be a string")
    loaded = load_fixture_ref(ref)
    if not isinstance(loaded, Mapping):
        raise ValidationError("injected.$ref must resolve to an object")
    return loaded


def evaluate_capability(capability: str, document: Mapping[str, Any]) -> dict[str, Any]:
    """Return the domain `result` object for a library/parity capability.

    Raises ValidationError on input failure. Unknown IDs raise ValidationError
    with a distinct message so tests can tell them apart from CLI usage (exit 3).
    """
    if not isinstance(document, Mapping):
        raise ValidationError("input JSON must be an object")
    if "capability" in document and document["capability"] != capability:
        raise ValidationError("input capability does not match the invoked capability-id")

    if capability == OQ_ID:
        injected = _injected(document)
        if "night_conditions_score" not in injected:
            raise ValidationError("injected.night_conditions_score is required")
        return assess_observing_quality(
            injected["night_conditions_score"],
            injected.get("modeled_zenith_sky_brightness"),
        )
    if capability == ANALYZE_CAPABILITY_ID:
        return analyze_night_conditions(document)
    if capability == SCORE_CAPABILITY_ID:
        injected = _injected(document)
        return public_night_score(injected.get("rating"), injected.get("hourly_scores"))
    if capability == FOG_ID:
        return score_fog(_injected(document))
    if capability == SEEING_ID:
        return seeing_penalty(_injected(document))
    if capability == TRANSPARENCY_ID:
        return transparency_penalty(_injected(document))
    if capability == WEATHER_ID:
        return decode_weather(_injected(document))
    if capability == ISS_ID:
        return decode_iss(_injected(document))
    if capability == GRID_ID:
        return location_grid(_injected(document))
    if capability == CATALOG_ID:
        return catalog_deep_sky(_injected(document))
    raise ValidationError(f"unknown scoring capability: {capability}")


def evaluate_scoring_capability(capability: str, document: Mapping[str, Any]) -> dict[str, Any]:
    """Return the domain `result` object. Includes Phase 8 decode IDs."""
    return evaluate_capability(capability, document)
