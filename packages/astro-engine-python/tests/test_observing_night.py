"""Focused tests for observing_night.resolve_active."""
from __future__ import annotations

from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import pytest

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.observing_night import (
    CAPABILITY_ID,
    DAY_DIFFERENCE_BOUND,
    MAX_DAY_COUNT,
    _add_days,
    _date_exists,
    _same_local_day,
    _start_of_day,
    _whole_days,
    allowed_timezone_identifiers,
    resolve_active_observing_night,
)

LA = "America/Los_Angeles"
DAYS = [
    {"astronomical_twilight_begin": "2026-02-18T13:35:00Z",
     "astronomical_twilight_end": "2026-02-19T03:15:00Z"},
    {"astronomical_twilight_begin": "2026-02-19T13:34:00Z",
     "astronomical_twilight_end": "2026-02-20T03:16:00Z"},
    {"astronomical_twilight_begin": "2026-02-20T13:33:00Z",
     "astronomical_twilight_end": "2026-02-21T03:17:00Z"},
    {"astronomical_twilight_begin": "2026-02-21T13:32:00Z",
     "astronomical_twilight_end": "2026-02-22T03:18:00Z"},
]


def payload(**overrides):
    document = {
        "reference_time": "2026-02-20T05:00:00Z",
        "time_zone": LA,
        "forecast_start_time": "2026-02-18T08:00:00Z",
        "daily_sun_events": DAYS,
        "daily_moon_count": 4,
    }
    document.update(overrides)
    return document


def instant(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)


def test_capability_id():
    assert CAPABILITY_ID == "observing_night.resolve_active"


# --- states ------------------------------------------------------------------


def test_evening_resolves_the_reference_civil_date():
    result = resolve_active_observing_night(payload())
    assert result["state"] == "resolved"
    assert (result["day_offset"], result["day_index"]) == (0, 1)
    assert result["observing_date"] == "2026-02-19"


def test_after_midnight_keeps_the_preceding_civil_date():
    result = resolve_active_observing_night(payload(reference_time="2026-02-20T10:00:00Z"))
    assert (result["state"], result["day_offset"]) == ("resolved", -1)
    assert result["observing_date"] == "2026-02-19"


def test_before_dawn_without_a_previous_row_requires_an_active_previous_payload():
    result = resolve_active_observing_night(payload(reference_time="2026-02-18T12:00:00Z"))
    assert result["state"] == "requires_active_previous_payload"
    assert result["time_zone"] == LA
    assert all(
        result[key] is None
        for key in ("day_offset", "day_index", "observing_date", "observing_day_start",
                    "astronomical_night_start", "astronomical_night_end")
    )


def test_states_are_never_collapsed():
    """`unavailable` and `requires_active_previous_payload` are different facts."""
    unavailable = resolve_active_observing_night(payload(reference_time="2026-02-23T05:00:00Z"))
    requires = resolve_active_observing_night(payload(reference_time="2026-02-18T12:00:00Z"))
    assert unavailable["state"] == "unavailable"
    assert requires["state"] == "requires_active_previous_payload"
    assert unavailable != requires


# --- boundary inclusivity -----------------------------------------------------


@pytest.mark.parametrize("reference,state,offset", [
    ("2026-02-18T13:34:59Z", "requires_active_previous_payload", None),
    ("2026-02-18T13:35:00Z", "requires_active_previous_payload", None),
    ("2026-02-18T13:35:01Z", "resolved", 0),
])
def test_morning_twilight_begin_comparison_is_inclusive(reference, state, offset):
    result = resolve_active_observing_night(payload(reference_time=reference))
    assert result["state"] == state
    assert result["day_offset"] == offset


@pytest.mark.parametrize("reference,offset", [
    ("2026-02-20T13:32:59Z", -1),
    ("2026-02-20T13:33:00Z", -1),
    ("2026-02-20T13:33:01Z", 0),
])
def test_previous_night_end_comparison_is_inclusive(reference, offset):
    result = resolve_active_observing_night(payload(reference_time=reference))
    assert (result["state"], result["day_offset"]) == ("resolved", offset)


