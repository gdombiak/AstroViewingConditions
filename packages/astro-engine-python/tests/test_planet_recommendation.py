"""Unit semantics for targets.planet_recommendation not covered by the fixtures."""
from __future__ import annotations

import pytest

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.planet_observation import LEAD_SECONDS, TRAIL_SECONDS
from astro_engine.planet_recommendation import (
    CAPABILITY_ID,
    EARLIEST_RATING_EPOCH_SECONDS,
    EARLIEST_SAMPLE_EPOCH_SECONDS,
    LATEST_RATING_EPOCH_SECONDS,
    LATEST_SAMPLE_EPOCH_SECONDS,
    LATEST_WINDOW_EPOCH_SECONDS,
    MAX_ROW_COUNT,
    RATING_SPILL_BEFORE_SECONDS,
    SAMPLE_SPILL_AFTER_SECONDS,
    SAMPLE_SPILL_BEFORE_SECONDS,
    WINDOW_SPILL_AFTER_SECONDS,
    Rating,
    Sample,
    Window,
    calibration,
    compass_direction,
    convenience_score,
    evaluate,
    overlap_fraction,
    recommend_planet,
    venus_twilight_suitability,
    weather_quality,
)

CAL = calibration()
NIGHT_START = 0.0
NIGHT_END = 9 * 3600.0


def sample(hours, altitude, azimuth=180.0, elongation=45.0):
    return Sample((hours - 20) * 3600.0, altitude, azimuth, elongation)


def run(samples, target_id="jupiter", cloud_cover_score=0.0, ratings=()):
    return evaluate(target_id, samples, NIGHT_START, NIGHT_END, cloud_cover_score, ratings, CAL)


@pytest.mark.parametrize("azimuth,expected", [
    (0.0, "N"), (11.24, "N"), (11.25, "NNE"), (22.5, "NNE"), (45.0, "NE"),
    (90.0, "E"), (180.0, "S"), (270.0, "W"), (348.75, "N"), (348.74, "NNW"),
    (359.999, "N"), (360.0, "N"), (-1.0, "N"),
])
def test_compass_direction_is_sixteen_point_and_wraps(azimuth, expected):
    assert compass_direction(azimuth) == expected


def test_no_visible_sample_is_no_recommendation():
    assert run([sample(20, -12.0), sample(22, 7.999999999)]) is None
    assert run([]) is None


def test_visible_altitude_threshold_is_inclusive():
    assert run([sample(22, 8.0)]).window.max_altitude == 8.0


def test_weighted_tie_keeps_the_earliest_sample():
    result = run([sample(22, 40.0, 90.0), sample(23, 40.0, 270.0)])
    assert result.window.azimuth == 90.0


def test_interior_crossings_interpolate_and_the_tail_uses_a_fixed_extension():
    result = run([
        Sample(0.0, 6.0, 120.0, 30.0),
        Sample(900.0, 10.0, 125.0, 30.0),
        Sample(1800.0, 12.0, 130.0, 30.0),
        Sample(2700.0, 4.0, 135.0, 30.0),
    ])
    assert result.window.start == 450.0
    assert result.window.end == 2250.0

    tail = run([Sample(0.0, 20.0, 120.0, 30.0), Sample(900.0, 31.0, 130.0, 30.0)])
    assert tail.window.end == 900.0 + CAL["visibility"]["window_extension_seconds"]


def test_flat_segment_inside_the_epsilon_keeps_the_earlier_instant():
    result = run([
        Sample(0.0, 7.99995, 120.0, 30.0),
        Sample(3600.0, 8.00004, 125.0, 30.0),
        Sample(7200.0, 30.0, 130.0, 30.0),
    ])
    assert result.window.start == 0.0


def test_convenience_bands_and_their_precedence():
    assert convenience_score(-2 * 3600.0, NIGHT_START, NIGHT_END, CAL) == 1
    assert convenience_score(4 * 3600.0, NIGHT_START, NIGHT_END, CAL) == 1
    assert convenience_score(5 * 3600.0, NIGHT_START, NIGHT_END, CAL) == 0.65
    assert convenience_score(6 * 3600.0, NIGHT_START, NIGHT_END, CAL) == 0.35
    assert convenience_score(-3 * 3600.0, NIGHT_START, NIGHT_END, CAL) == 0.65
    # Overlapping bands in a short night: evening is tested first and wins.
    assert convenience_score(3600.0, 0.0, 2 * 3600.0, CAL) == 1


def test_overlap_fraction_is_relative_to_the_window():
    assert overlap_fraction(-2 * 3600.0, 2 * 3600.0, NIGHT_START, NIGHT_END) == 0.5
    assert overlap_fraction(3600.0, 3600.0, NIGHT_START, NIGHT_END) == 0.0


def test_hourly_rating_overlap_is_open_on_both_sides():
    window = Window(0.0, 3600.0, 0.0, 30.0, "S", 180.0)
    assert weather_quality(window, 100.0, [Rating(-3600.0, 0.0)], CAL) == 0
    assert weather_quality(window, 100.0, [Rating(3600.0, 0.0)], CAL) == 0
    assert weather_quality(window, 100.0, [Rating(-3599.0, 0.0)], CAL) == 1


