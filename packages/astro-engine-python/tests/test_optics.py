from __future__ import annotations

import math

import pytest

from astro_engine.errors import ValidationError
from astro_engine.optics import CAPABILITY_ID, calculate_optics


def test_capability_id() -> None:
    assert CAPABILITY_ID == "optics.calculate"


def test_virtuoso_delos_reports_all_three_facts() -> None:
    result = calculate_optics({
        "telescope_focal_length_mm": 750,
        "eyepiece_focal_length_mm": 8,
        "telescope_aperture_mm": 150,
        "afov_degrees": 72,
    })
    assert result["magnification"] == pytest.approx(93.75)
    assert result["exit_pupil_mm"] == pytest.approx(1.6)
    assert result["approximate_true_field_of_view_degrees"] == pytest.approx(0.768)


def test_missing_aperture_omits_only_exit_pupil() -> None:
    result = calculate_optics({
        "telescope_focal_length_mm": 750,
        "eyepiece_focal_length_mm": 24,
        "afov_degrees": 68,
    })
    assert result["magnification"] == pytest.approx(31.25)
    assert result["exit_pupil_mm"] is None
    assert result["approximate_true_field_of_view_degrees"] == pytest.approx(2.176)


def test_missing_afov_omits_only_true_field() -> None:
    result = calculate_optics({
        "telescope_focal_length_mm": 1200,
        "eyepiece_focal_length_mm": 10,
        "telescope_aperture_mm": 200,
    })
    assert result["magnification"] == 120
    assert result["exit_pupil_mm"] == pytest.approx(200 / 120)
    assert result["approximate_true_field_of_view_degrees"] is None


def test_null_focal_length_makes_dependent_facts_unavailable() -> None:
    result = calculate_optics({
        "telescope_focal_length_mm": None,
        "eyepiece_focal_length_mm": 8,
        "telescope_aperture_mm": 150,
        "afov_degrees": 72,
    })
    assert result == {
        "magnification": None,
        "exit_pupil_mm": None,
        "approximate_true_field_of_view_degrees": None,
    }


def test_empty_input_is_unavailable_rather_than_guessed() -> None:
    assert calculate_optics({}) == {
        "magnification": None,
        "exit_pupil_mm": None,
        "approximate_true_field_of_view_degrees": None,
    }


@pytest.mark.parametrize("payload", [
    {"telescope_focal_length_mm": 0, "eyepiece_focal_length_mm": 8},
    {"telescope_focal_length_mm": -750, "eyepiece_focal_length_mm": 8},
    {"telescope_focal_length_mm": True, "eyepiece_focal_length_mm": 8},
    {"telescope_focal_length_mm": "750", "eyepiece_focal_length_mm": 8},
    {"telescope_focal_length_mm": 750, "eyepiece_focal_length_mm": 8, "name": "Delos"},
    {"afov_degrees": 0, "telescope_focal_length_mm": 750, "eyepiece_focal_length_mm": 8},
    {"afov_degrees": 180.1, "telescope_focal_length_mm": 750, "eyepiece_focal_length_mm": 8},
    {"telescope_aperture_mm": math.inf, "telescope_focal_length_mm": 750,
     "eyepiece_focal_length_mm": 8},
])
def test_invalid_input_is_rejected(payload: dict) -> None:
    with pytest.raises(ValidationError, match="invalid optics.calculate input"):
        calculate_optics(payload)


def test_apparent_field_of_180_is_accepted() -> None:
    result = calculate_optics({
        "telescope_focal_length_mm": 1000,
        "eyepiece_focal_length_mm": 10,
        "afov_degrees": 180,
    })
    assert result["approximate_true_field_of_view_degrees"] == pytest.approx(1.8)