def test_previous_night_start_comparison_is_inclusive():
    """Reachable only when evening twilight ends after local midnight."""
    madrid = [
        {"astronomical_twilight_begin": "2026-06-19T01:44:00Z",
         "astronomical_twilight_end": "2026-06-19T22:14:00Z"},
        {"astronomical_twilight_begin": "2026-06-20T01:45:00Z",
         "astronomical_twilight_end": "2026-06-20T22:15:00Z"},
        {"astronomical_twilight_begin": "2026-06-21T01:45:00Z",
         "astronomical_twilight_end": "2026-06-21T22:16:00Z"},
    ]
    document = {
        "time_zone": "Europe/Madrid",
        "forecast_start_time": "2026-06-18T22:00:00Z",
        "daily_sun_events": madrid,
        "daily_moon_count": 3,
    }
    at_start = resolve_active_observing_night(
        {**document, "reference_time": "2026-06-20T22:15:00Z"}
    )
    assert (at_start["day_offset"], at_start["observing_date"]) == (-1, "2026-06-20")
    just_before = resolve_active_observing_night(
        {**document, "reference_time": "2026-06-20T22:14:59Z"}
    )
    # One second earlier is still local 2026-06-21, and that date has not yet
    # reached its own morning twilight, so no night in this payload is active.
    assert just_before["state"] == "requires_active_previous_payload"


# --- indexing -----------------------------------------------------------------


def test_empty_hourly_forecast_uses_the_bare_day_offset():
    result = resolve_active_observing_night(
        payload(reference_time="2026-02-20T10:00:00Z", forecast_start_time=None)
    )
    assert (result["state"], result["day_offset"], result["day_index"]) == ("resolved", 0, 0)
    assert result["observing_date"] == "2026-02-20"


def test_empty_hourly_forecast_can_never_resolve_the_preceding_night():
    for reference in ("2026-02-19T10:00:00Z", "2026-02-20T10:00:00Z", "2026-02-21T10:00:00Z"):
        result = resolve_active_observing_night(
            payload(reference_time=reference, forecast_start_time=None)
        )
        assert result["day_offset"] != -1


def test_forecast_starting_after_the_reference_day_is_unavailable():
    result = resolve_active_observing_night(
        payload(reference_time="2026-02-18T05:00:00Z",
                forecast_start_time="2026-02-20T08:00:00Z")
    )
    assert result["state"] == "unavailable"


def test_short_moon_array_bounds_the_selection():
    assert resolve_active_observing_night(payload(daily_moon_count=1))["state"] == "unavailable"
    assert resolve_active_observing_night(payload(daily_moon_count=2))["state"] == "resolved"


def test_missing_following_row_falls_back_to_the_same_day_morning_twilight():
    result = resolve_active_observing_night(payload(reference_time="2026-02-22T05:00:00Z"))
    assert result["day_index"] == 3
    assert result["astronomical_night_start"] == "2026-02-22T03:18:00Z"
    assert result["astronomical_night_end"] == "2026-02-21T13:32:00Z"
    assert result["astronomical_night_end"] < result["astronomical_night_start"]


# --- local calendar semantics --------------------------------------------------


def test_repeated_local_midnight_add_keeps_the_source_offset():
    """`date(byAdding:)` is not `startOfDay`: it takes the LATER occurrence.

    Foundation ground truth from the differential scan; `America/Havana` repeats
    local midnight on 2026-11-01.
    """
    zone = ZoneInfo("America/Havana")
    reference_day = _start_of_day(instant("2026-11-02T07:00:00Z"), zone)
    assert reference_day == instant("2026-11-02T05:00:00Z")
    assert _add_days(reference_day, -1, zone) == instant("2026-11-01T05:00:00Z")
    # startOfDay of the same civil date is the EARLIER occurrence, one hour before.
    assert _start_of_day(instant("2026-11-01T12:00:00Z"), zone) == instant(
        "2026-11-01T04:00:00Z"
    )


