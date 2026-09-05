from __future__ import annotations

import math

import pytest

from astro_engine.errors import ValidationError
from astro_engine.fog import score_fog


def test_humidity_80_is_zero_and_omits_factor() -> None:
    result = score_fog(
        {
            "humidity": 80,
            "temperature": 15.0,
            "dew_point": 12.0,
            "visibility": 10000,
            "wind_speed": 5.0,
        }
    )
    assert result == {"score": 0, "factors": []}


def test_humidity_95_and_96_truncation() -> None:
    base = {
        "temperature": 15.0,
        "dew_point": 12.0,
        "visibility": 10000,
        "wind_speed": 5.0,
    }
    assert score_fog({**base, "humidity": 95}) == {
        "score": 30,
        "factors": ["high_humidity"],
    }
    assert score_fog({**base, "humidity": 96}) == {
        "score": 32,
        "factors": ["high_humidity"],
    }


def test_missing_dew_point_skips_spread_term() -> None:
    result = score_fog(
        {
            "humidity": 80,
            "temperature": 15.0,
            "visibility": 10000,
            "wind_speed": 5.0,
        }
    )
    assert result["score"] == 0
    assert result["factors"] == []


def test_visibility_1000_is_not_strictly_below() -> None:
    result = score_fog(
        {
            "humidity": 80,
            "temperature": 15.0,
            "dew_point": 12.0,
            "visibility": 1000,
            "wind_speed": 5.0,
        }
    )
    assert result["score"] == 0
    assert "low_visibility" not in result["factors"]


def test_wind_3_skips_term_wind_0_adds_15() -> None:
    base = {
        "humidity": 80,
        "temperature": 15.0,
        "dew_point": 12.0,
        "visibility": 10000,
    }
    assert score_fog({**base, "wind_speed": 3.0})["score"] == 0
    assert score_fog({**base, "wind_speed": 0.0}) == {
        "score": 15,
        "factors": ["low_wind"],
    }


def test_all_maxima_clamp_to_100() -> None:
    result = score_fog(
        {
            "humidity": 100,
            "temperature": 10.0,
            "dew_point": 10.0,
            "visibility": 0,
            "low_cloud_cover": 100,
            "wind_speed": 0.0,
        }
    )
    assert result["score"] == 100
    assert result["factors"] == [
        "high_humidity",
        "low_temp_dew_diff",
        "low_visibility",
        "high_low_cloud",
        "low_wind",
    ]


def test_boolean_humidity_is_rejected() -> None:
    with pytest.raises(ValidationError, match="humidity"):
        score_fog({"humidity": True, "temperature": 15.0, "wind_speed": 5.0})


def test_non_finite_temperature_is_rejected() -> None:
    with pytest.raises(ValidationError, match="temperature"):
        score_fog({"humidity": 80, "temperature": math.inf, "wind_speed": 5.0})


def test_explicit_null_dew_point_is_omitted() -> None:
    result = score_fog(
        {
            "humidity": 80,
            "temperature": 15.0,
            "dew_point": None,
            "visibility": 10000,
            "wind_speed": 5.0,
        }
    )
    assert result["score"] == 0
