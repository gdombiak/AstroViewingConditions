"""Calendar/DST derivation for a nighttime hourly-forecast window.

This is the portable form of the production Swift `NightForecastFilter` rule.
Timezone acquisition, Sun-event calculation and forecast filtering remain
caller composition. Normative procedure:
contracts/procedures/night-forecast-window.md.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Mapping, NamedTuple
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from astro_engine.errors import ValidationError
from astro_engine.observing_night import (
    EARLIEST_EPOCH_SECONDS,
    LATEST_EPOCH_SECONDS,
    _add_days,
    _start_of_day,
    allowed_timezone_identifiers,
)
from astro_engine.validate import format_utc_z, parse_utc_z

CAPABILITY_ID = "night_forecast.derive_window"

INPUT_KEYS = {
    "observing_time",
    "time_zone",
    "astronomical_twilight_end",
    "astronomical_twilight_begin",
    "tomorrow_astronomical_twilight_begin",
}


class NightForecastWindow(NamedTuple):
    start: datetime
    end: datetime


_HALF_SECOND = timedelta(microseconds=500_000)
_HOUR = timedelta(hours=1)
_MINUTE = timedelta(minutes=1)
_SECOND = timedelta(seconds=1)

# Foundation abandons an enumeration after this many rounds and returns nil.
_MAX_SEARCH_ROUNDS = 101

# Loop guards. Foundation only leaves its field loops on a match or on its own
# not-advancing check; these bounds cannot be reached by any real zone and exist
# so a corrupt tzdata cannot hang the process.
_MAX_FIELD_STEPS = 10_000


def _interval_start(instant: datetime, zone: ZoneInfo, unit_seconds: int) -> datetime:
    """Start of `Calendar.dateInterval(of:for:)` for `.hour` and `.minute`.

    Foundation aligns these intervals to the local wall clock, not to the
    containing day, so a partial-hour offset jump re-aligns the field search at
    the transition instead of carrying the day's residue forward. The interval
    length stays a nominal 3600/60 seconds even where the next wall-clock
    boundary is nearer or further, which is what makes the search observable
    across gaps.
    """
    local = instant.astimezone(zone)
    elapsed = timedelta(seconds=local.second, microseconds=local.microsecond)
    if unit_seconds == 3600:
        elapsed += timedelta(minutes=local.minute)
    return instant - elapsed


def _day_interval_end(instant: datetime, zone: ZoneInfo) -> datetime:
    """End of `Calendar.dateInterval(of: .day, for:)` — the next day's start."""
    return _start_of_day(_add_days(_start_of_day(instant, zone), 1, zone), zone)


def _matches(instant: datetime, hour: int, minute: int, zone: ZoneInfo) -> bool:
    """`Calendar.date(_:containsMatchingComponents:)` for this component set."""
    local = instant.astimezone(zone)
    return (local.hour, local.minute, local.second, local.microsecond) == (
        hour, minute, 0, 0,
    )


def _adjusted_for_missing_hour(
    instant: datetime, zone: ZoneInfo
) -> datetime | None:
    """`Calendar._adjustedDateForMismatchedHour(...)` under `.nextTime`.

    An hour-only mismatch is forgiven only when the candidate sits immediately
    before or immediately after a one-label forward jump; the match then moves
    to the transition boundary. Every other hour mismatch is a real miss.
    """
    found = _interval_start(instant, zone, 3600)
    current_hour = found.astimezone(zone).hour
    following = found + _HOUR
    next_hour = following.astimezone(zone).hour
    if next_hour - current_hour > 1 or (current_hour == 23 and next_hour > 0):
        return following
    previous_hour = (found - _SECOND).astimezone(zone).hour
    if current_hour - previous_hour > 1 or (previous_hour == 23 and current_hour > 0):
        return found
    return None


def _matching_date(
    start: datetime, hour: int, minute: int, zone: ZoneInfo
) -> datetime:
    """`Calendar._matchingDate(after:matching:)` for `{hour, minute, second: 0}`.

    Foundation matches hour, then minute, then second as independent forward
    field searches over calendar unit intervals. It is not equivalent to
    resolving one complete local datetime, which is why a clock that plainly
    exists on the search day can still be passed over.
    """
    result = start
    date_hour = result.astimezone(zone).hour
    adjusted = False

    # A local day that begins after 00:00 is already a non-strict match for
    # hour 0; the rewinding below would otherwise never reach it.
    if hour == 0:
        day_begin = _start_of_day(result, zone)
        first_hour = day_begin.astimezone(zone).hour
        if first_hour != 0 and date_hour == first_hour:
            result = day_begin
            adjusted = True

    if hour != date_hour and not adjusted:
        for _ in range(_MAX_FIELD_STEPS):
            last = result
            found = _interval_start(result, zone, 3600)
            previous_hour = date_hour
            following = found + _HOUR
            date_hour = following.astimezone(zone).hour
            # Foundation's deliberately narrow forward-DST recognition: a
            # one-label skipped hour, including 23 -> 1. Other positive jumps
            # continue the field search and can reach a later civil day.
            if date_hour - previous_hour == 2 or (
                previous_hour == 23 and date_hour == 1
            ):
                date_hour -= 1
                result = found
            else:
                result = following
            adjusted = True
            if result == last and previous_hour == date_hour:
                raise ValueError("calendar hour search is not advancing")
            if hour == date_hour:
                break
        else:
            raise ValueError("cannot resolve local wall-time hour")

    if not adjusted:
        # The hour already matches, so clear the smaller components.
        result = _interval_start(result, zone, 3600)

    if minute != result.astimezone(zone).minute:
        for _ in range(_MAX_FIELD_STEPS):
            following = _interval_start(result, zone, 60) + _MINUTE
            if following == result:
                raise ValueError("calendar minute search is not advancing")
            result = following
            if result.astimezone(zone).minute == minute:
                break
        else:
            raise ValueError("cannot resolve local wall-time minute")
    else:
        result = _interval_start(result, zone, 60)

    # Second zero is already satisfied by the minute-interval start.
    return result


