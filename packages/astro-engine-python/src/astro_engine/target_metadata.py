"""Canonical target requirements, static solar candidates and sensitivity derivation.

Normative boundaries: contracts/procedures/target-metadata.md. No astronomy.
"""
from __future__ import annotations

from typing import Any, Mapping

from astro_engine.catalog import load_deep_sky_catalog
from astro_engine.contracts import load_canonical_data
from astro_engine.errors import ValidationError
from astro_engine.validate import require_finite_number

CAPABILITY_IDS = ("targets.requirements", "catalog.solar_system", "targets.moon_sensitivity")
OBJECT_TYPES = frozenset({"galaxy", "diffuseNebula", "globularCluster", "openCluster", "doubleStar", "planetaryNebula"})
# Foundation CharacterSet.whitespacesAndNewlines, including U+200B but
# excluding Python-only control separators U+001C...U+001F.
_ID_WHITESPACE = "\t\n\v\f\r \u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u200b\u2028\u2029\u202f\u205f\u3000"
_CATALOG_TYPES = dict(zip(
    ("galaxy", "diffuse_nebula", "globular_cluster", "open_cluster", "double_star", "planetary_nebula"),
    ("galaxy", "diffuseNebula", "globularCluster", "openCluster", "doubleStar", "planetaryNebula"),
))


def solar_system_candidates() -> list[dict[str, Any]]:
    return load_canonical_data("catalog/solar-system.json")["entries"]


def resolve_requirements(id: str, type: str, object_type: str | None = None) -> dict[str, Any]:
    """Typed-host primitive; transport validation lives in evaluate_metadata."""
    data = load_canonical_data("catalog/target-requirements.json")
    id = id.strip(_ID_WHITESPACE).lower()
    if id in data["overrides"]:
        return data["overrides"][id]
    row = data["fallbacks"].get(object_type if type == "deepSky" else type, data["default"])
    if type == "planet" and id in data["naked_eye_planet_ids"]:
        row = {**row, "naked_eye_suitability": "preferred"}
    return row


def moon_sensitivity(object_type: str, surface_brightness: float | None) -> float:
    data = load_canonical_data("calibration/target-scoring.json")["moon"]["deep_sky_interference_sensitivity"]
    if object_type != "planetaryNebula":
        return data["non_planetary_nebula"]
    if surface_brightness is None:
        return data["default"]
    nebula = data["planetary_nebula_by_surface_brightness"]
    if surface_brightness <= nebula["high_surface_brightness_max"]:
        return nebula["high_surface_brightness_sensitivity"]
    if surface_brightness >= nebula["low_surface_brightness_min"]:
        return nebula["low_surface_brightness_sensitivity"]
    return nebula["mid_sensitivity"]


def evaluate_metadata(capability: str, input: Mapping[str, Any]) -> dict[str, Any]:
    def invalid():
        return ValidationError(f"invalid {capability} input")

    if not isinstance(input, Mapping):
        raise invalid()
    if capability == "catalog.solar_system":
        if input:
            raise invalid()
        return {"entries": solar_system_candidates()}
    if capability == "targets.moon_sensitivity":
        object_type = input.get("object_type")
        if set(input) - {"object_type", "surface_brightness"} or not isinstance(object_type, str) or object_type not in OBJECT_TYPES:
            raise invalid()
        brightness = input.get("surface_brightness")
        if brightness is not None:
            try:
                brightness = require_finite_number(brightness, "surface_brightness")
            except ValidationError as exc:
                raise invalid() from exc
        return {"sensitivity": moon_sensitivity(object_type, brightness)}
    if capability != "targets.requirements" or set(input) - {"id", "type", "object_type"}:
        raise invalid()
    id = input.get("id")
    if not isinstance(id, str) or not id.strip(_ID_WHITESPACE):
        raise invalid()
    id = id.strip(_ID_WHITESPACE).lower()
    if "type" in input:
        type = input["type"]
        object_type = input.get("object_type")
        if not isinstance(type, str) or type not in {"moon", "planet", "deepSky"}:
            raise invalid()
        if object_type is not None and (not isinstance(object_type, str) or object_type not in OBJECT_TYPES):
            raise invalid()
    else:
        if "object_type" in input:
            raise invalid()
        entry = next((entry for entry in load_deep_sky_catalog() if entry["id"] == id), None)
        if entry:
            type, object_type = "deepSky", _CATALOG_TYPES[entry["object_type"]]
        else:
            entry = next((entry for entry in solar_system_candidates() if entry["id"] == id), None)
            if entry is None:
                raise invalid()
            type, object_type = entry["type"], None
    return {"requirement": resolve_requirements(id, type, object_type), "is_planet": type == "planet"}
