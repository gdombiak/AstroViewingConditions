from __future__ import annotations

import math

import pytest

from astro_engine.errors import ValidationError
from astro_engine.seeing import seeing_penalty


def test_neither_component_is_null() -> None:
    assert seeing_penalty(
        {
            "current_temperature": 10,
            "previous_temperature": None,
            "wind_speed_200hpa": None,
        }
    ) == {"penalty": None}


def test_delta_inclusive_upper_bounds() -> None:
    assert seeing_penalty(
        {
            "current_temperature": 11,
            "previous_temperature": 10,
            "wind_speed_200hpa": None,
        }
    ) == {"penalty": 0.0}
    assert seeing_penalty(
        {
            "current_temperature": 12,
            "previous_temperature": 10,
            "wind_speed_200hpa": None,
        }
    ) == {"penalty": 0.5}


def test_temperature_delta_uses_absolute_difference() -> None:
    assert seeing_penalty(
        {
            "current_temperature": 10,
            "previous_temperature": 12,
            "wind_speed_200hpa": None,
        }
    ) == {"penalty": 0.5}


def test_wind_only_and_average_of_components() -> None:
    assert seeing_penalty(
        {
            "current_temperature": 10,
            "previous_temperature": None,
            "wind_speed_200hpa": 50,
        }
    ) == {"penalty": 0.0}
    assert seeing_penalty(
        {
            "current_temperature": 13,
            "previous_temperature": 10,
            "wind_speed_200hpa": 50,
        }
    ) == {"penalty": 0.5}


def test_both_max_clamp() -> None:
    assert seeing_penalty(
        {
            "current_temperature": 16,
            "previous_temperature": 10,
            "wind_speed_200hpa": 250,
        }
    ) == {"penalty": 2.0}


def test_boolean_and_non_finite_rejected() -> None:
    with pytest.raises(ValidationError):
        seeing_penalty({"current_temperature": True, "previous_temperature": 1})
    with pytest.raises(ValidationError):
        seeing_penalty(
            {
                "current_temperature": 10,
                "previous_temperature": math.nan,
            }
        )
