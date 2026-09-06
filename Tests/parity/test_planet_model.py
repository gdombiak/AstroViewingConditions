"""Adversarial Swift/Python port checks for the production planet astronomy model.

The tolerances asserted here are deliberately far tighter than the public
`astronomy_planet_observation` ceilings: a regression to a different astronomy
model must fail even when ordinary cases would still fit the published policy.
"""
import json
from datetime import datetime, timedelta, timezone

import pytest

from compare import compare_value, load_policy_fields
from test_planets import SUPPORTED, _python, _swift

DAYS = ("2000-01-02", "2012-06-06", "2026-03-01", "2026-07-18", "2035-11-11", "2049-12-29")
LOCATIONS = (
    (90.0, 0.0), (-90.0, 0.0), (89.9, 179.9), (-89.9, -179.9),
    (66.5, 20.0), (-66.5, 20.0), (0.0, 0.0), (0.0, -179.999),
    (37.323, -122.032), (33.8078, -118.3183), (-33.87, 151.21), (51.5, 0.0), (-23.44, -46.63),
)


def _cases():
    # All four production planets across the supported date range and a spread of
    # ordinary, equatorial, polar and antimeridian sites.
    for target_id in SUPPORTED:
        for day in DAYS:
            for latitude, longitude in LOCATIONS:
                start = datetime.fromisoformat(day).replace(tzinfo=timezone.utc) + timedelta(hours=3)
                yield dict(target_id=target_id, latitude=latitude, longitude=longitude,
                           night_start=start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                           night_end=(start + timedelta(hours=8)).strftime("%Y-%m-%dT%H:%M:%SZ"))
    # Interval boundaries: zero-length, inverted inside and past the guard, the
    # maximum span, non-divisible spans and a non-default odd cadence.
    base = datetime(2026, 3, 1, 3, tzinfo=timezone.utc)
    for seconds, cadence in ((0, 900), (-3600, 900), (-10799, 900), (-10800, 900),
                             (26 * 3600, 900), (3601, 137), (93599 - 10800, 900),
                             (8 * 3600 + 1, 900), (8 * 3600, 3600)):
        yield dict(target_id="venus", latitude=40.7, longitude=-74.0,
                   night_start=base.strftime("%Y-%m-%dT%H:%M:%SZ"),
                   night_end=(base + timedelta(seconds=seconds)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                   sample_interval_seconds=cadence)
    # Azimuth wrap across a transit at high latitude, one sample per minute.
    for minute in range(0, 240, 7):
        start = datetime(2026, 12, 21, tzinfo=timezone.utc) + timedelta(minutes=minute)
        yield dict(target_id="mars", latitude=78.2, longitude=15.6,
                   night_start=start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                   night_end=(start + timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                   sample_interval_seconds=60)
    # Altitude near the 8 degree visibility threshold and solar elongations near
    # the Venus scoring boundaries, sampled finely.
    for minute in range(0, 180, 5):
        start = datetime(2026, 7, 18, 4, tzinfo=timezone.utc) + timedelta(minutes=minute)
        yield dict(target_id="venus", latitude=33.8078, longitude=-118.3183,
                   night_start=start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                   night_end=(start + timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                   sample_interval_seconds=300)
    # Range edges, including the sampling lead that reaches before the input window.
    yield dict(target_id="saturn", latitude=40.7, longitude=-74.0,
               night_start="2000-01-01T00:00:00Z", night_end="2000-01-01T08:00:00Z")
    yield dict(target_id="saturn", latitude=40.7, longitude=-74.0,
               night_start="2049-12-31T14:00:00Z", night_end="2049-12-31T23:59:59Z")


def test_production_model_port_adversarial_sweep(tmp_path):
    worst = dict(altitude=0.0, azimuth=0.0, solar_elongation=0.0)
    fields = load_policy_fields("astronomy_planet_observation")
    intervals = rows = null_observations = 0
    threshold_crossings = 0

    for injected in _cases():
        swift = _swift("astronomy.planet_observation", injected, tmp_path)
        python = _python("astronomy.planet_observation", injected)
        compare_value(swift, python, fields, path="")
        compare_value(python, swift, fields, path="")
        intervals += 1
        assert (swift["observation"] is None) == (python["observation"] is None)
        if swift["observation"] is None:
            null_observations += 1
            continue
        pairs = list(zip(swift["observation"]["samples"], python["observation"]["samples"]))
        assert len(pairs) == len(swift["observation"]["samples"]) == len(python["observation"]["samples"])
        previous = None
        for a, b in pairs:
            assert a["time"] == b["time"]
            worst["altitude"] = max(worst["altitude"], abs(a["altitude"] - b["altitude"]))
            azimuth = abs(a["azimuth"] - b["azimuth"]) % 360
            worst["azimuth"] = max(worst["azimuth"], min(azimuth, 360 - azimuth))
            worst["solar_elongation"] = max(
                worst["solar_elongation"], abs(a["solar_elongation"] - b["solar_elongation"]))
            if previous is not None and (previous < 8) != (a["altitude"] < 8):
                threshold_crossings += 1
            previous = a["altitude"]
            rows += 1

    # Stronger than the public maximum tolerances: a regression to a different
    # ephemeris must fail even if ordinary cases happen to fit the old policy.
    assert worst["altitude"] < 1e-9
    assert worst["azimuth"] < 1e-9
    assert worst["solar_elongation"] < 1e-9
    assert null_observations > 0, "the guarded inverted interval must be exercised"
    assert threshold_crossings > 20, "the sweep must cross the visible-altitude threshold"
    print(f"\n[planet model] {intervals} intervals, {rows} samples, "
          f"{threshold_crossings} threshold crossings; worst deltas "
          f"{json.dumps(worst, sort_keys=True)}")


@pytest.mark.parametrize("target_id", SUPPORTED)
def test_each_supported_planet_is_covered_by_the_sweep(target_id):
    assert any(case["target_id"] == target_id for case in _cases())


def test_public_ceilings_are_far_above_the_measured_agreement():
    """The published tolerances exist for cross-platform libm ULPs, not for a
    different astronomy model."""
    fields = load_policy_fields("astronomy_planet_observation")
    assert fields["observation.samples[].altitude"] == "abs_1e4"
    assert fields["observation.samples[].solar_elongation"] == "abs_1e4"
    assert fields["observation.samples[].azimuth"] == "cyclic_azimuth_abs_0_01"


@pytest.mark.parametrize("spec,value", [("cyclic_azimuth_abs_0_01", 540.0)])
def test_cyclic_comparison_rejects_out_of_range_equivalents(spec, value):
    with pytest.raises(AssertionError):
        compare_value(value, value, {"angle": spec}, path="angle")
