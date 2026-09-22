"""Compose saved telescope and eyepiece state with engine optical facts.

Host resolves inventory and passes explicit numbers through. It does not
divide focal lengths, apertures, or apparent fields.
"""

from __future__ import annotations

from astro_engine.errors import ValidationError
from astro_engine.optics import calculate_optics

from astro_host.equipment import EquipmentStore
from astro_host.errors import InvalidRequestError
from astro_host.eyepieces import EyepieceStore
from astro_host.models import EquipmentType, SavedEquipment, SavedEyepiece


def optical_facts(
    *,
    telescope_focal_length_mm: float | None,
    eyepiece_focal_length_mm: float | None,
    telescope_aperture_mm: float | None,
    afov_degrees: float | None,
) -> dict[str, float | None]:
    """Return the engine result for one combination. Missing numbers stay omitted."""
    payload: dict[str, float] = {}
    if telescope_focal_length_mm is not None:
        payload["telescope_focal_length_mm"] = telescope_focal_length_mm
    if eyepiece_focal_length_mm is not None:
        payload["eyepiece_focal_length_mm"] = eyepiece_focal_length_mm
    if telescope_aperture_mm is not None:
        payload["telescope_aperture_mm"] = telescope_aperture_mm
    if afov_degrees is not None:
        payload["afov_degrees"] = afov_degrees
    try:
        result = calculate_optics(payload)
    except ValidationError as exc:
        raise InvalidRequestError("invalid optics.calculate input") from exc
    return result


def explicit_optics(
    *,
    telescope_focal_length_mm: float | None,
    eyepiece_focal_length_mm: float | None,
    telescope_aperture_mm: float | None,
    afov_degrees: float | None,
) -> dict[str, object]:
    facts = optical_facts(
        telescope_focal_length_mm=telescope_focal_length_mm,
        eyepiece_focal_length_mm=eyepiece_focal_length_mm,
        telescope_aperture_mm=telescope_aperture_mm,
        afov_degrees=afov_degrees,
    )
    return {
        "telescope": {
            "id": None,
            "name": None,
            "type": None,
            "aperture_mm": telescope_aperture_mm,
            "focal_length_mm": telescope_focal_length_mm,
        },
        "combinations": [
            {
                "eyepiece": {
                    "id": None,
                    "name": None,
                    "focal_length_mm": eyepiece_focal_length_mm,
                    "afov_degrees": afov_degrees,
                    "aliases": [],
                },
                "optics": facts,
            }
        ],
    }


def saved_optics(
    equipment: EquipmentStore,
    eyepieces: EyepieceStore,
    *,
    telescope_id: str | None = None,
    telescope_query: str | None = None,
    eyepiece_id: str | None = None,
    eyepiece_query: str | None = None,
    all_eyepieces: bool = False,
) -> dict[str, object]:
    telescope = (
        equipment.get(telescope_id)
        if telescope_id is not None
        else equipment.resolve(telescope_query or "")
    )
    if telescope.type is not EquipmentType.VISUAL_TELESCOPE:
        raise InvalidRequestError(
            "saved eyepiece optics require a visual telescope"
        )
    if all_eyepieces:
        selected = eyepieces.list()
    elif eyepiece_id is not None:
        selected = (eyepieces.get(eyepiece_id),)
    else:
        selected = (eyepieces.resolve(eyepiece_query or ""),)
    return {
        "telescope": _public_telescope(telescope),
        "combinations": [
            {
                "eyepiece": _public_eyepiece(eyepiece),
                "optics": optical_facts(
                    telescope_focal_length_mm=telescope.focal_length_mm,
                    eyepiece_focal_length_mm=eyepiece.focal_length_mm,
                    telescope_aperture_mm=telescope.aperture_mm,
                    afov_degrees=eyepiece.afov_degrees,
                ),
            }
            for eyepiece in selected
        ],
    }


def _public_telescope(item: SavedEquipment) -> dict[str, object]:
    return {
        "id": item.id,
        "name": item.name,
        "type": item.type.value,
        "aperture_mm": item.aperture_mm,
        "focal_length_mm": item.focal_length_mm,
    }


def _public_eyepiece(item: SavedEyepiece) -> dict[str, object]:
    return {
        "id": item.id,
        "name": item.name,
        "focal_length_mm": item.focal_length_mm,
        "afov_degrees": item.afov_degrees,
        "aliases": list(item.aliases),
    }