def test_repeated_local_midnight_in_a_second_current_zone():
    zone = ZoneInfo("Atlantic/Azores")
    reference_day = _start_of_day(instant("2026-10-26T02:00:00Z"), zone)
    assert reference_day == instant("2026-10-26T01:00:00Z")
    assert _add_days(reference_day, -1, zone) == instant("2026-10-25T01:00:00Z")
    assert _start_of_day(instant("2026-10-25T12:00:00Z"), zone) == instant(
        "2026-10-25T00:00:00Z"
    )


def test_dropped_civil_dates_are_detected():
    """Pacific/Apia and Pacific/Fakaofo have no 2011-12-30."""
    from datetime import date as civil

    for name in ("Pacific/Apia", "Pacific/Fakaofo"):
        zone = ZoneInfo(name)
        assert not _date_exists(civil(2011, 12, 30), zone)
        assert _date_exists(civil(2011, 12, 29), zone)
        assert _date_exists(civil(2011, 12, 31), zone)
    # A skipped *hour* is not a skipped date.
    assert _date_exists(civil(2026, 9, 6), ZoneInfo("America/Santiago"))


def test_a_window_containing_a_dropped_civil_date_is_refused():
    samoa = [
        {"astronomical_twilight_begin": "2011-12-28T15:30:00Z",
         "astronomical_twilight_end": "2011-12-29T07:10:00Z"},
        {"astronomical_twilight_begin": "2011-12-29T15:31:00Z",
         "astronomical_twilight_end": "2011-12-30T07:11:00Z"},
        {"astronomical_twilight_begin": "2011-12-30T15:32:00Z",
         "astronomical_twilight_end": "2011-12-31T07:12:00Z"},
    ]
    for name in ("Pacific/Apia", "Pacific/Fakaofo"):
        with pytest.raises(ValidationError):
            resolve_active_observing_night({
                "reference_time": "2011-12-31T12:00:00Z", "time_zone": name,
                "forecast_start_time": "2011-12-28T10:00:00Z",
                "daily_sun_events": samoa, "daily_moon_count": 3,
            })


def test_the_same_zone_is_accepted_away_from_its_dropped_date():
    result = resolve_active_observing_night({
        "reference_time": "2026-06-16T08:00:00Z", "time_zone": "Pacific/Apia",
        "forecast_start_time": "2026-06-14T11:00:00Z",
        "daily_sun_events": [
            {"astronomical_twilight_begin": "2026-06-14T15:30:00Z",
             "astronomical_twilight_end": "2026-06-15T07:10:00Z"},
            {"astronomical_twilight_begin": "2026-06-15T15:31:00Z",
             "astronomical_twilight_end": "2026-06-16T07:11:00Z"},
            {"astronomical_twilight_begin": "2026-06-16T15:32:00Z",
             "astronomical_twilight_end": "2026-06-17T07:12:00Z"},
        ],
        "daily_moon_count": 3,
    })
    assert result["state"] == "resolved"
    assert result["observing_date"] == "2026-06-16"


def test_start_of_day_on_a_skipped_midnight_is_the_transition_instant():
    zone = ZoneInfo("America/Santiago")
    assert _start_of_day(instant("2026-09-06T12:00:00Z"), zone) == instant("2026-09-06T04:00:00Z")


def test_start_of_day_on_a_normal_day():
    zone = ZoneInfo(LA)
    assert _start_of_day(instant("2026-02-19T23:00:00Z"), zone) == instant("2026-02-19T08:00:00Z")


def test_add_days_preserves_wall_clock_across_a_spring_transition():
    zone = ZoneInfo(LA)
    # 2026-03-07 00:00 PST + 1 day = 2026-03-08 00:00 PST (the 02:00 shift is later).
    assert _add_days(instant("2026-03-07T08:00:00Z"), 1, zone) == instant("2026-03-08T08:00:00Z")
    # + 2 days lands after the shift, an hour earlier in UTC.
    assert _add_days(instant("2026-03-07T08:00:00Z"), 2, zone) == instant("2026-03-09T07:00:00Z")


