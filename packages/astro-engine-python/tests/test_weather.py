from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path

import pytest

from astro_engine.contracts import contracts_root, load_fixture_ref, resolve_fixture_ref
from astro_engine.errors import FixtureRefError, ValidationError
from astro_engine.night_conditions import analyze_night_conditions
from astro_engine.weather import decode_weather

from support import load_fixture

OPEN_METEO = Path("fixtures/providers/open-meteo/forecast")
WEATHER_DECODE = Path("fixtures/capabilities/weather-decode")
NAMED_FIXTURES = (
    "happy-path",
    "missing-fields",
    "negative-values",
    "tz-from-offset-only",
    "layered-seeing-transparency",
    "short-optional-arrays",
    "malformed-time-skipped",
)


def _provider(name: str) -> dict:
    path = contracts_root() / OPEN_METEO / f"{name}.json"
    return json.loads(path.read_text(encoding="utf-8"))


def _expected(name: str) -> dict:
    return load_fixture(contracts_root() / WEATHER_DECODE / name)["expected"]["result"]


def test_named_provider_fixtures_are_contract_owned() -> None:
    root = contracts_root() / OPEN_METEO
    for name in NAMED_FIXTURES:
        path = root / f"{name}.json"
        assert path.is_file(), name
        assert "packages" not in path.parts
        assert path.parts[-4:] == ("providers", "open-meteo", "forecast", f"{name}.json")


@pytest.mark.parametrize("name", NAMED_FIXTURES)
def test_named_open_meteo_fixtures(name: str) -> None:
    result = decode_weather(_provider(name))
    assert result == _expected(name)


def test_happy_path_times_and_omits_precipitation() -> None:
    result = decode_weather(_provider("happy-path"))
    assert result["timezone"] is None
    assert result["utc_offset_seconds"] == -28800
    assert [row["time"] for row in result["hourly"]] == [
        "2026-02-19T08:00:00Z",
        "2026-02-19T09:00:00Z",
    ]
    for row in result["hourly"]:
        assert "precipitation" not in row
        assert "id" not in row


def test_tz_from_offset_only_uses_numeric_offset_and_null_timezone() -> None:
    result = decode_weather(_provider("tz-from-offset-only"))
    assert result["timezone"] is None
    assert result["utc_offset_seconds"] == -28800
    assert result["hourly"][0]["time"] == "2026-02-19T08:00:00Z"
    assert result["hourly"][1]["time"] == "2026-02-19T09:00:00Z"
    assert "dew_point" not in result["hourly"][0]
    assert "visibility" not in result["hourly"][0]


def test_malformed_time_keeps_original_provider_indices() -> None:
    raw = _provider("malformed-time-skipped")
    result = decode_weather(raw)
    assert raw["hourly"]["time"] == [
        "2026-02-19T00:00",
        "not-a-timestamp",
        "2026-02-19T02:00",
    ]
    assert len(result["hourly"]) == 2
    first, second = result["hourly"]
    assert first["time"] == "2026-02-19T00:00:00Z"
    assert first["cloud_cover"] == 10
    assert first["humidity"] == 11
    assert first["wind_speed"] == 1.5
    assert first["wind_direction"] == 10
    assert first["temperature"] == 1.0
    assert first["dew_point"] == 0.5
    assert first["visibility"] == 1000
    assert second["time"] == "2026-02-19T02:00:00Z"
    assert second["cloud_cover"] == 30
    assert second["humidity"] == 31
    assert second["wind_speed"] == 3.5
    assert second["wind_direction"] == 30
    assert second["temperature"] == 3.0
    assert second["dew_point"] == 2.5
    assert second["visibility"] == 3000
    compacted = decode_weather(
        {
            "utc_offset_seconds": 0,
            "hourly": {
                "time": ["2026-02-19T00:00", "2026-02-19T02:00"],
                "cloudcover": raw["hourly"]["cloudcover"],
                "relativehumidity_2m": raw["hourly"]["relativehumidity_2m"],
                "windspeed_10m": raw["hourly"]["windspeed_10m"],
                "winddirection_10m": raw["hourly"]["winddirection_10m"],
                "temperature_2m": raw["hourly"]["temperature_2m"],
                "dewpoint_2m": raw["hourly"]["dewpoint_2m"],
                "visibility": raw["hourly"]["visibility"],
            },
        }
    )
    assert compacted["hourly"][1]["cloud_cover"] == 20
    assert result["hourly"][1]["cloud_cover"] != compacted["hourly"][1]["cloud_cover"]


def test_short_optional_arrays_omit_missing_indices() -> None:
    result = decode_weather(_provider("short-optional-arrays"))
    assert result["hourly"][0]["mid_cloud_cover"] == 40
    assert result["hourly"][0]["high_cloud_cover"] == 30
    assert result["hourly"][0]["wind_speed_200hpa"] == 120
    assert "mid_cloud_cover" not in result["hourly"][1]
    assert "high_cloud_cover" not in result["hourly"][1]
    assert "wind_speed_200hpa" not in result["hourly"][1]


