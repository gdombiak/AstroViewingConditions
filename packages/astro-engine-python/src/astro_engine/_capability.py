"""Library capability dispatch shared by tests/parity and the public CLI.

The public CLI allow-list lives in `cli.py` and is an explicit subset gate.
This module owns capability execution, including confined `$ref` expansion
under `contracts/fixtures`. Host atlas paths are injected explicitly; they
are never read from JSON.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

from astro_engine.deep_sky_observation import (
    CAPABILITY_IDS as DEEP_SKY_IDS,
    evaluate_deep_sky_observation,
)
from astro_engine.moon_observation import CAPABILITY_ID as MOON_OBSERVATION_ID
from astro_engine.moon_recommendation import (
    CAPABILITY_ID as MOON_RECOMMENDATION_ID,
    recommend_moon,
)
from astro_engine.target_metadata import CAPABILITY_IDS as METADATA_IDS, evaluate_metadata
from astro_engine.observing_window import CAPABILITY_ID as WINDOW_ID, select_observing_window
from astro_engine.targets import CAPABILITY_ID as TARGETS_ID, recommend_targets
from astro_engine.equipment import CAPABILITY_ID as EQUIPMENT_ID, match_equipment
from astro_engine.catalog import CAPABILITY_ID as CATALOG_ID, catalog_deep_sky
from astro_engine.contracts import load_fixture_ref, resolve_fixture_ref
from astro_engine.errors import AtlasInvalidError, ValidationError
from astro_engine.fog import CAPABILITY_ID as FOG_ID, score_fog
from astro_engine.grid import CAPABILITY_ID as GRID_ID, location_grid
from astro_engine.location_compare import (
    CAPABILITY_ID as COMPARE_ID,
    compare_locations,
)
from astro_engine.iss import CAPABILITY_ID as ISS_ID, decode_iss
from astro_engine.light_pollution import (
    CAPABILITY_ID as LP_ID,
    LightPollutionArtifact,
    LightPollutionArtifactError,
)
from astro_engine.night_conditions import (
    ANALYZE_CAPABILITY_ID,
    SCORE_CAPABILITY_ID,
    analyze_night_conditions,
    public_night_score,
)
from astro_engine.observing_quality import CAPABILITY_ID as OQ_ID, assess_observing_quality
from astro_engine.seeing import CAPABILITY_ID as SEEING_ID, seeing_penalty
from astro_engine.transparency import CAPABILITY_ID as TRANSPARENCY_ID, transparency_penalty
from astro_engine.validate import require_finite_number
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

DETERMINISTIC_CAPABILITY_IDS = (
    WINDOW_ID, GRID_ID, COMPARE_ID, CATALOG_ID, TARGETS_ID, EQUIPMENT_ID, *DEEP_SKY_IDS,
    MOON_RECOMMENDATION_ID,
)

LOOKUP_CAPABILITY_IDS = (LP_ID,)


@dataclass(frozen=True)
class CapabilityHost:
    """Host-provided inputs that are not part of the JSON envelope.

    `atlas_path` is an operator override or the host-resolved production
    default LPATLAS1 file. It is never taken from JSON. Fixture `$ref`
    stays under `contracts/fixtures` and does not use this field.
    `ephemeris_path` is a local astronomy kernel override. None uses installed
    skyfield-data; it is never taken from JSON or downloaded by execution.
    """

    atlas_path: Path | str | None = None
    ephemeris_path: Path | str | None = None


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


def _artifact_ref_bytes(injected: Mapping[str, Any]) -> bytes:
    """Load an LPATLAS1 artifact from a confined `injected.artifact.$ref`."""
    artifact = injected.get("artifact")
    if not isinstance(artifact, Mapping):
        raise ValidationError("injected.artifact must be an object")
    if list(artifact.keys()) != ["$ref"]:
        raise ValidationError(
            "injected.artifact must be a confined {$ref} under contracts/fixtures"
        )
    ref = artifact["$ref"]
    if not isinstance(ref, str):
        raise ValidationError("injected.artifact.$ref must be a string")
    return resolve_fixture_ref(ref).read_bytes()


def _host_atlas_bytes(path: Path | str) -> bytes:
    candidate = Path(path)
    try:
        if not candidate.is_file():
            raise ValidationError(f"atlas file is missing: {candidate}")
        return candidate.read_bytes()
    except ValidationError:
        raise
    except OSError as exc:
        raise ValidationError(f"cannot read atlas file: {exc}") from exc


def _atlas_bytes(injected: Mapping[str, Any], host: CapabilityHost | None) -> bytes:
    has_artifact = "artifact" in injected
    host_path = host.atlas_path if host is not None else None
    if has_artifact and host_path is not None:
        raise ValidationError(
            "injected.artifact cannot be combined with a host atlas path"
        )
    if has_artifact:
        return _artifact_ref_bytes(injected)
    if host_path is not None:
        return _host_atlas_bytes(host_path)
    raise ValidationError(
        "light_pollution.lookup requires injected.artifact.$ref or a host atlas"
    )


def _light_pollution_lookup(
    injected: Mapping[str, Any],
    host: CapabilityHost | None,
) -> dict[str, Any]:
    latitude = require_finite_number(injected.get("latitude"), "latitude")
    longitude = require_finite_number(injected.get("longitude"), "longitude")
    try:
        artifact = LightPollutionArtifact.from_bytes(_atlas_bytes(injected, host))
    except LightPollutionArtifactError as exc:
        raise AtlasInvalidError(str(exc)) from exc
    return {"modeled_zenith_sky_brightness": artifact.lookup(latitude, longitude)}


def evaluate_capability(
    capability: str,
    document: Mapping[str, Any],
    *,
    host: CapabilityHost | None = None,
) -> dict[str, Any]:
    """Return the domain `result` object for a library/parity capability.

    Raises ValidationError on input failure. Unknown IDs raise ValidationError
    with a distinct message so tests can tell them apart from CLI usage (exit 3).
    `host` carries operator/default atlas paths; parity/tests omit it and use
    confined `$ref` instead.
    """
    if not isinstance(document, Mapping):
        raise ValidationError("input JSON must be an object")
    if "capability" in document and document["capability"] != capability:
        raise ValidationError("input capability does not match the invoked capability-id")

    if capability in ("astronomy.sun_events", "astronomy.moon_info", "astronomy.moon_series"):
        if set(document) - {"capability", "injected"}:
            raise ValidationError("invalid astronomy envelope")
        from astro_engine.astronomy import evaluate_astronomy
        return evaluate_astronomy(capability, _injected(document),
                                  ephemeris_path=host.ephemeris_path if host else None)
    if capability == MOON_OBSERVATION_ID:
        if set(document) - {"capability", "injected"}:
            raise ValidationError("invalid astronomy envelope")
        from astro_engine.moon_observation import evaluate_moon_observation
        return evaluate_moon_observation(_injected(document))
    if capability == MOON_RECOMMENDATION_ID:
        return recommend_moon(_injected(document))
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
    if capability == COMPARE_ID:
        return compare_locations(_injected(document))
    if capability in METADATA_IDS:
        return evaluate_metadata(capability, _injected(document))
    if capability in DEEP_SKY_IDS:
        return evaluate_deep_sky_observation(capability, _injected(document))
    if capability == WINDOW_ID:
        return select_observing_window(_injected(document))
    if capability == TARGETS_ID:
        return recommend_targets(_injected(document))
    if capability == EQUIPMENT_ID:
        return match_equipment(_injected(document))
    if capability == CATALOG_ID:
        return catalog_deep_sky(_injected(document))
    if capability == LP_ID:
        return _light_pollution_lookup(_injected(document), host)
    raise ValidationError(f"unknown scoring capability: {capability}")


def evaluate_scoring_capability(
    capability: str,
    document: Mapping[str, Any],
    *,
    host: CapabilityHost | None = None,
) -> dict[str, Any]:
    """Return the domain `result` object. Includes Phase 8 decode IDs."""
    return evaluate_capability(capability, document, host=host)
