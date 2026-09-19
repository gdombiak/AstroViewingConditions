"""observing_night.compose_outlook and observing_night.select_best.

The portable form of the production three-night outlook day composition. It
resolves no timezone, fetches nothing and scores nothing: the active-night
decision and every day-arithmetic rule come from `observing_night`
(`observing_night.resolve_active`), which this module reuses rather than
reimplements. Scores, best windows, labels, verdicts, tone and every cache or
persistence concern stay with the host.

Normative procedure: contracts/procedures/night-outlook.md.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any, Mapping, NamedTuple, Sequence
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.observing_night import (
    DailySunEvents,
    EARLIEST_EPOCH_SECONDS,
    LATEST_EPOCH_SECONDS,
    MAX_DAY_COUNT,
    STATE_REQUIRES_ACTIVE_PREVIOUS_PAYLOAD,
    STATE_RESOLVED,
    STATE_UNAVAILABLE,
    _add_days,
    _start_of_day,
    allowed_timezone_identifiers,
    has_skipped_civil_date,
    night as observing_night,
    select as select_observing_night,
)
from astro_engine.validate import format_utc_z, parse_utc_z

CAPABILITY_ID = "observing_night.compose_outlook"
BEST_NIGHT_CAPABILITY_ID = "observing_night.select_best"

# The outlook is exactly three nights; production has no other length.
NIGHT_COUNT = 3

# One day of one-minute rows, the shared 1.0 row cap. Production hourly payloads
# are far smaller; the cap only bounds the transport.
MAX_HOURLY_ROW_COUNT = 1_440

# Both public score capabilities clamp to this closed range, so a score outside
# it never comes from the engine.
MINIMUM_SCORE = 0
MAXIMUM_SCORE = 100

EXPECTED_HOURLY_CADENCE = 3600.0
CADENCE_TOLERANCE = 60.0

STATUS_AVAILABLE = "available"
STATUS_NO_ASTRONOMICAL_NIGHT = "no_astronomical_night"
STATUS_UNAVAILABLE = "unavailable"
NIGHT_STATUSES = frozenset(
    {STATUS_AVAILABLE, STATUS_NO_ASTRONOMICAL_NIGHT, STATUS_UNAVAILABLE}
)

DAY_KEYS = {"astronomical_twilight_end", "astronomical_twilight_begin"}
INPUT_KEYS = {
    "reference_time",
    "time_zone",
    "forecast_start_time",
    "daily_sun_events",
    "daily_moon_count",
    "hourly_times",
}
BEST_NIGHT_INPUT_KEYS = {"nights"}
BEST_NIGHT_ROW_KEYS = {"status", "score"}


class OutlookNight(NamedTuple):
    """One composed slot.

    `slot_index` is the position the host renders (0 is the active observing
    night). `day_offset` is that slot's offset from the local reference day.
    `day_index` is None on a fallback row, which selected no day at all, and both
    boundaries are None there too.
    """

    slot_index: int
    day_offset: int
    day_index: int | None
    observing_day_start: datetime
    observing_local_date: Any
    astronomical_night_start: datetime | None
    astronomical_night_end: datetime | None
    status: str


class Outlook(NamedTuple):
    state: str
    nights: list[OutlookNight]


class BestNightCandidate(NamedTuple):
    status: str
    score: int | None


# --- Composition -------------------------------------------------------------


def compose(
    reference_time: datetime,
    zone: ZoneInfo,
    forecast_start_time: datetime | None,
    daily_sun_events: Sequence[DailySunEvents],
    daily_moon_count: int,
    hourly_times: Sequence[datetime],
) -> Outlook:
    """The active observing night plus the next two local civil days."""
    state, active = select_observing_night(
        reference_time, zone, forecast_start_time, daily_sun_events, daily_moon_count
    )
    if active is None:
        return Outlook(
            state=(
                STATE_REQUIRES_ACTIVE_PREVIOUS_PAYLOAD
                if state == STATE_REQUIRES_ACTIVE_PREVIOUS_PAYLOAD
                else STATE_UNAVAILABLE
            ),
            nights=_fallback_nights(reference_time, zone),
        )

    # Production derives the same first offset by differencing the reference day
    # against the resolved observing day, which is the exact inverse of the day
    # shift that produced it.
    resolved = [
        found
        for found in (
            observing_night(
                active.day_offset + slot,
                reference_time,
                zone,
                forecast_start_time,
                daily_sun_events,
                daily_moon_count,
            )
            for slot in range(NIGHT_COUNT)
        )
        if found is not None
    ]
    if len(resolved) != NIGHT_COUNT:
        # All-or-nothing: production discards a partially composable outlook and
        # publishes the fallback rows instead.
        return Outlook(
            state=STATE_UNAVAILABLE, nights=_fallback_nights(reference_time, zone)
        )

    ordered_hourly = sorted(hourly_times)
    return Outlook(
        state=STATE_RESOLVED,
        nights=[
            OutlookNight(
                slot_index=slot,
                day_offset=found.day_offset,
                day_index=found.day_index,
                observing_day_start=found.observing_day_start,
                observing_local_date=found.observing_local_date,
                astronomical_night_start=found.astronomical_night_start,
                astronomical_night_end=found.astronomical_night_end,
                status=_status(
                    found.astronomical_night_start,
                    found.astronomical_night_end,
                    ordered_hourly,
                ),
            )
            for slot, found in enumerate(resolved)
        ],
    )


def _fallback_nights(reference_time: datetime, zone: ZoneInfo) -> list[OutlookNight]:
    """The rows production publishes when no outlook composes.

    The local reference day and the two days after it, with no boundaries and no
    score.
    """
    start = _start_of_day(reference_time, zone)
    nights = []
    for slot in range(NIGHT_COUNT):
        day = _add_days(start, slot, zone)
        local = day.astimezone(zone)
        nights.append(OutlookNight(
            slot_index=slot,
            day_offset=slot,
            day_index=None,
            observing_day_start=day,
            observing_local_date=local.date(),
            astronomical_night_start=None,
            astronomical_night_end=None,
            status=STATUS_UNAVAILABLE,
        ))
    return nights


def _status(
    start: datetime | None,
    end: datetime | None,
    ordered_hourly: Sequence[datetime],
) -> str:
    if start is None or end is None or not start < end:
        return STATUS_NO_ASTRONOMICAL_NIGHT
    return (
        STATUS_AVAILABLE
        if _has_complete_hourly_coverage(start, end, ordered_hourly)
        else STATUS_UNAVAILABLE
    )


def has_complete_hourly_coverage(
    astronomical_night_start: datetime,
    astronomical_night_end: datetime,
    hourly_times: Sequence[datetime],
) -> bool:
    """Whether the hourly stream continuously covers the whole astronomical night.

    Hourly timestamps represent the start of their interval, so an interval may
    contain a non-hour-aligned boundary. The nominal cadence is the median
    positive step across the whole stream and must itself be an hour within the
    tolerance; the covering rows must start at or before the night start, reach
    past the night end, and step by that cadence throughout. A duplicate
    timestamp or missing interval therefore breaks coverage. Caller ordering does
    not matter because timestamps are sorted first.
    """
    return _has_complete_hourly_coverage(
        astronomical_night_start, astronomical_night_end, sorted(hourly_times)
    )


def _has_complete_hourly_coverage(
    start: datetime,
    end: datetime,
    ordered_hourly: Sequence[datetime],
) -> bool:
    if not start < end:
        return False
    cadence = _nominal_hourly_cadence(ordered_hourly)
    if cadence is None:
        return False
    step = timedelta(seconds=cadence)
    relevant = [time for time in ordered_hourly if time <= end and time + step >= start]
    if not relevant:
        return False
    if not (relevant[0] <= start and relevant[-1] + step >= end):
        return False
    return all(
        abs((second - first).total_seconds() - cadence) <= CADENCE_TOLERANCE
        for first, second in zip(relevant, relevant[1:])
    )


def _nominal_hourly_cadence(ordered_hourly: Sequence[datetime]) -> float | None:
    """The median strictly positive step, accepted only when it is an hour.

    Zero steps from duplicate timestamps are excluded from the estimate but
    still break the continuity check above.
    """
    intervals = sorted(
        interval
        for interval in (
            (second - first).total_seconds()
            for first, second in zip(ordered_hourly, ordered_hourly[1:])
        )
        if interval > 0
    )
    if not intervals:
        return None
    cadence = intervals[len(intervals) // 2]
    if abs(cadence - EXPECTED_HOURLY_CADENCE) > CADENCE_TOLERANCE:
        return None
    return cadence


# --- Best-night selection ----------------------------------------------------


def select_best_night(candidates: Sequence[BestNightCandidate]) -> int | None:
    """The outlook's best night, or None when no row is eligible.

    Only an `available` row that carries a score participates. The highest score
    wins and a tie keeps the **earliest** eligible row, because production
    replaces the incumbent only on a strictly greater score. The supplied order
    is the semantics; nothing is sorted.
    """
    eligible = [
        index
        for index, candidate in enumerate(candidates)
        if candidate.status == STATUS_AVAILABLE and candidate.score is not None
    ]
    if not eligible:
        return None
    best = eligible[0]
    for candidate in eligible[1:]:
        best_score = candidates[best].score
        candidate_score = candidates[candidate].score
        if best_score is None or candidate_score is None:
            continue
        if candidate_score > best_score:
            best = candidate
    return best


# --- Transport ---------------------------------------------------------------


def _invalid(capability: str = CAPABILITY_ID) -> ValidationError:
    return ValidationError(f"invalid {capability} input")


def _instant(value: Any, capability: str = CAPABILITY_ID) -> datetime:
    try:
        parsed = parse_utc_z(value, "instant")
    except ValidationError as exc:
        raise _invalid(capability) from exc
    if not EARLIEST_EPOCH_SECONDS <= parsed.timestamp() <= LATEST_EPOCH_SECONDS:
        raise _invalid(capability)
    return parsed


def _in_range(moment: datetime) -> bool:
    return EARLIEST_EPOCH_SECONDS <= moment.timestamp() <= LATEST_EPOCH_SECONDS


def _zone(value: Any) -> ZoneInfo:
    if not isinstance(value, str) or value not in allowed_timezone_identifiers():
        raise _invalid()
    try:
        return ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, KeyError) as exc:
        # The identifier is catalogued but this runtime's tzdata lacks it.
        raise _invalid() from exc


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


def _hourly_times(value: Any) -> list[datetime]:
    """Only the hourly timestamps cross the transport.

    Caller order is not semantics here — the coverage rule sorts, exactly as
    production does.
    """
    if not isinstance(value, list):
        raise _invalid()
    if len(value) > MAX_HOURLY_ROW_COUNT:
        raise SampleCapError(
            f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_HOURLY_ROW_COUNT} rows)"
        )
    return [_instant(raw) for raw in value]


def compose_night_outlook(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping) or set(input) != INPUT_KEYS:
        raise _invalid()

    identifier = input["time_zone"]
    zone = _zone(identifier)
    reference_time = _instant(input["reference_time"])
    raw_forecast_start = input["forecast_start_time"]
    forecast_start_time = None if raw_forecast_start is None else _instant(raw_forecast_start)
    daily_sun_events = _day_rows(input["daily_sun_events"])
    daily_moon_count = _moon_count(input["daily_moon_count"])
    hourly_times = _hourly_times(input["hourly_times"])
    if has_skipped_civil_date(reference_time, forecast_start_time, zone):
        raise _invalid()

    outlook = compose(
        reference_time, zone, forecast_start_time,
        daily_sun_events, daily_moon_count, hourly_times,
    )
    # The two composed days after the reference day can leave the shared instant
    # range at its very end; the window is refused rather than reported outside
    # the transport's own domain.
    for row in outlook.nights:
        if not _in_range(row.observing_day_start):
            raise _invalid()

    return {
        "state": outlook.state,
        "time_zone": identifier,
        "nights": [
            {
                "slot_index": row.slot_index,
                "day_offset": row.day_offset,
                "day_index": row.day_index,
                "observing_date": row.observing_local_date.isoformat(),
                "observing_day_start": format_utc_z(row.observing_day_start),
                "astronomical_night_start": (
                    None if row.astronomical_night_start is None
                    else format_utc_z(row.astronomical_night_start)
                ),
                "astronomical_night_end": (
                    None if row.astronomical_night_end is None
                    else format_utc_z(row.astronomical_night_end)
                ),
                "status": row.status,
            }
            for row in outlook.nights
        ],
    }


def _score(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid(BEST_NIGHT_CAPABILITY_ID)
    number = float(value)
    if number != int(number) or not MINIMUM_SCORE <= number <= MAXIMUM_SCORE:
        raise _invalid(BEST_NIGHT_CAPABILITY_ID)
    return int(number)


def select_best_outlook_night(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping) or set(input) != BEST_NIGHT_INPUT_KEYS:
        raise _invalid(BEST_NIGHT_CAPABILITY_ID)
    rows = input["nights"]
    if not isinstance(rows, list):
        raise _invalid(BEST_NIGHT_CAPABILITY_ID)
    if len(rows) > NIGHT_COUNT:
        raise SampleCapError(
            f"{BEST_NIGHT_CAPABILITY_ID} exceeds the 1.0 row cap ({NIGHT_COUNT} rows)"
        )

    candidates = []
    for raw in rows:
        if not isinstance(raw, Mapping) or set(raw) != BEST_NIGHT_ROW_KEYS:
            raise _invalid(BEST_NIGHT_CAPABILITY_ID)
        status = raw["status"]
        if not isinstance(status, str) or status not in NIGHT_STATUSES:
            raise _invalid(BEST_NIGHT_CAPABILITY_ID)
        candidates.append(BestNightCandidate(status=status, score=_score(raw["score"])))

    return {"best_index": select_best_night(candidates)}
