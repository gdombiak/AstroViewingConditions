"""Deterministic planet recommendation from injected observation facts.

Normative procedure: contracts/procedures/planet-recommendation.md. Portable
form of the private math in the production
`DefaultPlanetTargetRecommendationProvider`. No ephemeris, no network: the
samples are injected and use the `astronomy.planet_observation` result's
`observation.samples`. Presentation copy (the English summary and its
poor-conditions branches) stays with the host.
"""

from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping, NamedTuple, Sequence

from astro_engine.contracts import load_canonical_data
from astro_engine.errors import SampleCapError, ValidationError
from astro_engine.validate import UTC_Z_PATTERN

CAPABILITY_ID = "targets.planet_recommendation"

# Swift `Date` counts seconds from 2001-01-01T00:00:00Z; matching the scale keeps
# interpolated window arithmetic bit-identical, as in targets.deep_sky_windows.
_REFERENCE_EPOCH = 978_307_200.0
_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

# Night interval range: the same fixed modern product range as
# targets.deep_sky_windows.
EARLIEST_EPOCH_SECONDS = 946_684_800.0
LATEST_EPOCH_SECONDS = 16_725_225_599.0

# --- bounded spill --------------------------------------------------------
#
# A valid astronomy.planet_observation bundle must be consumable verbatim, and
# that provider samples *outside* the night interval by construction. The spill
# is derived from production sampling and scoring semantics, not from a wish for
# unbounded timestamps. Each offset is a fixed transport literal rather than a
# calibration read, so tuning the scorer can never widen the accepted range.

SAMPLE_SPILL_BEFORE_SECONDS = 2 * 3600.0    # observation sampling lead
SAMPLE_SPILL_AFTER_SECONDS = 3600.0         # observation sampling trail
WINDOW_SPILL_AFTER_SECONDS = 3600.0 + 900.0  # trail + fixed final-sample extension
RATING_SPILL_BEFORE_SECONDS = 2 * 3600.0 + 3600.0  # lead + one rating hour
RATING_SPILL_AFTER_SECONDS = WINDOW_SPILL_AFTER_SECONDS  # a rating starts before the window end

# Injected sample instants: 1999-12-31T22:00:00Z ... 2500-01-01T00:59:59Z.
EARLIEST_SAMPLE_EPOCH_SECONDS = EARLIEST_EPOCH_SECONDS - SAMPLE_SPILL_BEFORE_SECONDS
LATEST_SAMPLE_EPOCH_SECONDS = LATEST_EPOCH_SECONDS + SAMPLE_SPILL_AFTER_SECONDS

# Injected hourly-rating instants: 1999-12-31T21:00:00Z ... 2500-01-01T01:14:59Z.
EARLIEST_RATING_EPOCH_SECONDS = EARLIEST_EPOCH_SECONDS - RATING_SPILL_BEFORE_SECONDS
LATEST_RATING_EPOCH_SECONDS = LATEST_EPOCH_SECONDS + RATING_SPILL_AFTER_SECONDS

# Emitted window instants: a window opens no earlier than the first sample and
# closes no later than the last sample plus the fixed extension.
EARLIEST_WINDOW_EPOCH_SECONDS = EARLIEST_SAMPLE_EPOCH_SECONDS
LATEST_WINDOW_EPOCH_SECONDS = LATEST_EPOCH_SECONDS + WINDOW_SPILL_AFTER_SECONDS

# One day of one-minute rows, applied to both injected arrays.
MAX_ROW_COUNT = 1_440

SUPPORTED_TARGET_IDS = ("venus", "mars", "jupiter", "saturn")

# Interpolation guard from production `thresholdCrossing`. A structural numeric
# constant, not a product heuristic, so it is not calibrated.
THRESHOLD_CROSSING_EPSILON_DEGREES = 0.0001

_COMPASS = (
    "N", "NNE", "NE", "ENE",
    "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW",
    "W", "WNW", "NW", "NNW",
)


class Sample(NamedTuple):
    time: float
    altitude: float
    azimuth: float
    solar_elongation: float | None


class Rating(NamedTuple):
    time: float
    score: float


