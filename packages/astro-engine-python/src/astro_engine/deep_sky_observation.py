"""Deep-sky observation facts: closed-form horizontal position plus visible runs.

Normative procedure: contracts/procedures/deep-sky-observation.md. Deterministic —
no ephemeris provider, no network, no refraction. Instant arithmetic mirrors the
production Swift `Date` reference epoch (2001-01-01T00:00:00Z) so both hosts
execute the same binary64 operations.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping, NamedTuple, Sequence

from astro_engine.catalog import load_deep_sky_catalog
from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.validate import UTC_Z_PATTERN

POSITION_CAPABILITY_ID = "astronomy.horizontal_position"
WINDOWS_CAPABILITY_ID = "targets.deep_sky_windows"
CAPABILITY_IDS = (POSITION_CAPABILITY_ID, WINDOWS_CAPABILITY_ID)

DEFAULT_MINIMUM_ALTITUDE = 15.0
DEFAULT_SAMPLE_INTERVAL = 15 * 60.0

# Swift `Date` counts seconds from 2001-01-01T00:00:00Z. Production sampling and
# interpolation add/subtract on that scale; matching it keeps the last bit equal.
_REFERENCE_EPOCH = 978_307_200.0
_COMPASS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

# Fixed modern product range, 2000-01-01T00:00:00Z through 2499-12-31T23:59:59Z
# inclusive. Deliberately not a historical astronomy range: the lower bound sits
# well after the 1582 Gregorian cutover, where Foundation falls back to the Julian
# calendar while `datetime` stays proleptic Gregorian, so the two hosts would
# resolve the same string to different instants. See the procedure.
EARLIEST_EPOCH_SECONDS = 946_684_800.0
LATEST_EPOCH_SECONDS = 16_725_225_599.0

# 1.0 capability cap on sampling work: seven days of one-minute cadence. The
# production geometry is a single astronomical night at the 900 s default, at most
# ~96 samples even for a maximal polar night, so this admits every product request
# by more than two orders of magnitude while bounding worst-case work.
MAX_SAMPLE_COUNT = 10_080


class Position(NamedTuple):
    altitude: float
    azimuth: float


class Sample(NamedTuple):
    time: float
    """Seconds since the 2001-01-01T00:00:00Z reference epoch."""
    altitude: float
    azimuth: float


class Window(NamedTuple):
    start: float
    end: float
    best_time: float
    max_altitude: float
    azimuth: float
    direction: str


def _radians(value: float) -> float:
    """Swift `value * .pi / 180` — two roundings, not CPython's single constant."""
    return value * math.pi / 180


def _degrees(value: float) -> float:
    """Swift `value * 180 / .pi` — two roundings, not CPython's single constant."""
    return value * 180 / math.pi


def normalized_degrees(value: float) -> float:
    result = math.fmod(value, 360.0)
    return result if result >= 0 else result + 360.0


def _normalized_signed_degrees(value: float) -> float:
    normalized = normalized_degrees(value)
    return normalized - 360.0 if normalized > 180.0 else normalized


def compass_direction(azimuth: float) -> str:
    return _COMPASS[int((normalized_degrees(azimuth) + 22.5) / 45) % len(_COMPASS)]


def horizontal_position(
    right_ascension_hours: float,
    declination_degrees: float,
    latitude_degrees: float,
    longitude_degrees: float,
    reference_seconds: float,
) -> Position:
    """Geometric altitude/azimuth. `reference_seconds` is on the 2001 epoch."""
    julian_date = (reference_seconds + _REFERENCE_EPOCH) / 86_400 + 2_440_587.5
    days_since_j2000 = julian_date - 2_451_545.0
    greenwich_sidereal = normalized_degrees(280.46061837 + 360.98564736629 * days_since_j2000)
    local_sidereal = normalized_degrees(greenwich_sidereal + longitude_degrees)
    hour_angle = _radians(_normalized_signed_degrees(local_sidereal - right_ascension_hours * 15))
    declination = _radians(declination_degrees)
    latitude = _radians(latitude_degrees)

    # Clamp: binary64 can push the spherical identity outside [-1, 1].
    sine_altitude = min(max(
        math.sin(declination) * math.sin(latitude)
        + math.cos(declination) * math.cos(latitude) * math.cos(hour_angle),
        -1.0,
    ), 1.0)
    altitude = math.asin(sine_altitude)
    azimuth = math.atan2(
        math.sin(hour_angle),
        math.cos(hour_angle) * math.sin(latitude) - math.tan(declination) * math.cos(latitude),
    ) + math.pi
    return Position(_degrees(altitude), normalized_degrees(_degrees(azimuth)))


