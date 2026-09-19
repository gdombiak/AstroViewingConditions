"""Typed-layer semantics for deep-sky observation facts.

Mirrors packages/astro-engine-swift/Tests/.../DeepSkyObservationTests.swift. Ties
and the degenerate-slope guard live here rather than in fixtures: an exact
binary64 tie between two trig samples cannot be constructed reliably.
"""

from __future__ import annotations

import math

import pytest

from astro_engine.deep_sky_observation import (
    DEFAULT_SAMPLE_INTERVAL,
    MAX_SAMPLE_COUNT,
    exceeds_sample_cap,
    Sample,
    compass_direction,
    horizontal_position,
    observe,
    samples,
    threshold_crossing,
    windows,
)
from astro_engine.errors import SampleCapError, ValidationError
from astro_engine._capability import evaluate_capability


def row(offset_minutes: float, altitude: float, azimuth: float = 90.0) -> Sample:
    return Sample(offset_minutes * 60.0, altitude, azimuth)


# --- sampling -------------------------------------------------------------


def test_inclusive_endpoint_sampling_stops_early_on_indivisible_intervals():
    rows = samples(16.6949, 36.4613, 40.0, -74.0, 0.0, 50 * 60.0)
    assert [entry.time for entry in rows] == [0.0, 900.0, 1800.0, 2700.0]


def test_endpoint_is_sampled_when_it_falls_on_a_step():
    rows = samples(16.6949, 36.4613, 40.0, -74.0, 0.0, 2 * DEFAULT_SAMPLE_INTERVAL)
    assert [entry.time for entry in rows] == [0.0, 900.0, 1800.0]


def test_inverted_interval_has_no_samples_and_zero_length_has_one():
    assert samples(0, 0, 0, 0, 0.0, -1.0) == []
    assert len(samples(0, 0, 0, 0, 0.0, 0.0)) == 1


# --- runs -----------------------------------------------------------------


def test_threshold_equality_is_visible():
    rows = [row(0, 10), row(15, 15), row(30, 10)]
    result = windows(rows, rows[0].time, rows[2].time, 15)
    assert len(result) == 1
    assert result[0].max_altitude == 15
    assert result[0].best_time == rows[1].time


def test_highest_altitude_tie_keeps_the_earliest_sample():
    rows = [row(0, 20, 90), row(15, 30, 100), row(30, 30, 200), row(45, 20, 260)]
    result = windows(rows, rows[0].time, rows[3].time, 15)
    assert len(result) == 1
    assert result[0].best_time == rows[1].time
    assert result[0].azimuth == 100
    assert result[0].direction == "E"


def test_multiple_runs_each_produce_a_window():
    rows = [row(0, 20), row(15, 5), row(30, 20), row(45, 5)]
    result = windows(rows, rows[0].time, rows[3].time, 15)
    assert len(result) == 2
    assert result[0].start == rows[0].time
    assert result[1].end == threshold_crossing(rows[2], rows[3], 15)


def test_never_visible_and_all_visible_boundaries():
    rows = [row(0, 5), row(15, 6)]
    assert windows(rows, rows[0].time, rows[1].time, 15) == []

    visible = [row(0, 40), row(15, 45)]
    interval_end = visible[1].time + 600
    result = windows(visible, visible[0].time, interval_end, 15)
    assert len(result) == 1
    assert result[0].start == visible[0].time
    # Preserved quirk: a run reaching the last sample reports the interval end.
    assert result[0].end == interval_end


def test_single_sample_run_is_a_window():
    rows = [row(0, 5), row(15, 40), row(30, 5)]
    result = windows(rows, rows[0].time, rows[2].time, 15)
    assert len(result) == 1
    assert result[0].best_time == rows[1].time
    assert result[0].start < result[0].end


# --- crossing -------------------------------------------------------------


def test_degenerate_slope_guard_returns_the_first_instant():
    first, second = row(0, 20), row(15, 20.00005)
    assert threshold_crossing(first, second, 15) == first.time


def test_crossing_fraction_is_clamped_into_the_pair():
    first, second = row(0, 20), row(15, 30)
    assert threshold_crossing(first, second, 15) == first.time
    low_first, low_second = row(0, 1), row(15, 2)
    assert threshold_crossing(low_first, low_second, 15) == low_second.time


def test_interior_crossing_interpolates_linearly():
    first, second = row(0, 10), row(20, 30)
    assert threshold_crossing(first, second, 15) == first.time + 300


# --- position -------------------------------------------------------------


@pytest.mark.parametrize(
    "azimuth,expected",
    [(348.75, "N"), (337.4, "NW"), (0, "N"), (22.5, "NE"), (359.999, "N")],
)
def test_compass_direction_wraps_at_the_north_boundary(azimuth, expected):
    assert compass_direction(azimuth) == expected


