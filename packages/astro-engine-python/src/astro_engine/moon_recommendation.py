"""Deterministic lunar recommendation from injected observation facts.

Normative procedure: contracts/procedures/moon-recommendation.md. Portable form
of the private math in the production `DefaultMoonTargetRecommendationProvider`.
No ephemeris, no network: the Moon fact bundle is injected and uses the
`astronomy.moon_observation` result minus its echoed interval. Presentation copy (summary text,
phase names, emoji) stays with the host.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping, NamedTuple, Sequence

from astro_engine.contracts import load_canonical_data
from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.validate import UTC_Z_PATTERN

CAPABILITY_ID = "targets.moon_recommendation"

# Swift `Date` counts seconds from 2001-01-01T00:00:00Z; matching the scale keeps
# window arithmetic bit-identical, as in targets.deep_sky_windows.
_REFERENCE_EPOCH = 978_307_200.0
_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

# Same fixed modern product range as targets.deep_sky_windows.
EARLIEST_EPOCH_SECONDS = 946_684_800.0
LATEST_EPOCH_SECONDS = 16_725_225_599.0

# One day of one-minute rows, applied to both injected arrays.
MAX_ROW_COUNT = 1_440

_COMPASS = (
    "N", "NNE", "NE", "ENE",
    "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW",
    "W", "WNW", "NW", "NNW",
)


class Sample(NamedTuple):
    time: float
    altitude: float
    azimuth: float | None


class Rating(NamedTuple):
    time: float
    score: float


class Observation(NamedTuple):
    phase: float
    illumination: int
    rise: float | None
    set: float | None
    always_up: bool
    always_down: bool
    samples: tuple[Sample, ...]


class Window(NamedTuple):
    start: float
    end: float
    best_time: float
    max_altitude: float | None
    direction: str | None
    azimuth: float | None


class Result(NamedTuple):
    score: int
    window: Window
    reasons: tuple[str, ...]


def calibration() -> dict:
    return load_canonical_data("calibration/moon-recommendation.json")


def compass_direction(azimuth: float) -> str:
    """Sixteen-point objective code with round-half-away-from-zero.

    Deliberately not the eight-point deep-sky code: the Moon path has always
    reported sixteen points.
    """
    normalized = math.fmod(math.fmod(azimuth, 360.0) + 360.0, 360.0)
    quotient = normalized / 22.5
    whole = math.floor(quotient)
    index = whole + int(quotient - whole >= 0.5)
    return _COMPASS[index % len(_COMPASS)]


def _clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def _quarter_distance(phase: float) -> float:
    return min(abs(phase - 0.25), abs(phase - 0.75))


def _is_near_new_moon(observation: Observation, cal: dict) -> bool:
    bounds = cal["near_new_moon"]
    return (
        observation.illumination <= bounds["illumination_at_or_below_percent"]
        or observation.phase <= bounds["phase_at_or_below"]
        or observation.phase >= bounds["phase_at_or_above"]
    )


def phase_quality(observation: Observation, cal: dict) -> float:
    if _is_near_new_moon(observation, cal):
        return cal["near_new_moon"]["phase_quality"]
    quality = cal["phase_quality"]
    if _quarter_distance(observation.phase) <= quality["quarter_distance_at_or_below"]:
        return quality["quarter"]
    if observation.illumination <= quality["crescent_illumination_at_or_below_percent"]:
        return quality["crescent"]
    if observation.illumination >= quality["bright_illumination_at_or_above_percent"]:
        return quality["bright"]
    return quality["otherwise"]


def visible_fraction(samples: Sequence[Sample], cal: dict) -> float:
    if not samples:
        return 0.0
    threshold = cal["visibility"]["above_altitude_degrees"]
    visible = sum(1 for sample in samples if sample.altitude > threshold)
    return visible / len(samples)


def visibility_window(
    useful_start: float,
    useful_end: float,
    visible: Sequence[Sample],
    best: Sample | None,
    cal: dict,
) -> Window:
    """The `window_extension_seconds` extension is a fixed literal in production
    and is independent of the observation sampling cadence."""
    extension = cal["visibility"]["window_extension_seconds"]
    best_time = best.time if best is not None else useful_start + (useful_end - useful_start) / 2
    start = visible[0].time if visible else useful_start
    end = visible[-1].time + extension if visible else useful_end
    return Window(
        start=max(start, useful_start),
        end=min(max(end, start + extension), useful_end),
        best_time=best_time,
        max_altitude=None if best is None else best.altitude,
        direction=None if best is None or best.azimuth is None else compass_direction(best.azimuth),
        azimuth=None if best is None else best.azimuth,
    )


def weather_quality(window: Window, cloud_cover_score: float,
                    ratings: Sequence[Rating], cal: dict) -> float:
    weather = cal["weather"]
    overlapping = [
        rating for rating in ratings
        if rating.time + weather["hourly_rating_seconds"] > window.start and rating.time < window.end
    ]
    if not overlapping:
        return 1 - _clamp(cloud_cover_score / weather["cloud_cover_percent_divisor"], 0, 1)
    # Python 3.12+ sum(float) compensates; the contract requires ordered binary64 addition.
    total = 0.0
    for rating in overlapping:
        total += rating.score
    average = total / len(overlapping)
    return 1 - _clamp(average / weather["overlap_score_divisor"], 0, 1)


def score(observation: Observation, fraction: float, weather: float, cal: dict) -> int:
    weights = cal["weights"]
    raw = (
        phase_quality(observation, cal) * weights["phase"]
        + fraction * weights["visibility"]
        + weather * weights["weather"]
    )
    near_new = cal["near_new_moon"]
    capped = (
        min(raw, near_new["score_cap"])
        if observation.illumination <= near_new["illumination_at_or_below_percent"]
        else raw
    )
    clamped = _clamp(capped, cal["score"]["min"], cal["score"]["max"])
    whole = math.floor(clamped)
    return whole + int(clamped - whole >= 0.5)


def reasons(observation: Observation, useful_start: float, useful_end: float,
            visible: Sequence[Sample], fraction: float, weather: float,
            cal: dict) -> tuple[str, ...]:
    result: list[str] = []
    useful_minimum = cal["visibility"]["useful_fraction_at_or_above"]

    if not visible or fraction < useful_minimum or observation.always_down:
        result.append("moonBelowUsefulWindow")

    if _is_near_new_moon(observation, cal):
        result.append("newMoonDarkSky")
    elif _quarter_distance(observation.phase) <= cal["phase_quality"]["quarter_distance_at_or_below"]:
        result.append("excellentMoonCraterDetail")
    elif observation.illumination >= cal["phase_quality"]["bright_illumination_at_or_above_percent"]:
        result.append("brightFullMoonDeepSkyImpact")
    elif fraction >= useful_minimum:
        result.append("moonVisibleUsefulWindow")

    sets_early = cal["moon_sets_early"]
    if (
        observation.set is not None
        and observation.set > useful_start
        and observation.set < useful_end - sets_early["remaining_dark_seconds"]
        and observation.illumination >= sets_early["illumination_at_or_above_percent"]
    ):
        result.append("moonSetsEarlyDarkSkyLater")

    if weather < cal["weather"]["poor_below"]:
        result.append("poorWeather")

    return tuple(result) if result else ("moonVisibleUsefulWindow",)


def evaluate(observation: Observation, night_start: float, night_end: float,
             best_window: tuple[float, float] | None, cloud_cover_score: float,
             ratings: Sequence[Rating], cal: dict) -> Result | None:
    """`None` is "no lunar recommendation tonight", the production nil case."""
    useful_start = best_window[0] if best_window is not None else night_start
    useful_end = best_window[1] if best_window is not None else night_end
    useful = [s for s in observation.samples if useful_start <= s.time <= useful_end]
    threshold = cal["visibility"]["above_altitude_degrees"]
    visible = [s for s in useful if s.altitude > threshold]
    if not visible:
        return None

    # Ties keep the earliest sample, matching Swift `max(by:)`.
    best = visible[0]
    for candidate in visible[1:]:
        if best.altitude < candidate.altitude:
            best = candidate

    window = visibility_window(useful_start, useful_end, visible, best, cal)
    fraction = visible_fraction(useful, cal)
    weather = weather_quality(window, cloud_cover_score, ratings, cal)
    return Result(
        score=score(observation, fraction, weather, cal),
        window=window,
        reasons=reasons(observation, useful_start, useful_end, visible, fraction, weather, cal),
    )


# --- transport ------------------------------------------------------------


def _invalid() -> ValidationError:
    return ValidationError(f"invalid {CAPABILITY_ID} input")


def _number(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise _invalid()
    try:
        number = float(value)
    except OverflowError as exc:
        raise _invalid() from exc
    if not math.isfinite(number):
        raise _invalid()
    return number


def _optional_number(value: Any) -> float | None:
    return None if value is None else _number(value)


def _integer(value: Any) -> int:
    number = _number(value)
    if number != math.trunc(number) or abs(number) > 1_000_000_000:
        raise _invalid()
    return int(number)


def _boolean(value: Any) -> bool:
    if not isinstance(value, bool):
        raise _invalid()
    return value


def _reference_seconds(value: Any) -> float:
    if not isinstance(value, str) or not UTC_Z_PATTERN.fullmatch(value):
        raise _invalid()
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise _invalid() from exc
    seconds = (parsed - _EPOCH).total_seconds()
    if not EARLIEST_EPOCH_SECONDS <= seconds <= LATEST_EPOCH_SECONDS:
        raise _invalid()
    return seconds - _REFERENCE_EPOCH


def _optional_reference_seconds(value: Any) -> float | None:
    return None if value is None else _reference_seconds(value)


def _timestamp(reference_seconds: float) -> str:
    if not math.isfinite(reference_seconds):
        raise _invalid()
    seconds = math.floor(reference_seconds + _REFERENCE_EPOCH)
    if not EARLIEST_EPOCH_SECONDS <= seconds <= LATEST_EPOCH_SECONDS:
        raise _invalid()
    # isoformat preserves four-digit years even where strftime('%Y') does not.
    return (_EPOCH + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")


def _parse_best_window(value: Any) -> tuple[float, float] | None:
    """Omitted and explicit null both mean "no best conditions window"."""
    if value is None:
        return None
    if not isinstance(value, Mapping) or set(value) != {"start", "end"}:
        raise _invalid()
    return _reference_seconds(value["start"]), _reference_seconds(value["end"])


def _parse_observation(value: Any) -> Observation:
    expected = {"phase", "illumination", "rise", "set", "always_up", "always_down", "samples"}
    if not isinstance(value, Mapping) or set(value) != expected:
        raise _invalid()
    raw = value["samples"]
    if not isinstance(raw, list):
        raise _invalid()
    if len(raw) > MAX_ROW_COUNT:
        raise SampleCapError(f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)")
    samples: list[Sample] = []
    for row in raw:
        if not isinstance(row, Mapping) or set(row) != {"time", "altitude", "azimuth"}:
            raise _invalid()
        time = _reference_seconds(row["time"])
        if samples and time <= samples[-1].time:
            raise _invalid()
        samples.append(Sample(time, _number(row["altitude"]), _optional_number(row["azimuth"])))
    # MoonObservationData clamps both on construction; the host does the same.
    return Observation(
        phase=_clamp(_number(value["phase"]), 0.0, 1.0),
        illumination=int(_clamp(_integer(value["illumination"]), 0, 100)),
        rise=_optional_reference_seconds(value["rise"]),
        set=_optional_reference_seconds(value["set"]),
        always_up=_boolean(value["always_up"]),
        always_down=_boolean(value["always_down"]),
        samples=tuple(samples),
    )


def _parse_ratings(value: Any) -> list[Rating]:
    """Caller order is preserved: production never sorts the hourly ratings."""
    if not isinstance(value, list):
        raise _invalid()
    if len(value) > MAX_ROW_COUNT:
        raise SampleCapError(f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)")
    rows: list[Rating] = []
    for row in value:
        if not isinstance(row, Mapping) or set(row) != {"time", "score"}:
            raise _invalid()
        rows.append(Rating(_reference_seconds(row["time"]), _number(row["score"])))
    return rows


def recommend_moon(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping):
        raise _invalid()
    allowed = {"night_start", "night_end", "best_window", "moon", "cloud_cover_score", "hourly_ratings"}
    required = allowed - {"best_window"}
    if set(input) - allowed or not required <= set(input):
        raise _invalid()

    cal = calibration()
    result = evaluate(
        _parse_observation(input["moon"]),
        _reference_seconds(input["night_start"]),
        _reference_seconds(input["night_end"]),
        _parse_best_window(input.get("best_window")),
        _number(input["cloud_cover_score"]),
        _parse_ratings(input["hourly_ratings"]),
        cal,
    )
    if result is None:
        return {"recommendation": None}
    window = result.window
    return {
        "recommendation": {
            "score": result.score,
            "visibility_window": {
                "start": _timestamp(window.start),
                "end": _timestamp(window.end),
                "best_time": _timestamp(window.best_time),
                "max_altitude": window.max_altitude,
                "direction": window.direction,
                "azimuth": window.azimuth,
            },
            "reasons": list(result.reasons),
        }
    }