def test_only_venus_earns_twilight_credit():
    samples = [sample(18, 22.0, 260.0, 46.0), sample(19, 12.0, 270.0, 46.0),
               sample(20, 7.9, 280.0, 46.0)]
    venus = run(samples, target_id="venus")
    jupiter = run(samples, target_id="jupiter")
    assert venus.score > jupiter.score
    assert run(samples, target_id="VENUS").score == venus.score


def test_venus_twilight_components_saturate_at_their_production_bounds():
    window = Window(-2 * 3600.0, -3600.0, -2 * 3600.0, 20.0, "W", 265.0)
    best = Sample(-2 * 3600.0, 20.0, 265.0, 45.0)
    assert venus_twilight_suitability(best, window, NIGHT_START, NIGHT_END, CAL) == pytest.approx(1)
    missing = Sample(-2 * 3600.0, 20.0, 265.0, None)
    assert venus_twilight_suitability(missing, window, NIGHT_START, NIGHT_END, CAL) == pytest.approx(0.75)
    far = Window(-6 * 3600.0, -5 * 3600.0, -6 * 3600.0, 30.0, "W", 265.0)
    assert venus_twilight_suitability(Sample(-6 * 3600.0, 30.0, 265.0, 46.0), far,
                                      NIGHT_START, NIGHT_END, CAL) == 0


def test_reason_order_and_the_always_present_moonlight_code():
    assert run([sample(22, 50.0)]).reasons == (
        "highAltitude", "astronomicalDarkness", "convenientPlanetWindow",
        "goodNightQuality", "planetMoonlightResistant",
    )
    assert run([sample(17, 30.0)], cloud_cover_score=45.0).reasons == ("planetMoonlightResistant",)


def test_astronomical_darkness_reason_uses_the_overlap_not_the_venus_visibility_quality():
    result = run([sample(18, 22.0, 260.0, 46.0), sample(19, 12.0, 270.0, 46.0),
                  sample(20, 7.9, 280.0, 46.0)], target_id="venus")
    assert "astronomicalDarkness" not in result.reasons


# --- transport ------------------------------------------------------------


def row(time, altitude=40.0, azimuth=180.0, elongation=45.0):
    return {"time": time, "altitude": altitude, "azimuth": azimuth,
            "solar_elongation": elongation}


def document(**changes):
    base = dict(target_id="jupiter", night_start="2026-03-01T20:00:00Z",
                night_end="2026-03-02T05:00:00Z",
                samples=[row("2026-03-01T22:00:00Z")], cloud_cover_score=0.0,
                hourly_ratings=[])
    base.update(changes)
    return base


def test_transport_emits_the_objective_result():
    result = recommend_planet(document())["recommendation"]
    assert result["visibility_window"]["direction"] == "S"
    assert result["visibility_window"]["max_altitude"] == 40.0
    assert result["reasons"] == ["astronomicalDarkness", "convenientPlanetWindow",
                                 "goodNightQuality", "planetMoonlightResistant"]


def test_transport_returns_null_when_nothing_is_visible():
    assert recommend_planet(document(samples=[row("2026-03-01T22:00:00Z", altitude=1.0)])) == {
        "recommendation": None
    }


def test_solar_elongation_may_be_null():
    result = recommend_planet(document(samples=[row("2026-03-01T22:00:00Z", elongation=None)]))
    assert result["recommendation"] is not None


@pytest.mark.parametrize("changes", [
    dict(extra=1),
    dict(target_id="earth"),
    dict(target_id="moon"),
    dict(cloud_cover_score=True),
    dict(cloud_cover_score="5"),
    dict(night_start="1999-12-31T23:59:59Z"),
    dict(samples={"time": "2026-03-01T22:00:00Z"}),
    dict(hourly_ratings=3),
    dict(samples=[row("2026-03-01T23:00:00Z"), row("2026-03-01T22:00:00Z")]),
    dict(samples=[row("2026-03-01T22:00:00Z"), row("2026-03-01T22:00:00Z")]),
    dict(samples=[dict(row("2026-03-01T22:00:00Z"), extra=1)]),
    dict(samples=[{"time": "2026-03-01T22:00:00Z", "altitude": 40.0, "azimuth": None,
                   "solar_elongation": 45.0}]),
    dict(hourly_ratings=[{"time": "2026-03-01T22:00:00Z", "score": 1.0, "extra": 1}]),
])
def test_transport_fails_closed(changes):
    with pytest.raises(ValidationError):
        recommend_planet(document(**changes))


@pytest.mark.parametrize("key", ["target_id", "night_start", "night_end", "samples",
                                 "cloud_cover_score", "hourly_ratings"])
def test_missing_required_fields_fail_closed(key):
    payload = document()
    del payload[key]
    with pytest.raises(ValidationError):
        recommend_planet(payload)