def samples(
    right_ascension_hours: float,
    declination_degrees: float,
    latitude_degrees: float,
    longitude_degrees: float,
    start: float,
    end: float,
    sample_interval: float = DEFAULT_SAMPLE_INTERVAL,
) -> list[Sample]:
    """Inclusive-endpoint samples by repeated addition of `sample_interval`."""
    result: list[Sample] = []
    time = start
    while time <= end:
        position = horizontal_position(
            right_ascension_hours,
            declination_degrees,
            latitude_degrees,
            longitude_degrees,
            time,
        )
        result.append(Sample(time, position.altitude, position.azimuth))
        time = time + sample_interval
    return result


def threshold_crossing(first: Sample, second: Sample, minimum_altitude: float) -> float:
    altitude_change = second.altitude - first.altitude
    if abs(altitude_change) <= 0.0001:
        return first.time
    fraction = min(max((minimum_altitude - first.altitude) / altitude_change, 0.0), 1.0)
    return first.time + (second.time - first.time) * fraction


def windows(
    rows: Sequence[Sample],
    interval_start: float,
    interval_end: float,
    minimum_altitude: float = DEFAULT_MINIMUM_ALTITUDE,
) -> list[Window]:
    """One window per maximal contiguous run of samples at or above threshold."""
    result: list[Window] = []
    run_start: int | None = None
    last_index = len(rows) - 1

    for index, row in enumerate(rows):
        is_visible = row.altitude >= minimum_altitude
        if is_visible and run_start is None:
            run_start = index

        run_ended = run_start is not None and (not is_visible or index == last_index)
        if not run_ended:
            continue
        assert run_start is not None
        end_index = index if is_visible else index - 1
        run = rows[run_start:end_index + 1]
        if not run:
            continue
        # Ties keep the earliest sample, matching Swift `max(by:)`.
        best = run[0]
        for candidate in run[1:]:
            if best.altitude < candidate.altitude:
                best = candidate

        start = (
            interval_start
            if run_start == 0
            else threshold_crossing(rows[run_start - 1], rows[run_start], minimum_altitude)
        )
        end = (
            interval_end
            if end_index == last_index
            else threshold_crossing(rows[end_index], rows[end_index + 1], minimum_altitude)
        )
        result.append(Window(
            start=start,
            end=end,
            best_time=best.time,
            max_altitude=best.altitude,
            azimuth=best.azimuth,
            direction=compass_direction(best.azimuth),
        ))
        run_start = None

    return result


def exceeds_sample_cap(start: float, end: float, sample_interval: float) -> bool:
    """True when a forward interval would need more than `MAX_SAMPLE_COUNT` samples.

    Bounded work: one ULP query, one division and a few comparisons. Never runs
    the sampling loop.
    Mirrors `location.grid`'s `exceeds_contract_point_cap` preflight.

    An inverted interval is not a cap: it yields no samples and does no work, the
    same way non-positive grid radius/spacing is not a cap. A step too small to
    advance binary64 at the largest magnitude in range would never terminate the
    loop, so it counts as unbounded; checking the larger-magnitude endpoint is
    sufficient because the ULP is monotonic in magnitude.
    """
    span = end - start
    if span < 0:
        return False
    pivot = start if abs(start) >= abs(end) else end
    if not pivot + sample_interval > pivot:
        return True
    # `floor(span / sample_interval) + 1` counts the mathematical series
    # `start + k * interval`, which the repeated-addition loop does not follow:
    # every `time + interval` is rounded to nearest, so the realized step can be
    # up to half a ULP smaller than requested and the loop can emit more samples
    # than that quotient predicts. Bound with the smallest step the loop can take.
    effective_interval = sample_interval - math.ulp(abs(pivot)) / 2
    if effective_interval <= 0:
        return True
    quotient = span / effective_interval
    # Iterations are at most floor(quotient) + 1, so that is <= MAX <=> quotient < MAX.
    return not (math.isfinite(quotient) and quotient < MAX_SAMPLE_COUNT)


def observe(
    right_ascension_hours: float,
    declination_degrees: float,
    latitude_degrees: float,
    longitude_degrees: float,
    start: float,
    end: float,
    minimum_altitude: float = DEFAULT_MINIMUM_ALTITUDE,
    sample_interval: float = DEFAULT_SAMPLE_INTERVAL,
) -> list[Window]:
    rows = samples(
        right_ascension_hours,
        declination_degrees,
        latitude_degrees,
        longitude_degrees,
        start,
        end,
        sample_interval,
    )
    return windows(rows, start, end, minimum_altitude)


# --- transport ------------------------------------------------------------


