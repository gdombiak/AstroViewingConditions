"""observing_night.resolve_active — which local observing night is "Tonight".

The portable form of the production cross-midnight authority. It resolves no
timezone, fetches nothing and scores nothing: the caller supplies an already
resolved IANA zone, the reference instant, the first hourly-forecast timestamp
used for day indexing, the per-day astronomical twilight pair, and how many
daily Moon rows the same payload carries.

Normative procedure: contracts/procedures/observing-night.md.
"""

from __future__ import annotations

from datetime import date as civil_date, datetime, timedelta, timezone
from typing import Any, Mapping, NamedTuple, Sequence
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from astro_engine.contracts import load_canonical_data
from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.validate import format_utc_z, parse_utc_z

CAPABILITY_ID = "observing_night.resolve_active"

# The shared engine instant transport, as the target capabilities define it.
EARLIEST_EPOCH_SECONDS = 946_684_800.0     # 2000-01-01T00:00:00Z
LATEST_EPOCH_SECONDS = 16_725_225_599.0    # 2499-12-31T23:59:59Z

# `BestSpotSearcher.maxForecastDays` is the largest daily payload production
# ever builds, so it is the day cap for both daily arrays.
MAX_DAY_COUNT = 16

# One past the day cap, and the largest magnitude the day difference is computed
# to. Both daily arrays are capped at MAX_DAY_COUNT, so any elapsed-day count of
# this magnitude already fails the index guard and the payload is `unavailable`
# whatever the exact number is. Beyond this bound Foundation and this emulation
# can disagree by a day on multi-month spans that cross a base-offset change;
# stopping here keeps that region unobservable through the transport instead of
# silently divergent. Swift keeps Foundation's own unbounded value because the
# same array caps make it equally unobservable there.
DAY_DIFFERENCE_BOUND = MAX_DAY_COUNT + 1

# The public transport accepts exactly the catalogued shared location-style
# timezone identifiers: the slash-form names present in both Foundation's
# knownTimeZoneIdentifiers and zoneinfo.available_timezones(). Platform parser
# quirks (Foundation's GMT-0800, a host tzdata's private names) must not define
# the public API. The catalogue is symmetric across hosts, not canonical-IANA-
# only: historical aliases both runtimes publish are included.
TIMEZONE_POLICY_PATH = "timezones/observing-night-zones.json"

DAY_KEYS = {"astronomical_twilight_end", "astronomical_twilight_begin"}
INPUT_KEYS = {
    "reference_time",
    "time_zone",
    "forecast_start_time",
    "daily_sun_events",
    "daily_moon_count",
}

_ALLOWED_TIMEZONES: frozenset[str] | None = None

STATE_RESOLVED = "resolved"
STATE_REQUIRES_ACTIVE_PREVIOUS_PAYLOAD = "requires_active_previous_payload"
STATE_UNAVAILABLE = "unavailable"


class DailySunEvents(NamedTuple):
    """The only two Sun facts the decision consumes.

    `astronomical_twilight_begin` is that civil day's **morning** and
    `astronomical_twilight_end` its **evening**, so a row is expected to read
    "backwards" and no chronological ordering is imposed on it.
    """

    astronomical_twilight_end: datetime
    astronomical_twilight_begin: datetime


class ObservingNight(NamedTuple):
    day_offset: int
    day_index: int
    observing_day_start: datetime
    observing_local_date: civil_date
    astronomical_night_start: datetime
    astronomical_night_end: datetime


# --- Foundation-equivalent local-calendar arithmetic -------------------------
#
# Production runs a Gregorian `Calendar` pinned to the location zone. These
# three helpers reproduce exactly the Foundation operations that decision uses
# and nothing else; they are deliberately not a general calendar utility.


_Wall = tuple[int, int, int, int, int, int]


def _wall_of(local: datetime) -> _Wall:
    return (local.year, local.month, local.day, local.hour, local.minute, local.second)


def _earliest_local(wall: _Wall, zone: ZoneInfo) -> datetime:
    """Resolve a local wall time to its earliest instant, as `startOfDay` does.

    `fold=0` selects the earlier occurrence of a repeated wall time, and for a
    skipped wall time it applies the pre-transition offset, which yields the
    transition instant — the first valid moment at or after the request.
    """
    return datetime(*wall, tzinfo=zone, fold=0).astimezone(timezone.utc)


def _start_of_day(instant: datetime, zone: ZoneInfo) -> datetime:
    """`Calendar.startOfDay(for:)` — the first moment of the local civil day."""
    local = instant.astimezone(zone)
    return _earliest_local((local.year, local.month, local.day, 0, 0, 0), zone)


