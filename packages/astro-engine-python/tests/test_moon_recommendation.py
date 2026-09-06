"""Unit semantics for targets.moon_recommendation not covered by the fixtures."""
from __future__ import annotations

import pytest

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.moon_recommendation import (
    CAPABILITY_ID,
    MAX_ROW_COUNT,
    Observation,
    Rating,
    Sample,
    Window,
    _parse_observation,
    calibration,
    compass_direction,
    evaluate,
    recommend_moon,
    visible_fraction,
    weather_quality,
)

CAL = calibration()


def sample(minutes, altitude, azimuth=90.0):
    return Sample(float(minutes * 60), altitude, azimuth)


def observation(**changes):
    base = dict(phase=0.5, illumination=60, rise=None, set=None,
                always_up=False, always_down=False,
                samples=(sample(0, 10.0), sample(30, 20.0), sample(60, 5.0)))
    base.update(changes)
    return Observation(**base)


@pytest.mark.parametrize("azimuth,expected", [
    (0.0, "N"), (11.24, "N"), (11.26, "NNE"), (22.5, "NNE"), (45.0, "NE"),
    (90.0, "E"), (135.0, "SE"), (180.0, "S"), (225.0, "SW"), (270.0, "W"),
    (315.0, "NW"), (348.75, "N"), (348.74, "NNW"), (359.999, "N"),
    (360.0, "N"), (720.5, "N"), (-90.0, "W"), (-0.1, "N"),
])
def test_compass_direction_is_sixteen_point_and_wraps(azimuth, expected):
    assert compass_direction(azimuth) == expected


def test_visible_fraction_of_an_empty_useful_window_is_zero():
    assert visible_fraction([], CAL) == 0.0


def test_weather_quality_sums_overlapping_ratings_in_caller_order():
    window = Window(start=0.0, end=3600.0, best_time=0.0, max_altitude=1.0,
                    direction="N", azimuth=0.0)
    ordered = weather_quality(window, 0.0, [Rating(0.0, 0.1), Rating(1800.0, 1.9)], CAL)
    reversed_rows = weather_quality(window, 0.0, [Rating(1800.0, 1.9), Rating(0.0, 0.1)], CAL)
    assert ordered == 1 - (0.1 + 1.9) / 2 / 2
    # Ordered binary64 addition: the contract preserves caller order rather than
    # promising that a reordering gives the identical bit pattern.
    assert reversed_rows == 1 - (1.9 + 0.1) / 2 / 2


def test_weather_quality_boundary_of_the_overlap_test_is_half_open():
    window = Window(start=3600.0, end=7200.0, best_time=3600.0, max_altitude=1.0,
                    direction="N", azimuth=0.0)
    # A rating ending exactly at the window start does not overlap.
    assert weather_quality(window, 100.0, [Rating(0.0, 0.0)], CAL) == 0.0
    # A rating starting exactly at the window end does not overlap either.
    assert weather_quality(window, 100.0, [Rating(7200.0, 0.0)], CAL) == 0.0
    assert weather_quality(window, 100.0, [Rating(1.0, 0.0)], CAL) == 1.0


def test_no_visible_sample_yields_no_recommendation():
    dark = observation(samples=(sample(0, -1.0), sample(30, 0.0)))
    assert evaluate(dark, 0.0, 3600.0, None, 0.0, [], CAL) is None


def test_best_window_is_used_as_given_and_is_not_clipped_to_the_night():
    result = evaluate(observation(), 0.0, 60.0, (0.0, 3600.0), 0.0, [], CAL)
    assert result is not None
    assert result.window.end == 30 * 60 + CAL["visibility"]["window_extension_seconds"]


def test_phase_and_illumination_are_clamped_on_parse():
    parsed = _parse_observation({
        "phase": 1.5, "illumination": 140, "rise": None, "set": None,
        "always_up": False, "always_down": False, "samples": [],
    })
    assert parsed.phase == 1.0 and parsed.illumination == 100
    parsed = _parse_observation({
        "phase": -0.5, "illumination": -20, "rise": None, "set": None,
        "always_up": False, "always_down": False, "samples": [],
    })
    assert parsed.phase == 0.0 and parsed.illumination == 0


def valid(**changes):
    document = {
        "night_start": "2026-08-29T02:00:00Z",
        "night_end": "2026-08-29T06:00:00Z",
        "moon": {"phase": 0.5, "illumination": 60, "rise": None, "set": None,
                 "always_up": False, "always_down": False,
                 "samples": [{"time": "2026-08-29T03:00:00Z", "altitude": 10.0, "azimuth": 90.0}]},
        "cloud_cover_score": 0.0,
        "hourly_ratings": [],
    }
    document.update(changes)
    return {key: value for key, value in document.items() if value is not ...}


@pytest.mark.parametrize("document", [
    valid(night_start=...),
    valid(moon=...),
    valid(hourly_ratings=...),
    valid(cloud_cover_score=...),
    valid(best_window={"start": "2026-08-29T02:00:00Z", "end": "2026-08-29T03:00:00Z", "score": 1}),
    valid(best_window=[]),
    valid(hourly_ratings={}),
    valid(cloud_cover_score=[1]),
    valid(cloud_cover_score=True),
    valid(moon={"phase": 0.5}),
])
def test_invalid_documents_fail_closed(document):
    with pytest.raises(ValidationError) as excinfo:
        recommend_moon(document)
    assert str(excinfo.value) == f"invalid {CAPABILITY_ID} input"


def test_row_caps_are_reported_as_sample_cap():
    rows = [{"time": f"2026-08-29T02:{index // 60:02d}:{index % 60:02d}Z", "score": 1.0}
            for index in range(MAX_ROW_COUNT + 1)]
    with pytest.raises(SampleCapError) as excinfo:
        recommend_moon(valid(hourly_ratings=rows))
    assert str(excinfo.value) == (
        f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)"
    )


def test_recommendation_result_shape():
    result = recommend_moon(valid())["recommendation"]
    assert set(result) == {"score", "visibility_window", "reasons"}
    assert set(result["visibility_window"]) == {
        "start", "end", "best_time", "max_altitude", "direction", "azimuth"}
    assert isinstance(result["score"], int)
