"""Focused tests for night_conditions.classify_cloud_timing."""
from __future__ import annotations

import pytest

from astro_engine.cloud_timing import (
    CAPABILITY_ID,
    CLASSIFICATIONS,
    MAX_ROW_COUNT,
    classify_cloud_timing,
)
from astro_engine.contracts import night_quality_calibration
from astro_engine.errors import SampleCapError, ValidationError

BASE_HOUR = 20


def time(offset_seconds: int) -> str:
    total = BASE_HOUR * 3600 + offset_seconds
    day, rest = divmod(total, 86_400)
    hour, rest = divmod(rest, 3600)
    minute, second = divmod(rest, 60)
    return f"2026-03-{3 + day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"


def row(offset_seconds: int, score: float, cloud_cover: int) -> dict:
    return {"time": time(offset_seconds), "score": score, "cloud_cover": cloud_cover}


def verdict(rows) -> str:
    return classify_cloud_timing({"hourly_ratings": rows})["cloud_timing"]


def test_capability_id_and_semantic_domain():
    assert CAPABILITY_ID == "night_conditions.classify_cloud_timing"
    assert CLASSIFICATIONS == ("none", "early_heavy", "late_heavy", "intermittent_heavy")


def test_thresholds_come_from_shared_night_quality_calibration():
    night = night_quality_calibration()
    assert int(night["cloud_floor"]["cloud_cover_min"]) == 80
    assert float(night["rating_thresholds"]["fair_max"]) == 1.0


@pytest.mark.parametrize("rows,expected", [
    ([], "none"),
    ([row(0, 1.2, 90), row(3600, 1.2, 90), row(7200, 0.2, 10)], "early_heavy"),
    ([row(0, 0.2, 10), row(3600, 1.2, 90), row(7200, 1.2, 90)], "late_heavy"),
    ([row(0, 0.2, 10), row(3600, 1.2, 90), row(7200, 1.2, 90), row(10800, 0.2, 10)],
     "intermittent_heavy"),
    ([row(0, 1.5, 100), row(3600, 1.5, 100), row(7200, 1.5, 100)], "none"),
])
def test_four_semantic_verdicts(rows, expected):
    assert verdict(rows) == expected


def test_one_row_and_lone_heavy_hour_never_form_a_run():
    assert verdict([row(0, 1.5, 100)]) == "none"
    assert verdict([row(0, 0.2, 10), row(3600, 1.5, 100), row(7200, 0.2, 10)]) == "none"


def test_two_contiguous_heavy_rows_are_the_minimum_run():
    assert verdict([row(0, 0.2, 10), row(3600, 1.5, 100), row(7200, 1.5, 100)]) == "late_heavy"


def test_heavy_threshold_is_inclusive_and_usable_score_is_strict():
    assert verdict([row(0, 0.2, 10), row(3600, 1.2, 80), row(7200, 1.2, 80)]) == "late_heavy"
    assert verdict([row(0, 0.2, 10), row(3600, 1.2, 79), row(7200, 1.2, 79)]) == "none"
    assert verdict([row(0, 1.0, 10), row(3600, 1.2, 90), row(7200, 1.2, 90)]) == "none"
    assert verdict([row(0, 0.999, 10), row(3600, 1.2, 90), row(7200, 1.2, 90)]) == "late_heavy"


@pytest.mark.parametrize("step", [3599, 3601, 0, -3600, 7200])
def test_adjacency_is_exactly_one_hour(step):
    rows = [row(0, 0.2, 10), row(3600, 1.2, 90), row(3600 + step, 1.2, 90)]
    assert verdict(rows) == "none"


def test_rows_are_never_sorted():
    rows = [row(0, 0.2, 10), row(7200, 1.2, 90), row(3600, 1.2, 90), row(10800, 1.2, 90)]
    assert verdict(rows) == "none"


def test_usable_hours_are_found_anywhere_before_the_run():
    rows = [
        row(0, 0.2, 10),
        row(3600, 1.5, 50), row(7200, 1.5, 50), row(10800, 1.5, 50),
        row(14400, 1.5, 95), row(18000, 1.5, 95),
    ]
    assert verdict(rows) == "late_heavy"