def _add_days(instant: datetime, days: int, zone: ZoneInfo) -> datetime:
    """`Calendar.date(byAdding: .day, value:)` — shifts the local civil date.

    Foundation does **not** resolve the shifted wall time the way `startOfDay`
    does. Where the source instant's own UTC offset still reproduces the
    requested wall time it keeps that offset, which on a repeated local midnight
    selects the *later* occurrence rather than the earlier one — the observable
    difference from `startOfDay` in zones such as `America/Havana` and
    `Atlantic/Azores`. Only when the source offset cannot express the requested
    wall time does it fall back to the earliest-instant resolution, which is what
    produces the transition instant on a skipped local midnight.

    Both branches are derived from a differential scan of Foundation across
    every known zone; see contracts/procedures/observing-night.md.
    """
    local = instant.astimezone(zone)
    target = civil_date(local.year, local.month, local.day) + timedelta(days=days)
    wall = (target.year, target.month, target.day,
            local.hour, local.minute, local.second)
    candidate = datetime(*wall, tzinfo=timezone.utc) - local.utcoffset()
    if _wall_of(candidate.astimezone(zone)) == wall:
        return candidate
    if _date_exists(target, zone):
        return _earliest_local(wall, zone)
    # The whole civil date was skipped by a line crossing (Pacific/Apia and
    # Pacific/Fakaofo dropped 2011-12-30). There is no wall time to resolve, and
    # Foundation degenerates to plain 24-hour arithmetic.
    return instant + timedelta(days=days)


def _date_exists(day: civil_date, zone: ZoneInfo) -> bool:
    """Whether any instant falls on this local civil date."""
    first = _earliest_local((day.year, day.month, day.day, 0, 0, 0), zone)
    local = first.astimezone(zone)
    return (local.year, local.month, local.day) == (day.year, day.month, day.day)


def _whole_days(start: datetime, end: datetime, zone: ZoneInfo) -> int:
    """`Calendar.dateComponents([.day], from:to:)` — signed whole local days.

    Foundation returns the largest day count, toward zero, that still fits
    inside the interval. On a zone whose DST transition is at local midnight the
    two endpoints can be first-moments an hour apart in wall time, and the count
    is then one lower than the plain civil-date difference. That quirk is
    production behaviour and is preserved rather than normalised.

    The magnitude is bounded by `DAY_DIFFERENCE_BOUND`; see that constant.
    """
    sign = 1 if end >= start else -1
    local_start, local_end = start.astimezone(zone), end.astimezone(zone)
    estimate = min(
        DAY_DIFFERENCE_BOUND,
        abs(
            (civil_date(local_end.year, local_end.month, local_end.day)
             - civil_date(local_start.year, local_start.month, local_start.day)).days
        ) + 1,
    )
    count = estimate
    while count > 0:
        moved = _add_days(start, sign * count, zone)
        if (moved <= end) if sign == 1 else (moved >= end):
            break
        count -= 1
    return sign * count


def _same_local_day(left: datetime, right: datetime, zone: ZoneInfo) -> bool:
    """`Calendar.isDate(_:inSameDayAs:)`."""
    a, b = left.astimezone(zone), right.astimezone(zone)
    return (a.year, a.month, a.day) == (b.year, b.month, b.day)


# --- The decision ------------------------------------------------------------


def _night(
    day_offset: int,
    reference_time: datetime,
    zone: ZoneInfo,
    forecast_start_time: datetime | None,
    daily_sun_events: Sequence[DailySunEvents],
    daily_moon_count: int,
) -> ObservingNight | None:
    reference_day = _start_of_day(reference_time, zone)
    if forecast_start_time is not None:
        first_forecast_day = _start_of_day(forecast_start_time, zone)
        day_index = _whole_days(first_forecast_day, reference_day, zone) + day_offset
    else:
        day_index = day_offset

    if day_index < 0 or day_index >= len(daily_sun_events) or day_index >= daily_moon_count:
        return None

    observing_day_start = _add_days(reference_day, day_offset, zone)
    local = observing_day_start.astimezone(zone)
    today = daily_sun_events[day_index]
    next_index = day_index + 1
    tomorrow = daily_sun_events[next_index] if next_index < len(daily_sun_events) else None
    return ObservingNight(
        day_offset=day_offset,
        day_index=day_index,
        observing_day_start=observing_day_start,
        observing_local_date=civil_date(local.year, local.month, local.day),
        astronomical_night_start=today.astronomical_twilight_end,
        astronomical_night_end=(
            tomorrow.astronomical_twilight_begin
            if tomorrow is not None
            else today.astronomical_twilight_begin
        ),
    )


