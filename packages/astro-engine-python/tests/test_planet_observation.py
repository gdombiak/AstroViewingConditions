"""Unit semantics for astronomy.planet_observation not covered by the fixtures."""
from __future__ import annotations

import math

import pytest

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.planet_observation import (
    CAPABILITY_ID,
    DEFAULT_SAMPLE_INTERVAL,
    LEAD_SECONDS,
    MAX_SAMPLE_COUNT,
    SUPPORTED_TARGET_IDS,
    TRAIL_SECONDS,
    _reference_seconds,
    evaluate_planet_observation,
    observe,
    position,
)


def base(**changes):
    document = dict(target_id="venus", latitude=37.7749, longitude=-122.4194,
                    night_start="2026-03-01T04:00:00Z", night_end="2026-03-01T12:00:00Z",
                    sample_interval_seconds=900)
    document.update(changes)
    return document


def test_production_constants():
    assert DEFAULT_SAMPLE_INTERVAL == 900.0
    assert LEAD_SECONDS == 7200.0
    assert TRAIL_SECONDS == 3600.0
    assert SUPPORTED_TARGET_IDS == ("venus", "mars", "jupiter", "saturn")


def test_schlyter_day_number_reproduces_the_production_regression_sample():
    sample = position("jupiter", 37.323, -122.032, _reference_seconds("2026-06-30T01:26:00Z"))
    assert sample.altitude == pytest.approx(39.53232839707897, abs=1e-12)
    assert sample.azimuth == pytest.approx(266.78242134237917, abs=1e-12)


def test_sampling_span_is_inclusive_at_both_ends():
    start = _reference_seconds("2026-03-01T04:00:00Z")
    end = _reference_seconds("2026-03-01T13:00:00Z")
    samples = observe("mars", 40.0, -74.0, start, end, 2 * 3600.0)
    assert samples[0].time == start - LEAD_SECONDS
    assert samples[-1].time == end + TRAIL_SECONDS
    assert len(samples) == 7


def test_non_divisible_span_stops_before_the_end_without_an_extra_sample():
    start = _reference_seconds("2026-03-01T04:00:00Z")
    samples = observe("mars", 40.0, -74.0, start, _reference_seconds("2026-03-01T12:00:00Z"),
                      2 * 3600.0)
    assert len(samples) == 6
    assert samples[-1].time == start - LEAD_SECONDS + 5 * 2 * 3600.0


def test_interval_inverted_past_lead_and_trail_has_no_observation():
    start = _reference_seconds("2026-03-01T04:00:00Z")
    assert observe("venus", 40.0, -74.0, start, start - 3 * 3600.0) is None
    assert observe("venus", 40.0, -74.0, start, start - 3 * 3600.0 + 1) is not None


def test_transport_reports_a_null_observation_for_an_inverted_night():
    result = evaluate_planet_observation(base(night_end="2026-03-01T01:00:00Z"))
    assert result["observation"] is None
    assert result["night_start"] == "2026-03-01T04:00:00Z"


def test_transport_echoes_the_sampling_span():
    result = evaluate_planet_observation(base())
    assert result["observation"]["sample_start"] == "2026-03-01T02:00:00Z"
    assert result["observation"]["sample_end"] == "2026-03-01T13:00:00Z"
    assert len(result["observation"]["samples"]) == 45


def test_default_cadence_is_the_production_fifteen_minutes():
    document = base()
    del document["sample_interval_seconds"]
    assert len(evaluate_planet_observation(document)["observation"]["samples"]) == 45


@pytest.mark.parametrize("target_id", ["earth", "mercury", "Venus", "moon", "", None, 3])
def test_unsupported_target_ids_including_earth_are_rejected(target_id):
    with pytest.raises(ValidationError):
        evaluate_planet_observation(base(target_id=target_id))


@pytest.mark.parametrize("changes", [
    dict(night_end="2026-03-02T07:00:00Z"),
    dict(latitude=True),
    dict(latitude=90.1),
    dict(longitude=-180.1),
    dict(sample_interval_seconds=True),
    dict(sample_interval_seconds=0),
    dict(sample_interval_seconds=-900),
    dict(sample_interval_seconds=93601),
    dict(sample_interval_seconds=900.5),
    dict(night_start="1999-12-31T23:59:59Z"),
    dict(night_end="2050-01-01T00:00:00Z"),
    dict(night_start="2026-02-30T00:00:00Z"),
    dict(night_start="2026-03-01T04:00:00+00:00"),
    dict(extra=1),
])
def test_transport_fails_closed(changes):
    with pytest.raises(ValidationError):
        evaluate_planet_observation(base(**changes))


@pytest.mark.parametrize("key", ["target_id", "latitude", "longitude", "night_start", "night_end"])
def test_missing_required_fields_fail_closed(key):
    document = base()
    del document[key]
    with pytest.raises(ValidationError):
        evaluate_planet_observation(document)


@pytest.mark.parametrize("cadence", [1, 1e-12])
def test_sample_cap_is_enforced_before_sampling(cadence):
    with pytest.raises(SampleCapError) as excinfo:
        evaluate_planet_observation(base(sample_interval_seconds=cadence))
    assert str(excinfo.value) == (
        f"{CAPABILITY_ID} exceeds the 1.0 sample cap ({MAX_SAMPLE_COUNT} samples)"
    )


def test_samples_are_horizontal_coordinates_with_solar_elongation():
    for target_id in SUPPORTED_TARGET_IDS:
        result = evaluate_planet_observation(base(target_id=target_id))
        for row in result["observation"]["samples"]:
            assert -90 <= row["altitude"] <= 90
            assert 0 <= row["azimuth"] < 360
            assert 0 <= row["solar_elongation"] <= 180
            assert math.isfinite(row["altitude"])
