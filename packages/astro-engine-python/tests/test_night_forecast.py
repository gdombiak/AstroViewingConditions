"""Focused tests for night_forecast.derive_window."""
from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest

from astro_engine.errors import ValidationError
from astro_engine.night_forecast import (
    CAPABILITY_ID,
    _set_wall_time,
    derive_night_forecast_window,
    derive_window,
)


def instant(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)


def payload(**overrides):
    result = {
        "observing_time": "2026-02-19T20:00:00Z",
        "time_zone": "America/Los_Angeles",
        "astronomical_twilight_end": "2026-02-20T03:16:47Z",
        "astronomical_twilight_begin": "2026-02-19T13:34:59Z",
        "tomorrow_astronomical_twilight_begin": "2026-02-20T13:33:58Z",
    }
    result.update(overrides)
    return result


def test_capability_id_and_ordinary_projection_drop_seconds():
    assert CAPABILITY_ID == "night_forecast.derive_window"
    assert derive_night_forecast_window(payload()) == {
        "time_zone": "America/Los_Angeles",
        "start": "2026-02-20T03:16:00Z",
        "end": "2026-02-20T13:33:00Z",
    }


def test_spring_gap_snaps_to_transition_instant():
    zone = ZoneInfo("America/Los_Angeles")
    assert _set_wall_time(instant("2026-03-08T08:00:00Z"), 2, 30, zone) == instant(
        "2026-03-08T10:00:00Z"
    )


def test_fall_back_chooses_first_repeated_occurrence():
    zone = ZoneInfo("America/Los_Angeles")
    assert _set_wall_time(instant("2026-11-01T07:00:00Z"), 1, 30, zone) == instant(
        "2026-11-01T08:30:00Z"
    )


@pytest.mark.parametrize(("identifier", "day", "hour", "minute", "expected"), [
    # A partial-hour gap does not use Foundation's one-label skipped-hour
    # approximation; the field search reaches the next day's exact clock.
    ("Australia/Lord_Howe", "2026-10-04T12:00:00Z", 2, 15,
     "2026-10-04T15:15:00Z"),
    # The Chatham transition bisects Foundation's nominal-length hour interval;
    # the mismatched field candidate is adjusted to that interval's 04:00 end.
    ("Pacific/Chatham", "2026-09-26T12:00:00Z", 2, 45,
     "2026-09-26T14:15:00Z"),
    ("America/Bahia_Banderas", "2010-04-04T12:00:00Z", 2, 30,
     "2010-04-05T07:30:00Z"),
    ("America/Godthab", "2024-03-30T12:00:00Z", 23, 30,
     "2024-04-01T00:30:00Z"),
    # 03:15 exists after Caracas's 02:30 -> 03:00 jump, but the hour interval
    # starting at 02:00 still runs 3600 s, so the search enters hour 03 at
    # 03:30 and therefore finds 03:15 the next day.
    ("America/Caracas", "2016-05-01T12:00:00Z", 3, 15,
     "2016-05-02T07:15:00Z"),
    # A multi-hour midnight jump is not Foundation's special 23 -> 1 case.
    ("Antarctica/Casey", "2016-10-21T16:00:00Z", 0, 30,
     "2016-10-22T13:30:00Z"),
])
def test_nonstandard_forward_transition_field_search(
    identifier, day, hour, minute, expected
):
    assert _set_wall_time(
        instant(day), hour, minute, ZoneInfo(identifier)
    ) == instant(expected)