def test_right_ascension_wraps_by_24_hours():
    base = horizontal_position(1.5, 20, 40, -74, 0.0)
    wrapped = horizontal_position(25.5, 20, 40, -74, 0.0)
    assert base.altitude == pytest.approx(wrapped.altitude, abs=1e-9)
    assert base.azimuth == pytest.approx(wrapped.azimuth, abs=1e-9)
    assert 0 <= base.azimuth < 360


def test_longitude_is_east_positive():
    east = horizontal_position(0, 0, 0, 15, 0.0)
    shifted = horizontal_position(-1, 0, 0, 0, 0.0)
    assert east.altitude == pytest.approx(shifted.altitude, abs=1e-9)


def test_altitude_is_geometric_with_no_refraction():
    position = horizontal_position(6, 0, 90, 0, 0.0)
    assert position.altitude == pytest.approx(0.0, abs=1e-9)


def test_zenith_rounding_is_clamped_instead_of_throwing():
    # Observer latitude equals declination at a transit instant where the
    # unclamped spherical identity is 1 + 1 ULP. Typed API; not a whole-second
    # transport timestamp.
    position = horizontal_position(2.0, 34.0, 34.0, -74.0, 1_772_568_572.8249793 - 978_307_200.0)
    assert math.isfinite(position.altitude)
    assert math.isfinite(position.azimuth)
    assert position.altitude == pytest.approx(90.0, abs=1e-9)


def test_observe_composes_sampling_and_runs():
    assert observe(0.7123, 41.2692, 34.0, -118.0, 0.0, 8 * 3600.0) == windows(
        samples(0.7123, 41.2692, 34.0, -118.0, 0.0, 8 * 3600.0), 0.0, 8 * 3600.0
    )


# --- transport ------------------------------------------------------------


@pytest.mark.parametrize(
    "capability,injected",
    [
        ("astronomy.horizontal_position", {"right_ascension": 1, "declination": 2, "latitude": 3}),
        ("targets.deep_sky_windows", {"target_id": "m31", "latitude": 34.0, "longitude": -118.0,
                                      "night_start": "2026-09-06T04:00:00Z",
                                      "night_end": "2026-09-06T12:00:00Z",
                                      "sample_interval_seconds": 0}),
        ("targets.deep_sky_windows", {"target_id": "not-a-target", "latitude": 34.0, "longitude": -118.0,
                                      "night_start": "2026-09-06T04:00:00Z",
                                      "night_end": "2026-09-06T12:00:00Z"}),
    ],
)
def test_invalid_transport_inputs_raise_validation(capability, injected):
    with pytest.raises(ValidationError):
        evaluate_capability(capability, {"capability": capability, "injected": injected})


def test_transport_floors_interpolated_crossings_to_whole_seconds():
    result = evaluate_capability("targets.deep_sky_windows", {
        "capability": "targets.deep_sky_windows",
        "injected": {
            "target_id": "m42", "latitude": 34.0, "longitude": -118.0,
            "night_start": "2026-01-15T02:00:00Z", "night_end": "2026-01-15T12:00:00Z",
        },
    })
    window = result["windows"][0]
    assert window["end"] == "2026-01-15T10:19:04Z"
    typed = observe(
        5.5881, -5.3911, 34.0, -118.0,
        # 2026-01-15T02:00:00Z and +10h on the 2001 reference epoch.
        1768442400.0 - 978307200.0, 1768478400.0 - 978307200.0,
    )
    # The typed layer keeps sub-second precision; only transport floors it.
    assert typed[0].end % 1 != 0


# --- supported instant range ----------------------------------------------


def _position(time: str) -> dict:
    return evaluate_capability("astronomy.horizontal_position", {
        "capability": "astronomy.horizontal_position",
        "injected": {"right_ascension": 16.6949, "declination": 36.4613,
                     "latitude": 40.7, "longitude": -74.0, "time": time},
    })


def _windows(start: str, end: str) -> dict:
    return evaluate_capability("targets.deep_sky_windows", {
        "capability": "targets.deep_sky_windows",
        "injected": {"right_ascension": 16.6949, "declination": 36.4613,
                     "latitude": 40.7, "longitude": -74.0,
                     "night_start": start, "night_end": end},
    })


@pytest.mark.parametrize("time", ["2000-01-01T00:00:00Z", "2499-12-31T23:59:59Z"])
def test_transport_accepts_the_inclusive_range_bounds(time):
    assert set(_position(time)) == {"altitude", "azimuth"}


@pytest.mark.parametrize("time", ["1999-12-31T23:59:59Z", "2500-01-01T00:00:00Z"])
def test_transport_rejects_instants_just_outside_the_range(time):
    with pytest.raises(ValidationError):
        _position(time)


@pytest.mark.parametrize(
    "start,end",
    [("2000-01-01T00:00:00Z", "2000-01-01T08:00:00Z"),
     ("2499-12-31T16:00:00Z", "2499-12-31T23:59:59Z")],
)
def test_window_transport_accepts_intervals_on_the_bounds(start, end):
    assert "windows" in _windows(start, end)


