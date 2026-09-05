from __future__ import annotations

import math
from copy import deepcopy

import pytest

from astro_engine.errors import ValidationError
from astro_engine.night_conditions import analyze_night_conditions, public_night_score


def _base_document() -> dict:
    return {
        "capability": "night_conditions.analyze",
        "clock": "2026-03-01T12:00:00Z",
        "time_zone": "UTC",
        "injected": {
            "night_window": {
                "start": "2026-03-01T20:00:00Z",
                "end": "2026-03-02T05:00:00Z",
            },
            "forecasts": [],
            "moon_series": [],
        },
    }


def _hour(time: str, **overrides: object) -> dict:
    row = {
        "time": time,
        "cloud_cover": 0,
        "humidity": 0,
        "wind_speed": 3.0,
        "wind_direction": 0,
        "temperature": 15.0,
    }
    row.update(overrides)
    return row


def _moon(time: str, **overrides: object) -> dict:
    row = {"time": time, "altitude_deg": -10.0, "illumination_pct": 0}
    row.update(overrides)
    return row


def test_empty_night_uses_injected_window_and_public_20() -> None:
    result = analyze_night_conditions(_base_document())
    assert result["rating"] == "poor"
    assert result["hourly_ratings"] == []
    assert result["trend"] == "stable"
    assert result["first_half_score"] is None
    assert result["second_half_score"] is None
    assert result["public_score"] == 20
    assert result["night_start"] == "2026-03-01T20:00:00Z"
    assert result["night_end"] == "2026-03-02T05:00:00Z"
    assert result["details"]["moon_illumination_avg"] == 0
    assert "seeing_score_avg" not in result["details"]
    assert "transparency_score_avg" not in result["details"]
    assert "best_window" not in result
    assert "summary" not in result


def test_missing_clock_and_offset_clock_are_validation() -> None:
    missing = _base_document()
    del missing["clock"]
    with pytest.raises(ValidationError, match="clock"):
        analyze_night_conditions(missing)
    offset = _base_document()
    offset["clock"] = "2026-03-01T12:00:00-08:00"
    with pytest.raises(ValidationError, match="clock"):
        analyze_night_conditions(offset)
    plus_utc = _base_document()
    plus_utc["clock"] = "2026-03-01T12:00:00+00:00"
    with pytest.raises(ValidationError, match="clock"):
        analyze_night_conditions(plus_utc)


def test_time_zone_must_be_valid_iana() -> None:
    missing = _base_document()
    del missing["time_zone"]
    with pytest.raises(ValidationError, match="time_zone"):
        analyze_night_conditions(missing)
    invalid = _base_document()
    invalid["time_zone"] = "Not/AZone"
    with pytest.raises(ValidationError, match="time_zone"):
        analyze_night_conditions(invalid)
    offset = _base_document()
    offset["time_zone"] = "-08:00"
    with pytest.raises(ValidationError, match="time_zone"):
        analyze_night_conditions(offset)
    valid = _base_document()
    valid["time_zone"] = "America/Los_Angeles"
    analyze_night_conditions(valid)


def test_clipping_is_half_open_and_sorts() -> None:
    document = _base_document()
    document["injected"]["night_window"] = {
        "start": "2026-03-01T21:00:00Z",
        "end": "2026-03-02T00:00:00Z",
    }
    document["injected"]["forecasts"] = [
        _hour("2026-03-02T00:00:00Z"),
        _hour("2026-03-01T21:00:00Z"),
        _hour("2026-03-01T20:00:00Z", cloud_cover=100),
        _hour("2026-03-01T23:00:00Z"),
    ]
    document["injected"]["moon_series"] = [
        _moon("2026-03-01T21:00:00Z"),
        _moon("2026-03-01T23:00:00Z"),
    ]
    result = analyze_night_conditions(document)
    times = [row["time"] for row in result["hourly_ratings"]]
    assert times == ["2026-03-01T21:00:00Z", "2026-03-01T23:00:00Z"]
    assert result["night_start"] == "2026-03-01T21:00:00Z"
    assert result["night_end"] == "2026-03-01T23:00:00Z"
    assert "seeing_score" not in result["hourly_ratings"][0]
    assert result["hourly_ratings"][1]["seeing_score"] == 0.0