@pytest.mark.parametrize("identifier,day,hour,minute,expected", [
    # Foundation starts the search half a second before the day's first instant,
    # so the clock hour that ends the previous civil date can resolve onto that
    # previous date. St. John's falls back at 00:01, and rejecting the earlier
    # occurrence resumes the search one hour on rather than a whole day on.
    ("America/St_Johns", "2000-10-29T16:00:00Z", 23, 1,
     "2000-10-29T02:31:00Z"),
    # Casey's three-hour backward jump at 23:00 puts the whole of hour 23 on the
    # previous civil date.
    ("Antarctica/Casey", "2010-03-05T04:00:00Z", 23, 15,
     "2010-03-04T15:15:00Z"),
    # Mirror case: Pyongyang's half-hour jump at midnight drops 23:30, and the
    # rejected candidate resumes at the next day's first instant instead of
    # overshooting a further day.
    ("Asia/Pyongyang", "2018-05-04T03:00:00Z", 23, 30,
     "2018-05-05T14:30:00Z"),
])
def test_search_start_before_the_day_reaches_the_previous_civil_date(
    identifier, day, hour, minute, expected
):
    assert _set_wall_time(
        instant(day), hour, minute, ZoneInfo(identifier)
    ) == instant(expected)


def test_exact_clocks_after_partial_hour_search_boundary_stay_on_current_day():
    assert _set_wall_time(
        instant("2016-05-01T12:00:00Z"), 3, 30, ZoneInfo("America/Caracas")
    ) == instant("2016-05-01T07:30:00Z")
    assert _set_wall_time(
        instant("2026-10-04T12:00:00Z"), 2, 30, ZoneInfo("Australia/Lord_Howe")
    ) == instant("2026-10-03T15:30:00Z")


def test_skipped_midnight_hour_is_reachable():
    result = derive_night_forecast_window(payload(
        observing_time="2026-09-06T20:00:00Z",
        time_zone="America/Santiago",
        astronomical_twilight_end="2026-09-05T04:30:11Z",
        astronomical_twilight_begin="2026-09-05T09:40:22Z",
        tomorrow_astronomical_twilight_begin="2026-09-07T08:30:33Z",
    ))
    assert result == {
        "time_zone": "America/Santiago",
        "start": "2026-09-06T04:00:00Z",
        "end": "2026-09-07T08:30:00Z",
    }


def test_non_hour_offset_and_missing_tomorrow_fallback():
    result = derive_night_forecast_window(payload(
        observing_time="2026-04-10T06:15:00Z",
        time_zone="Asia/Kathmandu",
        astronomical_twilight_end="2026-04-10T15:02:44Z",
        astronomical_twilight_begin="2026-04-09T23:22:55Z",
        tomorrow_astronomical_twilight_begin=None,
    ))
    assert result == {
        "time_zone": "Asia/Kathmandu",
        "start": "2026-04-10T15:02:00Z",
        "end": "2026-04-10T23:22:00Z",
    }


def test_typed_deriver_does_not_validate_transport_timezone_catalogue():
    window = derive_window(
        instant("2026-02-19T20:00:00Z"),
        ZoneInfo("Etc/UTC"),
        instant("2026-02-19T20:15:59Z"),
        instant("2026-02-19T05:30:59Z"),
        None,
    )
    assert window.start == instant("2026-02-19T20:15:00Z")
    assert window.end == instant("2026-02-20T05:30:00Z")


@pytest.mark.parametrize("overrides", [
    {"time_zone": "UTC"},
    {"time_zone": "Mars/Olympus_Mons"},
    {"observing_time": "2026-02-19T20:00Z"},
    {"observing_time": "1999-12-31T23:59:59Z"},
    {"astronomical_twilight_end": None},
    {"astronomical_twilight_begin": True},
    {"tomorrow_astronomical_twilight_begin": "not-a-time"},
])
def test_transport_rejects_malformed_inputs(overrides):
    with pytest.raises(ValidationError, match="invalid night_forecast.derive_window input"):
        derive_night_forecast_window(payload(**overrides))


def test_transport_requires_exact_shape():
    missing = payload()
    missing.pop("tomorrow_astronomical_twilight_begin")
    with pytest.raises(ValidationError):
        derive_night_forecast_window(missing)
    with pytest.raises(ValidationError):
        derive_night_forecast_window({**payload(), "forecasts": []})


def test_derived_output_must_remain_in_shared_instant_range():
    with pytest.raises(ValidationError):
        derive_night_forecast_window(payload(
            observing_time="2499-12-31T12:00:00Z",
            time_zone="America/Los_Angeles",
        ))