def test_negative_values_are_not_sanitized() -> None:
    result = decode_weather(_provider("negative-values"))
    row = result["hourly"][0]
    assert row["wind_speed"] == -5.0
    assert row["temperature"] == -10.5
    assert row["dew_point"] == -12.0
    assert row["time"] == "2026-02-18T23:00:00Z"
    assert "precipitation" not in row


def test_layered_seeing_transparency_fields() -> None:
    result = decode_weather(_provider("layered-seeing-transparency"))
    row = result["hourly"][0]
    assert row["mid_cloud_cover"] == 40
    assert row["high_cloud_cover"] == 30
    assert row["wind_speed_200hpa"] == 120
    assert "low_cloud_cover" not in row


def test_iana_timezone_is_preferred_over_offset_when_valid() -> None:
    result = decode_weather(
        {
            "utc_offset_seconds": 0,
            "timezone": "America/New_York",
            "hourly": {
                "time": ["2026-07-01T00:00"],
                "cloudcover": [0],
                "relativehumidity_2m": [0],
                "windspeed_10m": [0],
                "winddirection_10m": [0],
                "temperature_2m": [0],
            },
        }
    )
    assert result["timezone"] == "America/New_York"
    assert result["utc_offset_seconds"] == 0
    assert result["hourly"][0]["time"] == "2026-07-01T04:00:00Z"


def test_invalid_timezone_string_falls_back_to_offset_and_is_preserved() -> None:
    result = decode_weather(
        {
            "utc_offset_seconds": -28800,
            "timezone": "Not/A_Zone",
            "hourly": {
                "time": ["2026-02-19T00:00"],
                "cloudcover": [1],
                "relativehumidity_2m": [2],
                "windspeed_10m": [3],
                "winddirection_10m": [4],
                "temperature_2m": [5],
            },
        }
    )
    assert result["timezone"] == "Not/A_Zone"
    assert result["hourly"][0]["time"] == "2026-02-19T08:00:00Z"


def _minimal_hourly(times: list[str], *, offset: int = 0) -> dict:
    n = len(times)
    return {
        "utc_offset_seconds": offset,
        "hourly": {
            "time": times,
            "cloudcover": list(range(n)),
            "relativehumidity_2m": [0] * n,
            "windspeed_10m": [0.0] * n,
            "winddirection_10m": [0] * n,
            "temperature_2m": [0.0] * n,
        },
    }


def test_seconds_in_timestamp_are_malformed_and_skipped() -> None:
    """OpenMeteoForecastDecoder skips yyyy-MM-dd'T'HH:mm:ss; keep that skip."""
    result = decode_weather(
        {
            "utc_offset_seconds": 0,
            "hourly": {
                "time": ["2026-02-19T00:00:00", "2026-02-19T01:00"],
                "cloudcover": [9, 8],
                "relativehumidity_2m": [1, 2],
                "windspeed_10m": [1.0, 2.0],
                "winddirection_10m": [10, 20],
                "temperature_2m": [1.0, 2.0],
            },
        }
    )
    assert len(result["hourly"]) == 1
    assert result["hourly"][0]["time"] == "2026-02-19T01:00:00Z"
    assert result["hourly"][0]["cloud_cover"] == 8


def test_unpadded_local_timestamps_match_swift_decoder() -> None:
    result = decode_weather(
        _minimal_hourly(
            [
                "2026-02-19T00:00",
                "2026-2-19T00:00",
                "2026-02-19T0:00",
                "2026-02-19T00:0",
                "2026-2-9T0:0",
                "2026-02-19T00:00:00",
                "2026-02-19T12:3",
                "2026-02-19T1:2",
            ]
        )
    )
    times = [row["time"] for row in result["hourly"]]
    covers = [row["cloud_cover"] for row in result["hourly"]]
    assert times == [
        "2026-02-19T00:00:00Z",
        "2026-02-19T00:00:00Z",
        "2026-02-19T00:00:00Z",
        "2026-02-19T00:00:00Z",
        "2026-02-09T00:00:00Z",
        "2026-02-19T12:03:00Z",
        "2026-02-19T01:02:00Z",
    ]
    assert covers == [0, 1, 2, 3, 4, 6, 7]


def test_gmt_offset_minute_rounding_matches_swift() -> None:
    expected = {
        1: "2026-02-19T00:00:00Z",
        29: "2026-02-19T00:00:00Z",
        30: "2026-02-18T23:59:00Z",
        31: "2026-02-18T23:59:00Z",
        59: "2026-02-18T23:59:00Z",
        60: "2026-02-18T23:59:00Z",
        61: "2026-02-18T23:59:00Z",
        89: "2026-02-18T23:59:00Z",
        90: "2026-02-18T23:58:00Z",
        91: "2026-02-18T23:58:00Z",
        119: "2026-02-18T23:58:00Z",
        -1: "2026-02-19T00:00:00Z",
        -29: "2026-02-19T00:00:00Z",
        -30: "2026-02-19T00:01:00Z",
        -31: "2026-02-19T00:01:00Z",
        -59: "2026-02-19T00:01:00Z",
        -60: "2026-02-19T00:01:00Z",
        -89: "2026-02-19T00:01:00Z",
        -90: "2026-02-19T00:02:00Z",
        -91: "2026-02-19T00:02:00Z",
        -119: "2026-02-19T00:02:00Z",
    }
    for offset, instant in expected.items():
        result = decode_weather(_minimal_hourly(["2026-02-19T00:00"], offset=offset))
        assert result["utc_offset_seconds"] == offset
        assert result["hourly"][0]["time"] == instant, offset