def test_whole_days_matches_the_civil_date_difference_in_a_normal_zone():
    zone = ZoneInfo(LA)
    assert _whole_days(instant("2026-03-07T08:00:00Z"), instant("2026-03-09T07:00:00Z"), zone) == 2
    assert _whole_days(instant("2026-03-09T07:00:00Z"), instant("2026-03-07T08:00:00Z"), zone) == -2


def test_whole_days_from_a_skipped_midnight_loses_one_day():
    """Frozen Foundation quirk: 01:00 + 1 day overshoots the next 00:00."""
    zone = ZoneInfo("America/Santiago")
    start = _start_of_day(instant("2026-09-06T12:00:00Z"), zone)   # 01:00 local
    end = _start_of_day(instant("2026-09-07T12:00:00Z"), zone)     # 00:00 local
    assert (start, end) == (instant("2026-09-06T04:00:00Z"), instant("2026-09-07T03:00:00Z"))
    assert _whole_days(start, end, zone) == 0


def test_same_local_day():
    zone = ZoneInfo(LA)
    assert _same_local_day(instant("2026-02-19T08:00:00Z"), instant("2026-02-20T07:59:59Z"), zone)
    assert not _same_local_day(instant("2026-02-19T08:00:00Z"), instant("2026-02-20T08:00:00Z"), zone)


def test_non_whole_hour_offsets_are_honoured():
    kathmandu = resolve_active_observing_night({
        "reference_time": "2026-04-10T19:45:00Z",
        "time_zone": "Asia/Kathmandu",
        "forecast_start_time": "2026-04-09T18:15:00Z",
        "daily_sun_events": [
            {"astronomical_twilight_begin": "2026-04-09T22:50:00Z",
             "astronomical_twilight_end": "2026-04-10T14:10:00Z"},
            {"astronomical_twilight_begin": "2026-04-10T22:49:00Z",
             "astronomical_twilight_end": "2026-04-11T14:11:00Z"},
        ],
        "daily_moon_count": 2,
    })
    assert kathmandu["observing_day_start"] == "2026-04-09T18:15:00Z"
    assert (kathmandu["day_offset"], kathmandu["observing_date"]) == (-1, "2026-04-10")


# --- strict transport ----------------------------------------------------------


@pytest.mark.parametrize("overrides", [
    {"time_zone": "Mars/Olympus_Mons"},
    {"time_zone": ""},
    {"time_zone": 0},
    {"time_zone": "GMT-0800"},
    {"time_zone": "GMT"},
    {"time_zone": "UTC"},
    {"time_zone": "Etc/GMT+8"},
    {"time_zone": "US/Pacific"},
    {"time_zone": "EST5EDT"},
    {"time_zone": "right/UTC"},
    {"reference_time": "2026-02-20T05:00Z"},
    {"reference_time": "1999-12-31T23:59:59Z"},
    {"reference_time": None},
    {"forecast_start_time": "not-a-time"},
    {"daily_sun_events": {}},
    {"daily_moon_count": True},
    {"daily_moon_count": 2.5},
    {"daily_moon_count": -1},
    {"daily_moon_count": 17},
])
def test_invalid_inputs_fail_closed(overrides):
    with pytest.raises(ValidationError):
        resolve_active_observing_night(payload(**overrides))


@pytest.mark.parametrize("row", [
    {"astronomical_twilight_begin": "2026-02-18T13:35:00Z"},
    {"astronomical_twilight_begin": "2026-02-18T13:35:00Z",
     "astronomical_twilight_end": "2026-02-19T03:15:00Z",
     "sunset": "2026-02-19T02:00:00Z"},
    {"astronomical_twilight_begin": "2026-02-18T13:35:00Z",
     "astronomical_twilight_end": None},
])
def test_day_rows_fail_closed(row):
    with pytest.raises(ValidationError):
        resolve_active_observing_night(payload(daily_sun_events=[row]))


