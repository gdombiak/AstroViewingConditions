"""optics.calculate — deterministic telescope and eyepiece arithmetic.

Magnification, exit pupil, and approximate true field of view are pure
ratios of explicit inputs. Missing inputs stay null. This capability does
not rank eyepieces or look up product specifications.
"""

from __future__ import annotations

import math
from typing import Any, Mapping

from astro_engine.errors import ValidationError
from astro_engine.validate import optional_finite_number

CAPABILITY_ID = "optics.calculate"
_FIELDS = frozenset({
    "telescope_focal_length_mm",
    "eyepiece_focal_length_mm",
    "telescope_aperture_mm",
    "afov_degrees",
})
_MAX_AFOV_DEGREES = 180.0


def calculate_optics(inputs: Mapping[str, Any] | Any) -> dict[str, float | None]:
    """Return magnification, exit pupil, and approximate true field."""
    if not isinstance(inputs, Mapping) or set(inputs) - _FIELDS:
        raise ValidationError("invalid optics.calculate input")
    try:
        telescope_focal_length = _positive(
            inputs.get("telescope_focal_length_mm"), "telescope_focal_length_mm"
        )
        eyepiece_focal_length = _positive(
            inputs.get("eyepiece_focal_length_mm"), "eyepiece_focal_length_mm"
        )
        aperture = _positive(inputs.get("telescope_aperture_mm"), "telescope_aperture_mm")
        afov = _afov(inputs.get("afov_degrees"))
    except ValidationError as exc:
        raise ValidationError("invalid optics.calculate input") from exc
    magnification = None
    if telescope_focal_length is not None and eyepiece_focal_length is not None:
        magnification = telescope_focal_length / eyepiece_focal_length
    exit_pupil = None
    if magnification is not None and aperture is not None:
        exit_pupil = aperture / magnification
    true_field = None
    if magnification is not None and afov is not None:
        true_field = afov / magnification
    return {
        "magnification": magnification,
        "exit_pupil_mm": exit_pupil,
        "approximate_true_field_of_view_degrees": true_field,
    }


def _positive(value: Any, name: str) -> float | None:
    number = optional_finite_number(value, name)
    if number is None:
        return None
    if number <= 0 or math.isnan(number):
        raise ValidationError(f"{name} must be greater than zero")
    return number


def _afov(value: Any) -> float | None:
    number = _positive(value, "afov_degrees")
    if number is None:
        return None
    if number > _MAX_AFOV_DEGREES:
        raise ValidationError("afov_degrees must be at most 180")
    return number