def test_offset_beyond_18_hours_falls_back_to_gmt_for_parsing() -> None:
    """Swift TimeZone(secondsFromGMT:) is nil outside ±18h; parse as UTC."""
    at_limit = decode_weather(
        {
            "utc_offset_seconds": 64800,
            "hourly": {
                "time": ["2026-02-19T00:00"],
                "cloudcover": [1],
                "relativehumidity_2m": [1],
                "windspeed_10m": [1.0],
                "winddirection_10m": [1],
                "temperature_2m": [1.0],
            },
        }
    )
    assert at_limit["utc_offset_seconds"] == 64800
    assert at_limit["hourly"][0]["time"] == "2026-02-18T06:00:00Z"

    beyond = decode_weather(
        {
            "utc_offset_seconds": 64801,
            "hourly": {
                "time": ["2026-02-19T00:00"],
                "cloudcover": [1],
                "relativehumidity_2m": [1],
                "windspeed_10m": [1.0],
                "winddirection_10m": [1],
                "temperature_2m": [1.0],
            },
        }
    )
    assert beyond["utc_offset_seconds"] == 64801
    assert beyond["hourly"][0]["time"] == "2026-02-19T00:00:00Z"

    negative_beyond = decode_weather(
        {
            "utc_offset_seconds": -64801,
            "hourly": {
                "time": ["2026-02-19T00:00"],
                "cloudcover": [1],
                "relativehumidity_2m": [1],
                "windspeed_10m": [1.0],
                "winddirection_10m": [1],
                "temperature_2m": [1.0],
            },
        }
    )
    assert negative_beyond["utc_offset_seconds"] == -64801
    assert negative_beyond["hourly"][0]["time"] == "2026-02-19T00:00:00Z"


def test_required_array_short_defaults_to_zero() -> None:
    result = decode_weather(
        {
            "utc_offset_seconds": 0,
            "hourly": {
                "time": ["2026-02-19T00:00", "2026-02-19T01:00"],
                "cloudcover": [7],
                "relativehumidity_2m": [1, 2],
                "windspeed_10m": [1.0, 2.0],
                "winddirection_10m": [10, 20],
                "temperature_2m": [1.0, 2.0],
            },
        }
    )
    assert result["hourly"][0]["cloud_cover"] == 7
    assert result["hourly"][1]["cloud_cover"] == 0


def test_root_must_be_object() -> None:
    with pytest.raises(ValidationError, match="object"):
        decode_weather([])
    with pytest.raises(ValidationError, match="hourly"):
        decode_weather({"utc_offset_seconds": 0})


def test_hourly_arrays_must_have_correct_types() -> None:
    base = _provider("missing-fields")
    bad_time = deepcopy(base)
    bad_time["hourly"]["time"] = [0]
    with pytest.raises(ValidationError, match="time"):
        decode_weather(bad_time)
    bad_cloud = deepcopy(base)
    bad_cloud["hourly"]["cloudcover"] = ["50"]
    with pytest.raises(ValidationError):
        decode_weather(bad_cloud)
    bad_bool = deepcopy(base)
    bad_bool["hourly"]["cloudcover"] = [True]
    with pytest.raises(ValidationError):
        decode_weather(bad_bool)
    bad_hourly = deepcopy(base)
    bad_hourly["hourly"] = []
    with pytest.raises(ValidationError, match="hourly"):
        decode_weather(bad_hourly)


def test_decoded_hours_are_usable_by_night_conditions() -> None:
    hours = decode_weather(_provider("happy-path"))["hourly"]
    document = {
        "capability": "night_conditions.analyze",
        "clock": "2026-02-19T12:00:00Z",
        "time_zone": "UTC",
        "injected": {
            "night_window": {
                "start": "2026-02-19T08:00:00Z",
                "end": "2026-02-19T10:00:00Z",
            },
            "forecasts": hours,
            "moon_series": [
                {"time": hour["time"], "altitude_deg": -10.0, "illumination_pct": 0}
                for hour in hours
            ],
        },
    }
    result = analyze_night_conditions(document)
    assert result["hourly_ratings"][0]["time"] == "2026-02-19T08:00:00Z"
    assert result["hourly_ratings"][0]["cloud_cover"] == 50


def test_fixture_ref_escape_and_missing() -> None:
    with pytest.raises(FixtureRefError) as escaped:
        resolve_fixture_ref("../data/calibration/observing-quality.json")
    assert escaped.value.code == "ref_escape"
    with pytest.raises(FixtureRefError) as missing:
        load_fixture_ref("providers/open-meteo/forecast/does-not-exist.json")
    assert missing.value.code == "fixture_missing"