def test_missing_moon_timestamp_is_validation() -> None:
    document = _base_document()
    document["injected"]["forecasts"] = [
        _hour("2026-03-01T21:00:00Z"),
        _hour("2026-03-01T22:00:00Z"),
    ]
    document["injected"]["moon_series"] = [_moon("2026-03-01T21:00:00Z")]
    with pytest.raises(
        ValidationError,
        match="moon_series missing timestamp 2026-03-01T22:00:00Z",
    ):
        analyze_night_conditions(document)


def test_extra_moon_samples_are_ignored() -> None:
    document = _base_document()
    document["injected"]["forecasts"] = [_hour("2026-03-01T21:00:00Z")]
    document["injected"]["moon_series"] = [
        _moon("2026-03-01T19:00:00Z", altitude_deg=90.0, illumination_pct=100),
        _moon("2026-03-01T21:00:00Z"),
        _moon("2026-03-01T22:00:00Z", altitude_deg=90.0, illumination_pct=100),
    ]
    result = analyze_night_conditions(document)
    assert result["hourly_ratings"][0]["moon_illumination"] == 0
    assert result["hourly_ratings"][0]["moon_altitude"] == -10.0


def test_heavy_cloud_floor_and_neither_regime() -> None:
    document = _base_document()
    document["injected"]["forecasts"] = [_hour("2026-03-01T21:00:00Z", cloud_cover=80)]
    document["injected"]["moon_series"] = [_moon("2026-03-01T21:00:00Z")]
    result = analyze_night_conditions(document)
    assert result["hourly_ratings"][0]["score"] == pytest.approx(1.1)
    assert result["rating"] == "poor"
    assert result["public_score"] == 19
    assert "seeing_score" not in result["hourly_ratings"][0]
    assert "transparency_score" not in result["hourly_ratings"][0]


def test_three_hours_halves_are_zero_not_null() -> None:
    document = _base_document()
    times = [
        "2026-03-01T21:00:00Z",
        "2026-03-01T22:00:00Z",
        "2026-03-01T23:00:00Z",
    ]
    document["injected"]["forecasts"] = [_hour(time) for time in times]
    document["injected"]["moon_series"] = [_moon(time) for time in times]
    result = analyze_night_conditions(document)
    assert result["trend"] == "stable"
    assert result["first_half_score"] == 0.0
    assert result["second_half_score"] == 0.0


def test_public_score_truncates_toward_zero() -> None:
    assert public_night_score("excellent", [0.15]) == {"score": 98}
    assert public_night_score("poor", [2, 2]) == {"score": 10}
    assert public_night_score("poor", []) == {"score": 20}
    assert public_night_score("excellent", [0, 0, 0, 0]) == {"score": 100}


def test_boolean_and_non_finite_forecast_numbers_rejected() -> None:
    document = _base_document()
    document["injected"]["forecasts"] = [_hour("2026-03-01T21:00:00Z", humidity=True)]
    document["injected"]["moon_series"] = [_moon("2026-03-01T21:00:00Z")]
    with pytest.raises(ValidationError):
        analyze_night_conditions(document)
    document = _base_document()
    document["injected"]["forecasts"] = [
        _hour("2026-03-01T21:00:00Z", temperature=math.inf)
    ]
    document["injected"]["moon_series"] = [_moon("2026-03-01T21:00:00Z")]
    with pytest.raises(ValidationError):
        analyze_night_conditions(document)


def test_clock_is_not_used_for_clipping() -> None:
    document = deepcopy(_base_document())
    document["clock"] = "1999-01-01T00:00:00Z"
    document["injected"]["forecasts"] = [_hour("2026-03-01T21:00:00Z")]
    document["injected"]["moon_series"] = [_moon("2026-03-01T21:00:00Z")]
    result = analyze_night_conditions(document)
    assert result["night_start"] == "2026-03-01T21:00:00Z"
    assert len(result["hourly_ratings"]) == 1
