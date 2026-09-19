"""catalog.deep_sky — curated catalog from contracts/data/catalog/deep-sky.json.

One language-neutral source. No package-local copy. Validation is for corrupt
product data, not an untrusted network API.
"""

from __future__ import annotations

from typing import Any, Mapping

from astro_engine.contracts import load_canonical_data
from astro_engine.errors import ValidationError
from astro_engine.validate import optional_finite_number, require_finite_number

CAPABILITY_ID = "catalog.deep_sky"
_CANONICAL_RELATIVE = "catalog/deep-sky.json"

_OBJECT_TYPES = frozenset(
    {
        "galaxy",
        "diffuse_nebula",
        "globular_cluster",
        "open_cluster",
        "double_star",
        "planetary_nebula",
    }
)
_EQUIPMENT = frozenset({"naked_eye", "binoculars", "small_telescope", "telescope"})
_INTENTS = frozenset({"easy", "standard", "challenge"})
_REQUIRED_KEYS = frozenset(
    {
        "id",
        "common_name",
        "catalog_name",
        "object_type",
        "constellation",
        "right_ascension",
        "declination",
        "magnitude",
        "apparent_size",
        "surface_brightness",
        "difficulty",
        "recommended_equipment",
        "observing_intent",
        "notes",
    }
)
_OPTIONAL_KEYS = frozenset({"display_type_name_override"})
_ALLOWED_KEYS = _REQUIRED_KEYS | _OPTIONAL_KEYS


def load_deep_sky_catalog() -> list[dict[str, Any]]:
    """Return curated entries in canonical file order."""
    return list(_load_document()["entries"])


def catalog_deep_sky(_inputs: Mapping[str, Any] | Any = None) -> dict[str, Any]:
    """Capability wrapper. The catalog is static; injected contents are ignored."""
    return {"entries": load_deep_sky_catalog()}


def _load_document() -> dict[str, Any]:
    raw = load_canonical_data(_CANONICAL_RELATIVE)
    if not isinstance(raw, Mapping):
        raise ValidationError("deep-sky catalog must be a JSON object")
    entries = raw.get("entries")
    if not isinstance(entries, list):
        raise ValidationError("deep-sky catalog entries must be an array")
    extra = set(raw) - {"entries"}
    if extra:
        raise ValidationError(
            f"unexpected deep-sky catalog keys: {sorted(extra)}"
        )
    return {"entries": [_validate_entry(item, index) for index, item in enumerate(entries)]}


def _validate_entry(raw: Any, index: int) -> dict[str, Any]:
    prefix = f"entries[{index}]"
    if not isinstance(raw, Mapping):
        raise ValidationError(f"{prefix} must be an object")
    extra = set(raw) - _ALLOWED_KEYS
    if extra:
        raise ValidationError(f"{prefix} unexpected keys: {sorted(extra)}")
    missing = _REQUIRED_KEYS - set(raw)
    if missing:
        raise ValidationError(f"{prefix} missing keys: {sorted(missing)}")

    entry: dict[str, Any] = {
        "id": _require_string(raw.get("id"), f"{prefix}.id"),
        "common_name": _require_string(raw.get("common_name"), f"{prefix}.common_name"),
        "catalog_name": _require_string(raw.get("catalog_name"), f"{prefix}.catalog_name"),
        "object_type": _require_enum(
            raw.get("object_type"), f"{prefix}.object_type", _OBJECT_TYPES
        ),
        "constellation": _require_string(
            raw.get("constellation"), f"{prefix}.constellation"
        ),
        "right_ascension": require_finite_number(
            raw.get("right_ascension"), f"{prefix}.right_ascension"
        ),
        "declination": require_finite_number(
            raw.get("declination"), f"{prefix}.declination"
        ),
        "magnitude": require_finite_number(raw.get("magnitude"), f"{prefix}.magnitude"),
        "apparent_size": _require_string(
            raw.get("apparent_size"), f"{prefix}.apparent_size"
        ),
        "surface_brightness": optional_finite_number(
            raw.get("surface_brightness"), f"{prefix}.surface_brightness"
        ),
        "difficulty": _clamp_unit(
            require_finite_number(raw.get("difficulty"), f"{prefix}.difficulty")
        ),
        "recommended_equipment": _require_enum(
            raw.get("recommended_equipment"),
            f"{prefix}.recommended_equipment",
            _EQUIPMENT,
        ),
        "observing_intent": _require_enum(
            raw.get("observing_intent"), f"{prefix}.observing_intent", _INTENTS
        ),
        "notes": _require_string(raw.get("notes"), f"{prefix}.notes"),
    }
    if "display_type_name_override" in raw:
        override = raw.get("display_type_name_override")
        if override is not None:
            entry["display_type_name_override"] = _require_string(
                override, f"{prefix}.display_type_name_override"
            )
    return entry


def _require_string(value: Any, name: str) -> str:
    if not isinstance(value, str):
        raise ValidationError(f"{name} must be a string")
    return value


def _require_enum(value: Any, name: str, allowed: frozenset[str]) -> str:
    text = _require_string(value, name)
    if text not in allowed:
        raise ValidationError(f"{name} is not a known catalog value")
    return text


def _clamp_unit(value: float) -> float:
    """Match DeepSkyCatalogEntry.init difficulty clamp 0...1."""
    return min(max(value, 0.0), 1.0)