def _invalid(capability: str) -> ValidationError:
    return ValidationError(f"invalid {capability} input")


def _number(value: Any, capability: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid(capability)
    number = float(value)
    if not math.isfinite(number):
        raise _invalid(capability)
    return number


def _reference_seconds(value: Any, capability: str) -> float:
    if not isinstance(value, str) or not UTC_Z_PATTERN.fullmatch(value):
        raise _invalid(capability)
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise _invalid(capability) from exc
    epoch_seconds = (parsed - _EPOCH).total_seconds()
    if not EARLIEST_EPOCH_SECONDS <= epoch_seconds <= LATEST_EPOCH_SECONDS:
        raise _invalid(capability)
    return epoch_seconds - _REFERENCE_EPOCH


def _timestamp(reference_seconds: float, capability: str) -> str:
    """Floor to the whole second and enforce the same range as on input.

    Window endpoints lie inside the injected interval, so an in-range request
    cannot produce an out-of-range instant.
    """
    if not math.isfinite(reference_seconds):
        raise _invalid(capability)
    seconds = math.floor(reference_seconds + _REFERENCE_EPOCH)
    if not EARLIEST_EPOCH_SECONDS <= seconds <= LATEST_EPOCH_SECONDS:
        raise _invalid(capability)
    # isoformat preserves four-digit years even where strftime('%Y') does not.
    return (_EPOCH + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")


def _evaluate_position(input: Mapping[str, Any]) -> dict[str, Any]:
    capability = POSITION_CAPABILITY_ID
    if set(input) != {"right_ascension", "declination", "latitude", "longitude", "time"}:
        raise _invalid(capability)
    position = horizontal_position(
        _number(input["right_ascension"], capability),
        _number(input["declination"], capability),
        _number(input["latitude"], capability),
        _number(input["longitude"], capability),
        _reference_seconds(input["time"], capability),
    )
    return {"altitude": position.altitude, "azimuth": position.azimuth}


def _evaluate_windows(input: Mapping[str, Any]) -> dict[str, Any]:
    capability = WINDOWS_CAPABILITY_ID
    allowed = {
        "target_id", "right_ascension", "declination", "latitude", "longitude",
        "night_start", "night_end", "minimum_altitude", "sample_interval_seconds",
    }
    if set(input) - allowed or not {"latitude", "longitude", "night_start", "night_end"} <= set(input):
        raise _invalid(capability)

    has_coordinates = "right_ascension" in input or "declination" in input
    if "target_id" in input:
        identifier = input["target_id"]
        if has_coordinates or not isinstance(identifier, str):
            raise _invalid(capability)
        entry = next((row for row in load_deep_sky_catalog() if row["id"] == identifier), None)
        if entry is None:
            raise _invalid(capability)
        right_ascension = float(entry["right_ascension"])
        declination = float(entry["declination"])
    else:
        if "right_ascension" not in input or "declination" not in input:
            raise _invalid(capability)
        right_ascension = _number(input["right_ascension"], capability)
        declination = _number(input["declination"], capability)

    minimum_altitude = (
        _number(input["minimum_altitude"], capability)
        if "minimum_altitude" in input
        else DEFAULT_MINIMUM_ALTITUDE
    )
    sample_interval = (
        _number(input["sample_interval_seconds"], capability)
        if "sample_interval_seconds" in input
        else DEFAULT_SAMPLE_INTERVAL
    )
    if not sample_interval > 0:
        raise _invalid(capability)

    start = _reference_seconds(input["night_start"], capability)
    end = _reference_seconds(input["night_end"], capability)
    if exceeds_sample_cap(start, end, sample_interval):
        raise SampleCapError(
            f"{capability} exceeds the 1.0 sample cap ({MAX_SAMPLE_COUNT} samples)"
        )
    rows = observe(
        right_ascension,
        declination,
        _number(input["latitude"], capability),
        _number(input["longitude"], capability),
        start,
        end,
        minimum_altitude,
        sample_interval,
    )
    return {
        "windows": [
            {
                "start": _timestamp(row.start, capability),
                "end": _timestamp(row.end, capability),
                "best_time": _timestamp(row.best_time, capability),
                "max_altitude": row.max_altitude,
                "azimuth": row.azimuth,
                "direction": row.direction,
            }
            for row in rows
        ]
    }


def evaluate_deep_sky_observation(capability: str, input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping):
        raise _invalid(capability)
    if capability == POSITION_CAPABILITY_ID:
        return _evaluate_position(input)
    if capability == WINDOWS_CAPABILITY_ID:
        return _evaluate_windows(input)
    raise _invalid(capability)