def test_ineligible_runs_are_filtered_before_ranking():
    rows = [
        row(0, 0.5, 100), row(3600, 0.5, 100), row(7200, 0.5, 100),
        row(10800, 1.5, 10),
        row(14400, 1.5, 90), row(18000, 1.5, 90),
    ]
    assert verdict(rows) == "late_heavy"


def test_preference_is_longest_then_cloudiest_then_earliest_start():
    longest = [
        row(0, 1.2, 100), row(3600, 1.2, 100),
        row(7200, 0.2, 10),
        row(10800, 1.2, 85), row(14400, 1.2, 85), row(18000, 1.2, 85),
    ]
    assert verdict(longest) == "late_heavy"

    cloudiest = [
        row(0, 1.2, 100), row(3600, 1.2, 100),
        row(7200, 0.2, 10),
        row(10800, 1.2, 85), row(14400, 1.2, 85),
        row(25200, 0.2, 10),
    ]
    assert verdict(cloudiest) == "early_heavy"

    earliest = [
        row(0, 1.2, 90), row(3600, 1.2, 90),
        row(7200, 0.2, 10),
        row(10800, 1.2, 90), row(14400, 1.2, 90),
        row(25200, 0.2, 10),
    ]
    assert verdict(earliest) == "early_heavy"


@pytest.mark.parametrize("document", [
    {},
    {"hourly_ratings": [], "good_rating_threshold": 1.0},
    {"hourly_ratings": {}},
    {"hourly_ratings": [{"time": time(0), "score": 0.2}]},
    {"hourly_ratings": [{"time": time(0), "score": 0.2, "cloud_cover": 10, "fog_score": 0}]},
    {"hourly_ratings": [{"time": time(0), "score": 0.2, "cloud_cover": 10.5}]},
    {"hourly_ratings": [{"time": time(0), "score": True, "cloud_cover": 10}]},
    {"hourly_ratings": [{"time": time(0), "score": 0.2, "cloud_cover": True}]},
    {"hourly_ratings": [{"time": time(0), "score": "0.2", "cloud_cover": 10}]},
    {"hourly_ratings": [{"time": time(0), "score": float("nan"), "cloud_cover": 10}]},
    {"hourly_ratings": [{"time": time(0), "score": 0.2, "cloud_cover": 2_000_000_000}]},
    {"hourly_ratings": [{"time": "2026-03-03T20:00:00+00:00", "score": 0.2, "cloud_cover": 10}]},
    {"hourly_ratings": [{"time": "2026-03-03T20:00:00.500Z", "score": 0.2, "cloud_cover": 10}]},
    {"hourly_ratings": [{"time": "2026-02-30T20:00:00Z", "score": 0.2, "cloud_cover": 10}]},
    {"hourly_ratings": [{"time": "0000-01-01T00:00:00Z", "score": 0.2, "cloud_cover": 10}]},
])
def test_strict_transport_rejections(document):
    with pytest.raises(ValidationError) as excinfo:
        classify_cloud_timing(document)
    assert str(excinfo.value) == f"invalid {CAPABILITY_ID} input"
    assert excinfo.value.code == "validation"


def test_integral_float_cloud_cover_is_accepted():
    rows = [row(0, 0.2, 10.0), row(3600, 1.2, 90.0), row(7200, 1.2, 90.0)]
    assert verdict(rows) == "late_heavy"


def test_row_cap_is_its_own_error_code():
    rows = [row(0, 0.2, 10)] * (MAX_ROW_COUNT + 1)
    with pytest.raises(SampleCapError) as excinfo:
        classify_cloud_timing({"hourly_ratings": rows})
    assert excinfo.value.code == "sample_cap"
    assert str(excinfo.value) == (
        f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)"
    )
    assert verdict([row(0, 0.2, 10)] * MAX_ROW_COUNT) == "none"