class Window(NamedTuple):
    start: float
    end: float
    best_time: float
    max_altitude: float
    direction: str
    azimuth: float

    @property
    def duration(self) -> float:
        return self.end - self.start


class Result(NamedTuple):
    score: int
    window: Window
    reasons: tuple[str, ...]


def calibration() -> dict:
    return load_canonical_data("calibration/planet-recommendation.json")


def compass_direction(azimuth: float) -> str:
    """Sixteen-point objective code with round-half-away-from-zero."""
    normalized = math.fmod(math.fmod(azimuth, 360.0) + 360.0, 360.0)
    quotient = normalized / 22.5
    whole = math.floor(quotient)
    index = whole + int(quotient - whole >= 0.5)
    return _COMPASS[index % len(_COMPASS)]


def _clamp(value: float, low: float, high: float) -> float:
    return min(max(value, low), high)


def visible_samples(samples: Sequence[Sample], cal: dict) -> list[Sample]:
    """Inclusive `>=` visible-altitude filter."""
    threshold = cal["visibility"]["minimum_altitude_degrees"]
    return [sample for sample in samples if sample.altitude >= threshold]


def altitude_quality(altitude: float, cal: dict) -> float:
    return _clamp(altitude / cal["visibility"]["altitude_normalization_degrees"], 0, 1)


def low_altitude_penalty(altitude: float, cal: dict) -> float:
    low = cal["low_altitude"]
    return low["penalty"] if altitude < low["below_degrees"] else 0.0


def convenience_score(time: float, night_start: float, night_end: float, cal: dict) -> float:
    """The evening band is tested first, so an instant inside both bands is evening."""
    bounds = cal["convenience"]
    evening_start = night_start - bounds["evening_lead_seconds"]
    evening_end = night_start + bounds["evening_trail_seconds"]
    if evening_start <= time <= evening_end:
        return bounds["evening"]
    if time >= night_end - bounds["late_night_lead_seconds"]:
        return bounds["late_night"]
    return bounds["otherwise"]


def weighted_score(sample: Sample, night_start: float, night_end: float, cal: dict) -> float:
    weights = cal["best_sample"]
    altitude = altitude_quality(sample.altitude, cal)
    darkness = 1.0 if night_start <= sample.time <= night_end else weights["outside_darkness_quality"]
    convenience = convenience_score(sample.time, night_start, night_end, cal)
    return (altitude * weights["altitude_weight"]
            + darkness * weights["darkness_weight"]
            + convenience * weights["convenience_weight"])


def threshold_crossing(first: Sample, second: Sample, cal: dict) -> float:
    change = second.altitude - first.altitude
    if not abs(change) > THRESHOLD_CROSSING_EPSILON_DEGREES:
        return first.time
    fraction = _clamp(
        (cal["visibility"]["minimum_altitude_degrees"] - first.altitude) / change, 0, 1)
    return first.time + (second.time - first.time) * fraction