def test_unknown_and_missing_top_level_keys_fail_closed():
    with pytest.raises(ValidationError):
        resolve_active_observing_night({**payload(), "location": {}})
    document = payload()
    del document["forecast_start_time"]
    with pytest.raises(ValidationError):
        resolve_active_observing_night(document)


def test_public_timezone_policy_is_a_shared_catalogued_set():
    allowed = allowed_timezone_identifiers()
    assert allowed_timezone_identifiers() is allowed          # cached
    assert all("/" in identifier for identifier in allowed)
    for catalogued in ("America/Los_Angeles", "America/Havana", "Atlantic/Azores",
                       "Pacific/Apia", "Pacific/Fakaofo", "Australia/Lord_Howe",
                       "Asia/Kathmandu", "America/Santiago"):
        assert catalogued in allowed
    for alias in ("GMT-0800", "GMT", "UTC", "Etc/UTC", "US/Pacific", "right/UTC"):
        assert alias not in allowed


def test_instant_range_boundaries():
    """2000-01-01T00:00:00Z .. 2499-12-31T23:59:59Z inclusive."""
    for accepted in ("2000-01-01T00:00:00Z", "2499-12-31T23:59:59Z"):
        assert resolve_active_observing_night(
            payload(reference_time=accepted)
        )["state"] == "unavailable"
    for rejected in ("1999-12-31T23:59:59Z", "2500-01-01T00:00:00Z"):
        with pytest.raises(ValidationError):
            resolve_active_observing_night(payload(reference_time=rejected))


def test_day_difference_is_bounded_but_unobservable():
    """The bound only ever lands outside the index guard, so it changes nothing."""
    assert DAY_DIFFERENCE_BOUND == MAX_DAY_COUNT + 1
    zone = ZoneInfo(LA)
    far = _whole_days(instant("2026-02-18T08:00:00Z"), instant("2027-02-18T08:00:00Z"), zone)
    assert far == DAY_DIFFERENCE_BOUND
    assert resolve_active_observing_night(
        payload(reference_time="2027-02-18T13:00:00Z")
    )["state"] == "unavailable"


def test_day_cap():
    assert MAX_DAY_COUNT == 16
    assert resolve_active_observing_night(
        payload(daily_sun_events=DAYS * 4, daily_moon_count=16)
    )["state"] == "resolved"
    with pytest.raises(SampleCapError):
        resolve_active_observing_night(payload(daily_sun_events=DAYS * 5))
    # A scalar out of domain is validation, not a transported-array overflow.
    with pytest.raises(ValidationError) as caught:
        resolve_active_observing_night(payload(daily_moon_count=17))
    assert not isinstance(caught.value, SampleCapError)


def test_a_row_is_never_required_to_be_chronological():
    """Begin is that morning and end that evening, so rows read backwards."""
    for row in DAYS:
        assert row["astronomical_twilight_begin"] < row["astronomical_twilight_end"]
    inverted = [{"astronomical_twilight_begin": "2026-02-19T03:15:00Z",
                 "astronomical_twilight_end": "2026-02-18T13:35:00Z"}]
    result = resolve_active_observing_night(
        payload(reference_time="2026-02-19T05:00:00Z",
                forecast_start_time=None,
                daily_sun_events=inverted, daily_moon_count=1)
    )
    assert result["state"] == "resolved"
    assert result["astronomical_night_start"] == "2026-02-18T13:35:00Z"
    assert result["astronomical_night_end"] == "2026-02-19T03:15:00Z"


def test_result_always_carries_every_key():
    keys = {"state", "time_zone", "day_offset", "day_index", "observing_date",
            "observing_day_start", "astronomical_night_start", "astronomical_night_end"}
    for reference in ("2026-02-20T05:00:00Z", "2026-02-18T12:00:00Z", "2026-02-23T05:00:00Z"):
        assert set(resolve_active_observing_night(payload(reference_time=reference))) == keys