@pytest.mark.parametrize(
    "start,end",
    [("1999-12-31T23:59:59Z", "2000-01-01T08:00:00Z"),
     ("2499-12-31T16:00:00Z", "2500-01-01T00:00:00Z")],
)
def test_window_transport_enforces_the_range_on_each_field(start, end):
    with pytest.raises(ValidationError):
        _windows(start, end)


def test_typed_api_is_unaffected_by_the_transport_range():
    # Only transport parsing/formatting is bounded; the numeric layer is not.
    ancient = -62_135_769_600.0 - 978_307_200.0
    assert len(samples(16.6949, 36.4613, 40.7, -74.0, ancient, ancient + 3600)) == 5


# --- sampling work cap ----------------------------------------------------


def test_sample_cap_preflight_boundaries():
    # floor(span / 900) + 1 == MAX_SAMPLE_COUNT exactly.
    at_limit = (MAX_SAMPLE_COUNT - 1) * 900
    assert not exceeds_sample_cap(0.0, float(at_limit), 900.0)
    assert exceeds_sample_cap(0.0, float(at_limit + 900), 900.0)


def test_non_advancing_step_exceeds_the_cap_even_on_a_zero_length_interval():
    start = 809_692_800.0
    # The quotient is 0 here, so only the advance check can reject it.
    assert exceeds_sample_cap(start, start, 1e-9)
    assert exceeds_sample_cap(start, start + 8 * 3600, 1e-9)


def test_inverted_interval_is_not_a_cap():
    start = 809_692_800.0
    assert not exceeds_sample_cap(start, start - 8 * 3600, 1e-9)


def test_sample_cap_surfaces_its_own_error_code():
    with pytest.raises(SampleCapError) as excinfo:
        evaluate_capability("targets.deep_sky_windows", {
            "capability": "targets.deep_sky_windows",
            "injected": {"right_ascension": 16.6949, "declination": 36.4613,
                         "latitude": 40.7, "longitude": -74.0,
                         "night_start": "2026-09-06T01:00:00Z",
                         "night_end": "2026-09-06T09:00:00Z",
                         "sample_interval_seconds": 1e-9},
        })
    assert excinfo.value.code == "sample_cap"
    assert str(excinfo.value) == (
        "targets.deep_sky_windows exceeds the 1.0 sample cap (10080 samples)"
    )


@pytest.mark.parametrize("interval", [600.0, 900.0, 3600.0])
def test_production_cadences_are_well_inside_the_cap(interval):
    start = 809_692_800.0
    assert not exceeds_sample_cap(start, start + 14 * 3600, interval)


def test_typed_sampling_api_keeps_no_cap():
    # Transport bounds the work; the typed layer matches generate_grid and does not.
    start = 809_692_800.0
    assert len(samples(16.6949, 36.4613, 40.7, -74.0, start, start + 3600, 0.5)) == 7201


def _loop_iterations(start: float, end: float, interval: float, limit: int = 60_000) -> int:
    """Replays the normative repeated-addition loop and counts iterations only."""
    count, time = 0, start
    while time <= end:
        count += 1
        time = time + interval
        if count > limit:
            return count
    return count


def test_accumulation_drift_cannot_slip_past_the_cap():
    # span/interval is only ~10079.1, so a mathematical count formula would accept,
    # but repeated addition realizes a slightly smaller step and emits 10083.
    start = 1_788_000_000.0 - 978_307_200.0
    end, interval = start + 1.0, 9.921520770703732e-05
    assert (end - start) / interval < MAX_SAMPLE_COUNT
    assert _loop_iterations(start, end, interval) == 10083
    assert exceeds_sample_cap(start, end, interval)


def test_no_accepted_request_exceeds_the_cap_across_adversarial_intervals():
    import random

    rng = random.Random(7)
    epochs = [946_684_800.0 - 978_307_200.0, 0.0, 809_692_800.0,
              16_725_225_599.0 - 978_307_200.0 - 100_000.0]
    accepted = 0
    worst = 0
    for epoch in epochs:
        ulp = math.ulp(abs(epoch)) if epoch else math.ulp(1.0)
        for _ in range(1500):
            span = rng.choice([0.0, 1.0, 60.0, 3600.0, 8 * 3600.0, rng.uniform(0, 1e5)])
            interval = (span / rng.uniform(9_000, 11_000) * rng.uniform(0.98, 1.02)
                        if span > 0 else rng.uniform(1e-9, 1e-3))
            if rng.random() < 0.3:
                interval = ulp * rng.uniform(0.1, 4.0)
            if not interval > 0 or not math.isfinite(interval):
                continue
            end = epoch + span
            if exceeds_sample_cap(epoch, end, interval):
                continue
            accepted += 1
            iterations = _loop_iterations(epoch, end, interval)
            worst = max(worst, iterations)
            assert iterations <= MAX_SAMPLE_COUNT, (epoch, span, repr(interval), iterations)
    assert accepted > 0
    assert worst <= MAX_SAMPLE_COUNT
