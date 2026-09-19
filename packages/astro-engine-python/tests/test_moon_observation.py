"""Structure, search and transport semantics for astronomy.moon_observation.

The sampling/search logic is exercised against an injected analytic sampler so the
cadence, midpoint and rise/set rules are testable without an ephemeris.
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

import pytest

from astro_engine._capability import evaluate_capability
from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.moon_observation import (
    CAPABILITY_ID,
    EARTH_MEAN_RADIUS_KM,
    MAX_SAMPLE_COUNT,
    MOON_MEAN_RADIUS_KM,
    REFRACTION_AT_HORIZON,
    evaluate_moon_observation,
    moon_times,
    observe,
)

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
START = (datetime(2026, 8, 29, 2, tzinfo=timezone.utc) - EPOCH).total_seconds()


class SineSampler:
    """`altitude(h) = offset + amplitude * sin(2*pi*(h + shift)/24)` degrees.

    A curved altitude is required: the quadratic interpolation degenerates (its
    leading coefficient vanishes) for a perfectly linear ramp, which is itself the
    IEEE case `test_constant_altitude_finds_no_events` covers.
    """

    def __init__(self, offset=0.0, amplitude=30.0, shift=0.0,
                 distance=384_400.0, fraction=0.5, phase=-90.0):
        self.offset = offset
        self.amplitude = amplitude
        self.shift = shift
        self.distance = distance
        self.fraction = fraction
        self.phase = phase
        self.phase_instants = []
        self.horizontal_instants = []

    def degrees_at(self, hours):
        return self.offset + self.amplitude * math.sin(2 * math.pi * (hours + self.shift) / 24)

    def moon_horizontal(self, latitude, longitude, time):
        self.horizontal_instants.append(time)
        hours = ((time - EPOCH).total_seconds() - START) / 3600
        degrees = self.degrees_at(hours)
        return degrees, (degrees + 360) % 360, math.radians(degrees), self.distance

    def moon_phase(self, time):
        self.phase_instants.append(time)
        return self.fraction, self.phase


def threshold_degrees(distance=384_400.0):
    return math.degrees(
        math.asin(EARTH_MEAN_RADIUS_KM / distance)
        - REFRACTION_AT_HORIZON
        - math.asin(MOON_MEAN_RADIUS_KM / distance)
    )


def instant(seconds):
    return EPOCH + timedelta(seconds=seconds)


def test_samples_use_repeated_addition_and_an_explicit_interval_end():
    result = observe(SineSampler(), 0, 0, START, START + 3600 + 600)
    times = [row[0] for row in result["samples"]]
    assert times == [START, START + 1800, START + 3600, START + 4200]


def test_interval_shorter_than_the_cadence_still_reports_both_endpoints():
    result = observe(SineSampler(), 0, 0, START, START + 600)
    assert [row[0] for row in result["samples"]] == [START, START + 600]


def test_zero_length_interval_reports_one_sample():
    result = observe(SineSampler(), 0, 0, START, START)
    assert [row[0] for row in result["samples"]] == [START]


def test_inverted_interval_reports_no_samples_but_still_searches_events():
    # Just below the threshold at the start and rising fast: the crossing lands
    # inside the one-cadence search limit, not inside the negative span.
    sampler = SineSampler(offset=0.0, amplitude=30.0, shift=-0.001)
    result = observe(sampler, 0, 0, START, START - 3600)
    assert result["samples"] == []
    assert result["rise"] is not None
    assert START <= result["rise"] < START + 1800


def test_phase_is_sampled_at_the_midpoint_and_inverted_intervals_use_the_start():
    sampler = SineSampler()
    observe(sampler, 0, 0, START, START + 7200)
    assert sampler.phase_instants == [instant(START + 3600)]
    sampler = SineSampler()
    observe(sampler, 0, 0, START, START - 7200)
    assert sampler.phase_instants == [instant(START)]


def test_illumination_truncates_and_phase_normalizes_to_the_unit_cycle():
    result = observe(SineSampler(fraction=0.999, phase=-179.0), 0, 0, START, START)
    assert result["illumination"] == 99
    assert result["phase"] == pytest.approx((-179.0 + 180) / 360)
    waning = observe(SineSampler(fraction=0.5, phase=90.0), 0, 0, START, START)
    assert waning["phase"] == 0.75


def test_rise_threshold_sits_above_the_geometric_horizon():
    """Rise/set use parallax minus refraction minus semidiameter, not altitude 0.

    A Moon parked between the geometric horizon and that threshold is "down" for
    rise/set even though its altitude is positive, which is exactly why sample
    visibility (`altitude > 0`) and `always_down` are different questions.
    """
    assert threshold_degrees() == pytest.approx(0.1161, abs=5e-4)
    below = moon_times(SineSampler(offset=0.05, amplitude=0.0), 0, 0, START, 6 * 3600)
    assert below.always_down and not below.always_up
    above = moon_times(SineSampler(offset=0.2, amplitude=0.0), 0, 0, START, 6 * 3600)
    assert above.always_up and not above.always_down


def test_rise_is_found_when_the_altitude_climbs_through_the_threshold():
    sampler = SineSampler(offset=0.0, amplitude=30.0, shift=-1.0)
    times = moon_times(sampler, 0, 0, START, 6 * 3600)
    assert times.rise is not None and times.set is None
    assert not times.always_down and not times.always_up
    # The hourly quadratic resolves the crossing to well under a sample step.
    assert abs((times.rise - START) / 3600 - 1.015) < 0.05


def test_always_down_when_no_crossing_is_found():
    times = moon_times(SineSampler(offset=-40.0, amplitude=10.0), 0, 0, START, 3600)
    assert times == (None, None, False, True)


def test_always_up_means_up_at_the_start_with_no_set_in_the_window():
    """The flags are seeded from the sign at hour 0, not from "no events"."""
    sampler = SineSampler(offset=0.0, amplitude=30.0, shift=6.0)
    times = moon_times(sampler, 0, 0, START, 3600)
    assert times.always_up and times.set is None


def test_constant_altitude_finds_no_events():
    """A degenerate quadratic divides to IEEE NaN rather than raising."""
    times = moon_times(SineSampler(offset=5.0, amplitude=0.0), 0, 0, START, 6 * 3600)
    assert times == (None, None, True, False)


def test_set_clears_always_up():
    sampler = SineSampler(offset=0.0, amplitude=30.0, shift=6.0)
    times = moon_times(sampler, 0, 0, START, 12 * 3600)
    assert times.set is not None and not times.always_up and not times.always_down


def test_events_outside_the_limit_are_not_reported():
    # The moon is up at the start and sets about six hours later.
    sampler = SineSampler(offset=0.0, amplitude=30.0, shift=6.0)
    assert moon_times(sampler, 0, 0, START, 3600).set is None
    assert moon_times(sampler, 0, 0, START, 8 * 3600).set is not None


def test_search_work_is_bounded_by_the_limit():
    sampler = SineSampler(offset=-40.0, amplitude=10.0)
    moon_times(sampler, 0, 0, START, 26 * 3600)
    assert len(sampler.horizontal_instants) <= 26 + 4


# --- transport ------------------------------------------------------------


def base(**changes):
    document = {"latitude": 37.7749, "longitude": -122.4194,
                "night_start": "2026-08-29T02:00:00Z", "night_end": "2026-08-29T06:00:00Z"}
    document.update(changes)
    return {key: value for key, value in document.items() if value is not ...}


@pytest.mark.parametrize("injected", [
    base(latitude=True),
    base(latitude=91),
    base(longitude=-181),
    base(latitude="37"),
    base(night_start=...),
    base(night_start="2026-08-29T02:00:00+00:00"),
    base(night_start="1999-12-31T23:59:59Z"),
    base(night_end="2050-01-01T00:00:00Z"),
    base(night_end="2026-08-29T02:00:00"),
    base(sample_interval_seconds=0),
    base(sample_interval_seconds=-1800),
    base(sample_interval_seconds=True),
    base(sample_interval_seconds=93_601),
    base(sample_interval_seconds=1e308),
    base(sample_interval_seconds=1800.5),
    base(sample_interval_seconds=0.5, night_end="2026-08-29T02:00:01Z"),
    base(sample_interval_seconds=10**400),
    base(minimum_altitude=0),
    base(night_end="2026-08-30T05:00:00Z"),
])
def test_invalid_transport_inputs_fail_closed(injected):
    with pytest.raises(ValidationError) as excinfo:
        evaluate_moon_observation(injected)
    assert str(excinfo.value) == f"invalid {CAPABILITY_ID} input"
    assert excinfo.value.code == "validation"


def test_span_of_exactly_26_hours_is_accepted():
    injected = base(night_start="2026-08-29T02:00:00Z", night_end="2026-08-30T04:00:00Z",
                    sample_interval_seconds=3600)
    result = evaluate_moon_observation(injected)
    assert len(result["samples"]) == 27


@pytest.mark.parametrize("interval", [1, 1e-12, 65])
def test_sample_cap_rejects_before_iterating(interval):
    with pytest.raises(SampleCapError) as excinfo:
        evaluate_moon_observation(base(sample_interval_seconds=interval,
                                       night_end="2026-08-30T04:00:00Z"))
    assert str(excinfo.value) == (
        f"{CAPABILITY_ID} exceeds the 1.0 sample cap ({MAX_SAMPLE_COUNT} samples)"
    )


def test_envelope_rejects_unknown_top_level_keys():
    document = {"capability": CAPABILITY_ID, "injected": base(), "time_zone": "UTC"}
    with pytest.raises(ValidationError):
        evaluate_capability(CAPABILITY_ID, document)


def test_result_shape_and_timestamp_flooring():
    result = evaluate_capability(CAPABILITY_ID, {"capability": CAPABILITY_ID, "injected": base()})
    assert set(result) == {"night_start", "night_end", "phase", "illumination", "rise", "set",
                           "always_up", "always_down", "samples"}
    assert result["night_start"] == "2026-08-29T02:00:00Z"
    for field in ("rise", "set"):
        assert result[field] is None or result[field].endswith("Z")
    assert all(set(row) == {"time", "altitude", "azimuth"} for row in result["samples"])


def test_cap_includes_the_explicit_end_sample(monkeypatch):
    from astro_engine.suncalc_moon import SunCalcMoonAstronomy
    def unexpected(*args, **kwargs):
        pytest.fail("cap must reject before constructing an ephemeris")
    monkeypatch.setattr(SunCalcMoonAstronomy, "__init__", unexpected)
    # 1440 regular samples plus the non-divisible endpoint used to pass.
    with pytest.raises(SampleCapError):
        evaluate_moon_observation(base(sample_interval_seconds=60,
                                       night_end="2026-08-30T01:59:30Z"))


def test_exactly_1440_samples_remain_composable():
    from astro_engine.moon_recommendation import recommend_moon
    result = evaluate_moon_observation(base(sample_interval_seconds=60,
                                           night_end="2026-08-30T01:59:00Z"))
    assert len(result["samples"]) == MAX_SAMPLE_COUNT
    moon = {k: v for k, v in result.items() if k not in ("night_start", "night_end")}
    recommend_moon(dict(night_start=result["night_start"], night_end=result["night_end"],
                        moon=moon, cloud_cover_score=0, hourly_ratings=[]))


def test_production_observation_does_not_construct_skyfield(monkeypatch):
    from astro_engine.astronomy import SkyfieldAstronomy
    def unexpected(*args, **kwargs):
        pytest.fail("production observation must use the SunCalc model")
    monkeypatch.setattr(SkyfieldAstronomy, "__init__", unexpected)
    assert evaluate_moon_observation(base())["samples"]
