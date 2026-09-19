"""Focused tests for observing_night.compose_outlook and observing_night.select_best."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.night_outlook import (
    BEST_NIGHT_CAPABILITY_ID,
    CAPABILITY_ID,
    MAX_HOURLY_ROW_COUNT,
    NIGHT_COUNT,
    compose_night_outlook,
    has_complete_hourly_coverage,
    select_best_outlook_night,
)

LA = "America/Los_Angeles"

# Five July days, evening twilight 22:18 local and morning 04:37 local.
DAYS = [
    {
        "astronomical_twilight_begin": f"2026-07-{number:02d}T11:37:00Z",
        "astronomical_twilight_end": f"2026-07-{number + 1:02d}T05:18:00Z",
    }
    for number in range(25, 30)
]

# Hourly rows on the hour from local midnight on July 25.
BASE = datetime(2026, 7, 25, 7, 0, tzinfo=timezone.utc)


def hours(count: int, step: int = 3600) -> list[str]:
    return [
        (BASE + timedelta(seconds=index * step)).strftime("%Y-%m-%dT%H:%M:%SZ")
        for index in range(count)
    ]


def payload(**overrides):
    document = {
        "reference_time": "2026-07-27T03:00:00Z",  # July 26, 20:00 local
        "time_zone": LA,
        "forecast_start_time": hours(1)[0],
        "daily_sun_events": DAYS,
        "daily_moon_count": 5,
        "hourly_times": hours(5 * 24),
    }
    document.update(overrides)
    return document


# --- Composition -------------------------------------------------------------


def test_evening_reference_composes_three_consecutive_available_nights():
    result = compose_night_outlook(payload())
    assert result["state"] == "resolved"
    assert result["time_zone"] == LA
    assert [night["slot_index"] for night in result["nights"]] == [0, 1, 2]
    assert [night["day_offset"] for night in result["nights"]] == [0, 1, 2]
    assert [night["day_index"] for night in result["nights"]] == [1, 2, 3]
    assert [night["observing_date"] for night in result["nights"]] == [
        "2026-07-26", "2026-07-27", "2026-07-28"
    ]
    assert [night["status"] for night in result["nights"]] == ["available"] * 3


def test_after_midnight_keeps_the_preceding_observing_night_in_slot_zero():
    result = compose_night_outlook(payload(reference_time="2026-07-26T08:00:00Z"))
    assert [night["day_offset"] for night in result["nights"]] == [-1, 0, 1]
    assert [night["observing_date"] for night in result["nights"]] == [
        "2026-07-25", "2026-07-26", "2026-07-27"
    ]


def test_requires_active_previous_payload_keeps_its_own_state():
    result = compose_night_outlook(payload(reference_time="2026-07-25T08:00:00Z"))
    assert result["state"] == "requires_active_previous_payload"
    assert [night["observing_date"] for night in result["nights"]] == [
        "2026-07-25", "2026-07-26", "2026-07-27"
    ]
    assert all(night["day_index"] is None for night in result["nights"])
    assert all(night["astronomical_night_start"] is None for night in result["nights"])
    assert all(night["status"] == "unavailable" for night in result["nights"])


def test_composition_is_all_or_nothing():
    result = compose_night_outlook(payload(daily_sun_events=DAYS[:3], daily_moon_count=3))
    assert result["state"] == "unavailable"
    assert [night["observing_date"] for night in result["nights"]] == [
        "2026-07-26", "2026-07-27", "2026-07-28"
    ]
    assert all(night["status"] == "unavailable" for night in result["nights"])
    assert all(night["day_offset"] == index for index, night in enumerate(result["nights"]))


def test_short_moon_array_alone_stops_composition():
    assert compose_night_outlook(payload(daily_moon_count=3))["state"] == "unavailable"


def test_truncated_hourly_stream_marks_only_the_uncovered_night():
    result = compose_night_outlook(
        payload(reference_time="2026-07-26T13:00:00Z", hourly_times=hours(4 * 24))
    )
    assert [night["status"] for night in result["nights"]] == [
        "available", "available", "unavailable"
    ]
    # The window is still reported for the uncovered night.
    assert result["nights"][2]["astronomical_night_start"] is not None


def test_missing_and_duplicate_hourly_rows_break_only_their_own_night():
    missing = hours(5 * 24)
    del missing[49]  # July 27, 01:00 local — inside the first night
    assert [
        night["status"]
        for night in compose_night_outlook(
            payload(reference_time="2026-07-26T13:00:00Z", hourly_times=missing)
        )["nights"]
    ] == ["unavailable", "available", "available"]

    duplicated = hours(5 * 24)
    duplicated.insert(49, duplicated[49])
    assert [
        night["status"]
        for night in compose_night_outlook(
            payload(reference_time="2026-07-26T13:00:00Z", hourly_times=duplicated)
        )["nights"]
    ] == ["unavailable", "available", "available"]


def test_caller_order_of_hourly_rows_is_not_semantics():
    assert compose_night_outlook(payload()) == compose_night_outlook(
        payload(hourly_times=list(reversed(hours(5 * 24))))
    )


def test_non_hourly_cadence_and_empty_stream_cover_nothing():
    half_hourly = compose_night_outlook(payload(hourly_times=hours(5 * 48, step=1800)))
    assert all(night["status"] == "unavailable" for night in half_hourly["nights"])
    empty = compose_night_outlook(payload(forecast_start_time=None, hourly_times=[]))
    assert empty["state"] == "resolved"
    assert all(night["status"] == "unavailable" for night in empty["nights"])


def test_empty_and_inverted_windows_are_no_astronomical_night():
    empty = list(DAYS)
    empty[3] = {
        "astronomical_twilight_begin": "2026-07-28T11:37:00Z",
        "astronomical_twilight_end": "2026-07-29T11:37:00Z",
    }
    assert [
        night["status"] for night in compose_night_outlook(payload(daily_sun_events=empty))["nights"]
    ] == ["available", "available", "no_astronomical_night"]

    inverted = list(DAYS)
    inverted[3] = {
        "astronomical_twilight_begin": "2026-07-28T11:37:00Z",
        "astronomical_twilight_end": "2026-07-29T12:00:00Z",
    }
    assert [
        night["status"]
        for night in compose_night_outlook(payload(daily_sun_events=inverted))["nights"]
    ] == ["available", "available", "no_astronomical_night"]


def test_last_represented_day_falls_back_to_its_own_morning_twilight():
    result = compose_night_outlook(payload(daily_sun_events=DAYS[:4], daily_moon_count=4))
    assert result["state"] == "resolved"
    assert result["nights"][2]["status"] == "no_astronomical_night"
    assert result["nights"][2]["astronomical_night_end"] == "2026-07-28T11:37:00Z"


# --- Coverage rule -----------------------------------------------------------


def test_coverage_requires_the_stream_to_straddle_both_boundaries():
    start = datetime(2026, 7, 26, 5, 18, tzinfo=timezone.utc)
    end = datetime(2026, 7, 27, 11, 37, tzinfo=timezone.utc)
    full = [BASE + timedelta(hours=index) for index in range(5 * 24)]
    assert has_complete_hourly_coverage(start, end, full)
    assert not has_complete_hourly_coverage(start, end, full[40:])
    assert not has_complete_hourly_coverage(end, start, full)


# --- Transport ---------------------------------------------------------------


def test_transport_reports_every_key_for_every_row():
    result = compose_night_outlook(payload())
    assert set(result) == {"state", "time_zone", "nights"}
    for night in result["nights"]:
        assert set(night) == {
            "slot_index", "day_offset", "day_index", "observing_date",
            "observing_day_start", "astronomical_night_start",
            "astronomical_night_end", "status",
        }


@pytest.mark.parametrize("document", [
    payload(display_label="Tonight"),
    payload(time_zone="US/Pacific"),
    payload(time_zone="Mars/Olympus"),
    payload(daily_moon_count=True),
    payload(hourly_times=["2026-07-25T07:00:00+00:00"]),
    payload(hourly_times="not-a-list"),
])
def test_transport_rejects_malformed_input(document):
    with pytest.raises(ValidationError):
        compose_night_outlook(document)


def test_transport_requires_every_key():
    document = payload()
    del document["hourly_times"]
    with pytest.raises(ValidationError):
        compose_night_outlook(document)


def test_transport_caps_rows_and_days():
    with pytest.raises(SampleCapError) as day_cap:
        compose_night_outlook(payload(daily_sun_events=DAYS * 4))
    assert "day cap" in str(day_cap.value)

    with pytest.raises(SampleCapError) as row_cap:
        compose_night_outlook(payload(hourly_times=hours(MAX_HOURLY_ROW_COUNT + 1, step=60)))
    assert str(row_cap.value) == (
        f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_HOURLY_ROW_COUNT} rows)"
    )


def test_skipped_civil_date_zone_is_excluded():
    with pytest.raises(ValidationError):
        compose_night_outlook(payload(
            time_zone="Pacific/Apia",
            reference_time="2011-12-28T08:00:00Z",
            forecast_start_time="2011-12-27T11:00:00Z",
            daily_sun_events=[
                {
                    "astronomical_twilight_begin": f"2011-12-{number:02d}T15:30:00Z",
                    "astronomical_twilight_end": f"2011-12-{number:02d}T07:30:00Z",
                }
                for number in range(27, 31)
            ],
            daily_moon_count=4,
            hourly_times=[
                (datetime(2011, 12, 27, 11, tzinfo=timezone.utc)
                 + timedelta(hours=index)).strftime("%Y-%m-%dT%H:%M:%SZ")
                for index in range(96)
            ],
        ))


# --- Best night --------------------------------------------------------------


def rows(*pairs):
    return {"nights": [{"status": status, "score": score} for status, score in pairs]}


def test_best_night_prefers_the_highest_score_and_keeps_the_earliest_tie():
    assert select_best_outlook_night(rows(
        ("available", 72), ("available", 91), ("available", 80)
    )) == {"best_index": 1}
    assert select_best_outlook_night(rows(
        ("available", 91), ("available", 91), ("available", 80)
    )) == {"best_index": 0}
    assert select_best_outlook_night(rows(
        ("available", 40), ("available", 88), ("available", 88)
    )) == {"best_index": 1}


def test_best_night_eligibility():
    assert select_best_outlook_night(rows(
        ("no_astronomical_night", 99), ("available", 10), ("unavailable", 100)
    )) == {"best_index": 1}
    assert select_best_outlook_night(rows(
        ("available", None), ("unavailable", None), ("no_astronomical_night", None)
    )) == {"best_index": None}
    assert select_best_outlook_night({"nights": []}) == {"best_index": None}


@pytest.mark.parametrize("document", [
    {"nights": [{"status": "available", "score": 10, "display_label": "Tonight"}]},
    {"nights": [{"status": "available", "score": 101}]},
    {"nights": [{"status": "available", "score": -1}]},
    {"nights": [{"status": "available", "score": True}]},
    {"nights": [{"status": "great", "score": 10}]},
    {"nights": [{"status": "available"}]},
    {"nights": "not-a-list"},
    {"rows": []},
])
def test_best_night_transport_rejects_malformed_input(document):
    with pytest.raises(ValidationError):
        select_best_outlook_night(document)


def test_best_night_caps_rows_at_the_outlook_length():
    with pytest.raises(SampleCapError) as excinfo:
        select_best_outlook_night(rows(*[("available", 10)] * (NIGHT_COUNT + 1)))
    assert str(excinfo.value) == (
        f"{BEST_NIGHT_CAPABILITY_ID} exceeds the 1.0 row cap ({NIGHT_COUNT} rows)"
    )