def _next_date(
    start: datetime, hour: int, minute: int, zone: ZoneInfo
) -> datetime | None:
    """`Calendar.nextDate(after:matching:)`, `.nextTime` / `.first` / forward."""
    searching = start
    for _ in range(_MAX_SEARCH_ROUNDS):
        match = _matching_date(searching, hour, minute, zone)

        forward_dst = False
        if not _matches(match, hour, minute, zone):
            adjusted = _adjusted_for_missing_hour(match, zone)
            if adjusted is not None:
                forward_dst = True
                match = adjusted
            else:
                # Only the hour can mismatch for this component set, so
                # Foundation restarts the field search at the next day's start.
                match = _matching_date(
                    _day_interval_end(searching, zone), hour, minute, zone
                )
        exact = _matches(match, hour, minute, zone)

        # Bump the search past the next-higher unit, or just past the candidate
        # when the candidate already overshot it.
        following_day = _day_interval_end(searching, zone)
        searching = following_day if match < following_day else match + _SECOND

        if match < start:
            # The candidate went backwards. When the matched hour repeats we can
            # advance by one hour instead of a whole day and pick up the second
            # occurrence, which is what a fall-back across midnight needs.
            match_hour = match.astimezone(zone).hour
            repeated = match + _HOUR
            if repeated.astimezone(zone).hour == match_hour:
                searching = repeated
            continue
        if not (exact or forward_dst):
            continue
        if match == start:
            continue
        return match
    return None


def _set_wall_time(day: datetime, hour: int, minute: int, zone: ZoneInfo) -> datetime:
    """Foundation `Calendar.date(bySettingHour:minute:second:of:)`, second zero.

    Foundation searches forward from half a second before the containing day's
    first instant, so the search can begin on the previous civil date, and it
    re-runs from the day's first instant if that produced an earlier result.
    """
    day_start = _start_of_day(day, zone)
    result = _next_date(day_start - _HALF_SECOND, hour, minute, zone)
    if result is not None and result < day_start:
        result = _next_date(day_start, hour, minute, zone)
    if result is None:
        raise ValueError("cannot resolve local wall time")
    return result


def derive_window(
    observing_time: datetime,
    zone: ZoneInfo,
    astronomical_twilight_end: datetime,
    astronomical_twilight_begin: datetime,
    tomorrow_astronomical_twilight_begin: datetime | None,
) -> NightForecastWindow:
    """Project Sun-event hour/minute components onto the observing local days."""
    start_of_day = _start_of_day(observing_time, zone)
    next_day = _add_days(start_of_day, 1, zone)

    dusk = astronomical_twilight_end.astimezone(zone)
    start = _set_wall_time(start_of_day, dusk.hour, dusk.minute, zone)

    dawn_source = tomorrow_astronomical_twilight_begin or astronomical_twilight_begin
    dawn = dawn_source.astimezone(zone)
    end = _set_wall_time(next_day, dawn.hour, dawn.minute, zone)
    return NightForecastWindow(start=start, end=end)


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def _instant(value: Any) -> datetime:
    try:
        parsed = parse_utc_z(value, "instant")
    except ValidationError as exc:
        raise _invalid() from exc
    if not EARLIEST_EPOCH_SECONDS <= parsed.timestamp() <= LATEST_EPOCH_SECONDS:
        raise _invalid()
    return parsed


def _zone(value: Any) -> ZoneInfo:
    if not isinstance(value, str) or value not in allowed_timezone_identifiers():
        raise _invalid()
    try:
        return ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, KeyError) as exc:
        raise _invalid() from exc


def derive_night_forecast_window(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping) or set(input) != INPUT_KEYS:
        raise _invalid()

    identifier = input["time_zone"]
    zone = _zone(identifier)
    raw_tomorrow = input["tomorrow_astronomical_twilight_begin"]
    tomorrow = None if raw_tomorrow is None else _instant(raw_tomorrow)
    try:
        window = derive_window(
            observing_time=_instant(input["observing_time"]),
            zone=zone,
            astronomical_twilight_end=_instant(input["astronomical_twilight_end"]),
            astronomical_twilight_begin=_instant(input["astronomical_twilight_begin"]),
            tomorrow_astronomical_twilight_begin=tomorrow,
        )
    except (OverflowError, ValueError) as exc:
        raise _invalid() from exc
    for instant in window:
        if not EARLIEST_EPOCH_SECONDS <= instant.timestamp() <= LATEST_EPOCH_SECONDS:
            raise _invalid()
    return {
        "time_zone": identifier,
        "start": format_utc_z(window.start),
        "end": format_utc_z(window.end),
    }