def visibility_window(samples: Sequence[Sample], visible: Sequence[Sample],
                      best: Sample, cal: dict) -> Window:
    """Interior crossings interpolate against the visible-altitude threshold.

    A run that ends on the final sample extends by the fixed
    `window_extension_seconds` literal, which production does not tie to the
    sampling cadence even though both default to 900 s.
    """
    extension = cal["visibility"]["window_extension_seconds"]
    times = [sample.time for sample in samples]
    first_visible = visible[0] if visible else None
    last_visible = visible[-1] if visible else None
    first_index = times.index(first_visible.time) if first_visible is not None else None
    last_index = (len(times) - 1 - times[::-1].index(last_visible.time)
                  if last_visible is not None else None)

    if first_visible is not None and first_index is not None and first_index > 0:
        start = threshold_crossing(samples[first_index - 1], first_visible, cal)
    else:
        start = first_visible.time if first_visible is not None else best.time

    if last_visible is not None and last_index is not None and last_index < len(times) - 1:
        end = threshold_crossing(last_visible, samples[last_index + 1], cal)
    else:
        end = (last_visible.time if last_visible is not None else best.time) + extension

    return Window(
        start=start,
        end=end,
        best_time=best.time,
        max_altitude=best.altitude,
        direction=compass_direction(best.azimuth),
        azimuth=best.azimuth,
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


def overlap_fraction(window_start: float, window_end: float,
                     darkness_start: float, darkness_end: float) -> float:
    if not window_end > window_start:
        return 0.0
    overlap_start = max(window_start, darkness_start)
    overlap_end = min(window_end, darkness_end)
    if not overlap_end > overlap_start:
        return 0.0
    return (overlap_end - overlap_start) / (window_end - window_start)


def venus_twilight_suitability(best: Sample, window: Window, night_start: float,
                               night_end: float, cal: dict) -> float:
    twilight = cal["venus_twilight"]
    is_evening = (best.time < night_start
                  and window.end > night_start - twilight["eligibility_window_seconds"])
    is_morning = (best.time > night_end
                  and window.start < night_end + twilight["eligibility_window_seconds"])
    if not (is_evening or is_morning):
        return 0.0

    altitude = _clamp(
        (best.altitude - cal["visibility"]["minimum_altitude_degrees"])
        / twilight["altitude_span_degrees"], 0, 1)
    duration = _clamp(window.duration / twilight["useful_duration_seconds"], 0, 1)
    elongation = _clamp(
        ((best.solar_elongation if best.solar_elongation is not None else 0)
         - twilight["elongation_offset_degrees"]) / twilight["elongation_span_degrees"], 0, 1)

    return (altitude * twilight["altitude_weight"]
            + duration * twilight["duration_weight"]
            + elongation * twilight["elongation_weight"])


def visibility_quality(target_id: str, best: Sample, window: Window, darkness_overlap: float,
                       night_start: float, night_end: float, cal: dict) -> float:
    """Every body except Venus scores visibility as astronomical-darkness overlap."""
    if target_id.lower() != "venus":
        return darkness_overlap
    return max(darkness_overlap,
               venus_twilight_suitability(best, window, night_start, night_end, cal))


def score(altitude: float, weather: float, visibility: float, convenience: float,
          cal: dict) -> int:
    weights = cal["weights"]
    raw = (altitude_quality(altitude, cal) * weights["altitude"]
           + weather * weights["weather"]
           + visibility * weights["visibility"]
           + convenience * weights["convenience"]
           - low_altitude_penalty(altitude, cal))
    clamped = _clamp(raw, cal["score"]["min"], cal["score"]["max"])
    whole = math.floor(clamped)
    return whole + int(clamped - whole >= 0.5)


def reasons(best: Sample, weather: float, darkness_overlap: float,
            convenience: float, cal: dict) -> tuple[str, ...]:
    """Production order. `astronomicalDarkness` keys on the darkness overlap,
    not on the Venus twilight-adjusted visibility quality."""
    bounds = cal["reasons"]
    result: list[str] = []

    if best.altitude >= bounds["high_altitude_at_or_above_degrees"]:
        result.append("highAltitude")
    elif best.altitude < bounds["low_altitude_below_degrees"]:
        result.append("lowAltitude")

    if darkness_overlap >= bounds["darkness_overlap_at_or_above"]:
        result.append("astronomicalDarkness")

    if convenience >= bounds["convenient_at_or_above"]:
        result.append("convenientPlanetWindow")
    elif convenience <= bounds["late_or_early_at_or_below"]:
        result.append("lateOrEarlyPlanetWindow")

    if weather >= bounds["good_weather_at_or_above"]:
        result.append("goodNightQuality")
    elif weather < bounds["poor_weather_below"]:
        result.append("poorWeather")

    result.append("planetMoonlightResistant")
    return tuple(result)


def evaluate(target_id: str, samples: Sequence[Sample], night_start: float, night_end: float,
             cloud_cover_score: float, ratings: Sequence[Rating], cal: dict) -> Result | None:
    """`None` is "no planet recommendation tonight", the production nil case."""
    visible = visible_samples(samples, cal)
    if not visible:
        return None

    # Ties keep the earliest sample, matching Swift `max(by:)`.
    best = visible[0]
    for candidate in visible[1:]:
        if (weighted_score(best, night_start, night_end, cal)
                < weighted_score(candidate, night_start, night_end, cal)):
            best = candidate

    window = visibility_window(samples, visible, best, cal)
    weather = weather_quality(window, cloud_cover_score, ratings, cal)
    darkness_overlap = overlap_fraction(window.start, window.end, night_start, night_end)
    convenience = convenience_score(best.time, night_start, night_end, cal)
    visibility = visibility_quality(target_id, best, window, darkness_overlap,
                                    night_start, night_end, cal)
    return Result(
        score=score(best.altitude, weather, visibility, convenience, cal),
        window=window,
        reasons=reasons(best, weather, darkness_overlap, convenience, cal),
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


def _reference_seconds(
    value: Any,
    not_before: float = EARLIEST_EPOCH_SECONDS,
    not_after: float = LATEST_EPOCH_SECONDS,
) -> float:
    """`night_start` / `night_end` keep the plain night range; injected sample and
    rating instants pass their own bounded-spill limits."""
    if not isinstance(value, str) or not UTC_Z_PATTERN.fullmatch(value):
        raise _invalid()
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError as exc:
        raise _invalid() from exc
    seconds = (parsed - _EPOCH).total_seconds()
    if not not_before <= seconds <= not_after:
        raise _invalid()
    return seconds - _REFERENCE_EPOCH


def _timestamp(reference_seconds: float) -> str:
    """Bounded inputs make the emitted instant provably inside the window range,
    so this guard never rejects a legitimate result; it stays as a fail-closed
    backstop and keeps Swift and Python symmetric."""
    if not math.isfinite(reference_seconds):
        raise _invalid()
    seconds = math.floor(reference_seconds + _REFERENCE_EPOCH)
    if not EARLIEST_WINDOW_EPOCH_SECONDS <= seconds <= LATEST_WINDOW_EPOCH_SECONDS:
        raise _invalid()
    # isoformat preserves four-digit years even where strftime('%Y') does not.
    return (_EPOCH + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")


def _parse_samples(value: Any) -> list[Sample]:
    """Strictly ordered instants: production's index lookups only have one
    meaning for a strictly ordered series."""
    if not isinstance(value, list):
        raise _invalid()
    if len(value) > MAX_ROW_COUNT:
        raise SampleCapError(f"{CAPABILITY_ID} exceeds the 1.0 row cap ({MAX_ROW_COUNT} rows)")
    samples: list[Sample] = []
    for row in value:
        if not isinstance(row, Mapping) or set(row) != {
            "time", "altitude", "azimuth", "solar_elongation"
        }:
            raise _invalid()
        time = _reference_seconds(row["time"], EARLIEST_SAMPLE_EPOCH_SECONDS,
                                  LATEST_SAMPLE_EPOCH_SECONDS)
        if samples and time <= samples[-1].time:
            raise _invalid()
        samples.append(Sample(time, _number(row["altitude"]), _number(row["azimuth"]),
                              _optional_number(row["solar_elongation"])))
    return samples


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
        rows.append(Rating(
            _reference_seconds(row["time"], EARLIEST_RATING_EPOCH_SECONDS,
                               LATEST_RATING_EPOCH_SECONDS),
            _number(row["score"]),
        ))
    return rows


def recommend_planet(input: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(input, Mapping):
        raise _invalid()
    allowed = {"target_id", "night_start", "night_end", "samples",
               "cloud_cover_score", "hourly_ratings"}
    if set(input) != allowed:
        raise _invalid()
    target_id = input["target_id"]
    if not isinstance(target_id, str) or target_id not in SUPPORTED_TARGET_IDS:
        raise _invalid()

    # Field order matches the Swift transport so a document with more than one
    # defect reports the same code and message on both hosts.
    night_start = _reference_seconds(input["night_start"])
    night_end = _reference_seconds(input["night_end"])
    samples = _parse_samples(input["samples"])
    cloud_cover_score = _number(input["cloud_cover_score"])
    ratings = _parse_ratings(input["hourly_ratings"])

    result = evaluate(target_id, samples, night_start, night_end,
                      cloud_cover_score, ratings, calibration())
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