def select(
    reference_time: datetime,
    zone: ZoneInfo,
    forecast_start_time: datetime | None,
    daily_sun_events: Sequence[DailySunEvents],
    daily_moon_count: int,
) -> tuple[str, ObservingNight | None]:
    """Preceding night first, then the reference civil date.

    Both preceding-night comparisons are inclusive, and so is the
    "before this morning's twilight" comparison that reports
    `requires_active_previous_payload`.
    """
    previous = _night(
        -1, reference_time, zone, forecast_start_time, daily_sun_events, daily_moon_count
    )
    if (
        previous is not None
        and previous.astronomical_night_start <= reference_time <= previous.astronomical_night_end
    ):
        return STATE_RESOLVED, previous

    current = _night(
        0, reference_time, zone, forecast_start_time, daily_sun_events, daily_moon_count
    )
    if current is None:
        return STATE_UNAVAILABLE, None

    # The observing day of offset 0 is the reference day, so this same-local-day
    # guard is always satisfied. It is reproduced rather than assumed away.
    if _same_local_day(current.observing_day_start, reference_time, zone) and (
        reference_time <= daily_sun_events[current.day_index].astronomical_twilight_begin
    ):
        return STATE_REQUIRES_ACTIVE_PREVIOUS_PAYLOAD, None
    return STATE_RESOLVED, current


# --- Transport ---------------------------------------------------------------


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


def allowed_timezone_identifiers() -> frozenset[str]:
    """The catalogued shared identifier set both hosts accept, from contracts/data."""
    global _ALLOWED_TIMEZONES
    if _ALLOWED_TIMEZONES is None:
        document = load_canonical_data(TIMEZONE_POLICY_PATH)
        _ALLOWED_TIMEZONES = frozenset(document["identifiers"])
    return _ALLOWED_TIMEZONES


def _zone(value: Any) -> ZoneInfo:
    if not isinstance(value, str) or value not in allowed_timezone_identifiers():
        raise _invalid()
    try:
        return ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, KeyError) as exc:
        # The identifier is catalogued but this runtime's tzdata lacks it.
        raise _invalid() from exc


def _require_no_skipped_civil_date(
    reference_time: datetime,
    forecast_start_time: datetime | None,
    zone: ZoneInfo,
) -> None:
    """Reject zones that dropped an entire civil date inside the usable window.

    A line crossing (`Pacific/Apia` and `Pacific/Fakaofo` dropped 2011-12-30) is
    the one case where Foundation's day arithmetic is not reproducible here, so
    the contract excludes it explicitly on both hosts instead of diverging
    silently. Ordinary DST zones are unaffected: only a missing civil *date*
    triggers this, never a missing hour.
    """
    local_reference = reference_time.astimezone(zone)
    first = civil_date(local_reference.year, local_reference.month, local_reference.day)
    if forecast_start_time is not None:
        local_forecast = forecast_start_time.astimezone(zone)
        first = min(
            first,
            civil_date(local_forecast.year, local_forecast.month, local_forecast.day),
        )
    # One day back covers the dayOffset -1 probe, then the bounded window.
    for offset in range(-1, DAY_DIFFERENCE_BOUND + 1):
        if not _date_exists(first + timedelta(days=offset), zone):
            raise _invalid()


def _day_rows(value: Any) -> list[DailySunEvents]:
    if not isinstance(value, list):
        raise _invalid()
    if len(value) > MAX_DAY_COUNT:
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 day cap ({MAX_DAY_COUNT} days)"
        )
    rows = []
    for raw in value:
        if not isinstance(raw, Mapping) or set(raw) != DAY_KEYS:
            raise _invalid()
        rows.append(DailySunEvents(
            astronomical_twilight_end=_instant(raw["astronomical_twilight_end"]),
            astronomical_twilight_begin=_instant(raw["astronomical_twilight_begin"]),
        ))
    return rows


def _moon_count(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid()
    number = float(value)
    if number != int(number) or not 0 <= number <= MAX_DAY_COUNT:
        raise _invalid()
    return int(number)


def resolve_active_observing_night(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping) or set(input) != INPUT_KEYS:
        raise _invalid()

    identifier = input["time_zone"]
    zone = _zone(identifier)
    reference_time = _instant(input["reference_time"])
    raw_forecast_start = input["forecast_start_time"]
    forecast_start_time = None if raw_forecast_start is None else _instant(raw_forecast_start)
    daily_sun_events = _day_rows(input["daily_sun_events"])
    daily_moon_count = _moon_count(input["daily_moon_count"])
    _require_no_skipped_civil_date(reference_time, forecast_start_time, zone)

    state, night = select(
        reference_time, zone, forecast_start_time, daily_sun_events, daily_moon_count
    )
    # Every key is always present; a state that carries no night reports JSON
    # null rather than omitting the field, so the three states stay distinct.
    result: dict[str, Any] = {
        "state": state,
        "time_zone": identifier,
        "day_offset": None,
        "day_index": None,
        "observing_date": None,
        "observing_day_start": None,
        "astronomical_night_start": None,
        "astronomical_night_end": None,
    }
    if night is not None:
        result.update({
            "day_offset": night.day_offset,
            "day_index": night.day_index,
            "observing_date": night.observing_local_date.isoformat(),
            "observing_day_start": format_utc_z(night.observing_day_start),
            "astronomical_night_start": format_utc_z(night.astronomical_night_start),
            "astronomical_night_end": format_utc_z(night.astronomical_night_end),
        })
    return result