@pytest.mark.parametrize("key", ["samples", "hourly_ratings"])
def test_row_caps_are_enforced_on_both_injected_arrays(key):
    rows = [{"time": f"2026-03-01T{20 + index // 3600:02d}:{index // 60 % 60:02d}:"
                     f"{index % 60:02d}Z", "score": 1.0}
            for index in range(MAX_ROW_COUNT + 1)]
    if key == "samples":
        rows = [row(entry["time"]) for entry in rows]
    with pytest.raises(SampleCapError) as excinfo:
        recommend_planet(document(**{key: rows}))
    assert str(excinfo.value) == (
        f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)"
    )


# --- bounded spill --------------------------------------------------------

LOW_NIGHT = dict(night_start="2000-01-01T00:00:00Z", night_end="2000-01-01T08:00:00Z")
HIGH_NIGHT = dict(night_start="2499-12-31T15:00:00Z", night_end="2499-12-31T23:59:59Z")


def _utc(seconds):
    from datetime import datetime, timedelta, timezone

    return (datetime(1970, 1, 1, tzinfo=timezone.utc)
            + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")


def test_spill_bounds_are_derived_from_production_sampling_and_scoring():
    assert SAMPLE_SPILL_BEFORE_SECONDS == LEAD_SECONDS
    assert SAMPLE_SPILL_AFTER_SECONDS == TRAIL_SECONDS
    assert WINDOW_SPILL_AFTER_SECONDS == TRAIL_SECONDS + CAL["visibility"]["window_extension_seconds"]
    assert RATING_SPILL_BEFORE_SECONDS == LEAD_SECONDS + CAL["weather"]["hourly_rating_seconds"]
    assert _utc(EARLIEST_SAMPLE_EPOCH_SECONDS) == "1999-12-31T22:00:00Z"
    assert _utc(LATEST_SAMPLE_EPOCH_SECONDS) == "2500-01-01T00:59:59Z"
    assert _utc(EARLIEST_RATING_EPOCH_SECONDS) == "1999-12-31T21:00:00Z"
    assert _utc(LATEST_RATING_EPOCH_SECONDS) == "2500-01-01T01:14:59Z"
    assert _utc(LATEST_WINDOW_EPOCH_SECONDS) == "2500-01-01T01:14:59Z"


def test_samples_from_the_observation_lead_are_accepted_and_can_open_the_window():
    window = recommend_planet(document(
        samples=[row("1999-12-31T22:00:00Z", altitude=30.0)], **LOW_NIGHT,
    ))["recommendation"]["visibility_window"]
    assert window["start"] == "1999-12-31T22:00:00Z"
    assert window["best_time"] == "1999-12-31T22:00:00Z"
    assert window["end"] == "1999-12-31T22:15:00Z"


def test_the_latest_window_end_is_emittable():
    window = recommend_planet(document(
        samples=[row("2500-01-01T00:59:59Z", altitude=30.0)], **HIGH_NIGHT,
    ))["recommendation"]["visibility_window"]
    assert window["end"] == "2500-01-01T01:14:59Z"


def test_ratings_may_reach_one_hour_before_the_earliest_window_start():
    base = dict(samples=[row("1999-12-31T22:00:00Z", altitude=30.0)],
                cloud_cover_score=100.0, **LOW_NIGHT)
    inside = recommend_planet(document(
        hourly_ratings=[{"time": "1999-12-31T21:00:01Z", "score": 0.0}], **base))
    assert "goodNightQuality" in inside["recommendation"]["reasons"]
    # Exactly on the floor: accepted, but the strict overlap test excludes it.
    on_floor = recommend_planet(document(
        hourly_ratings=[{"time": "1999-12-31T21:00:00Z", "score": 0.0}], **base))
    assert "poorWeather" in on_floor["recommendation"]["reasons"]


@pytest.mark.parametrize("changes", [
    dict(samples=[row("1999-12-31T21:59:59Z", altitude=30.0)], **LOW_NIGHT),
    dict(samples=[row("2500-01-01T01:00:00Z", altitude=30.0)], **HIGH_NIGHT),
    dict(samples=[row("1999-12-31T22:00:00Z", altitude=30.0)],
         hourly_ratings=[{"time": "1999-12-31T20:59:59Z", "score": 0.0}], **LOW_NIGHT),
    dict(samples=[row("2500-01-01T00:00:00Z", altitude=30.0)],
         hourly_ratings=[{"time": "2500-01-01T01:15:00Z", "score": 0.0}], **HIGH_NIGHT),
])
def test_instants_outside_the_justified_spill_fail_closed(changes):
    with pytest.raises(ValidationError):
        recommend_planet(document(**changes))


@pytest.mark.parametrize("field,value", [
    ("night_start", "1999-12-31T23:00:00Z"),
    ("night_end", "2500-01-01T00:00:00Z"),
])
def test_night_instants_keep_the_unspilled_range(field, value):
    """The spill applies to provider-derived instants, not to the night interval."""
    with pytest.raises(ValidationError):
        recommend_planet(document(**{field: value}))
